//
//  VideoEditorClickSoundPlayer.swift
//  Snapzy
//
//  Live Studio click sound in the editor preview: on each playback tick, schedules the
//  clicks that fall inside a short look-ahead window at their host time. The player
//  item is never rebuilt; seeks and pauses drop anything already scheduled.
//

import AVFoundation
import Foundation

@MainActor
final class VideoEditorClickSoundPlayer {
  private static let lookAhead: TimeInterval = 0.15

  private var engine: AVAudioEngine?
  /// The engine ran at least once. A started engine found stopped was stopped by the
  /// system (output device change), so it is rebuilt against the new output rather
  /// than restarted with its old wiring.
  private var engineHasRun = false
  private var node: AVAudioPlayerNode?
  private var buffer: AVAudioPCMBuffer?
  private var placementsKey: [TimelineSequence.Placement] = []
  private var clickTimes: [TimeInterval] = []
  private var scheduled: Set<TimeInterval> = []
  private var lastTime: TimeInterval?

  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  /// Structural timeline times of every audible click for `placements`.
  static func sequenceTimes(clickSourceTimes: [TimeInterval], placements: [TimelineSequence.Placement]) -> [TimeInterval] {
    var times: [TimeInterval] = []
    for placement in placements where placement.clip.isPrimary {
      for source in clickSourceTimes where source >= placement.clip.sourceStart && source < placement.clip.sourceEnd {
        times.append(placement.sequenceTime(atSource: source))
      }
    }
    return VideoEditorClickSound.merge(times.sorted())
  }

  func update(
    enabled: Bool,
    clickSourceTimes: @autoclosure () -> [TimeInterval],
    placements: [TimelineSequence.Placement],
    sequenceTime now: TimeInterval,
    rate: Float,
    isPlaying: Bool,
    volume: Float
  ) {
    guard enabled, isPlaying, rate > 0 else {
      reset()
      return
    }
    if placements != placementsKey {
      placementsKey = placements
      clickTimes = Self.sequenceTimes(clickSourceTimes: clickSourceTimes(), placements: placements)
    }
    if let lastTime, now < lastTime - 0.01 || now - lastTime > 0.5 {
      node?.stop()
      scheduled.removeAll()
    }
    lastTime = now
    guard !clickTimes.isEmpty, let node = startIfNeeded(), let buffer else { return }
    node.volume = volume

    let windowEnd = now + Self.lookAhead * Double(rate)
    var index = firstIndex(atOrAfter: now)
    let hostNow = mach_absolute_time()
    while index < clickTimes.count, clickTimes[index] < windowEnd {
      let time = clickTimes[index]
      index += 1
      guard scheduled.insert(time).inserted else { continue }
      let delay = (time - now) / Double(rate)
      let hostTime = hostNow + AVAudioTime.hostTime(forSeconds: max(delay, 0))
      node.scheduleBuffer(buffer, at: AVAudioTime(hostTime: hostTime), options: [])
    }
    scheduled = scheduled.filter { $0 >= now - 1 }
  }

  func reset() {
    node?.stop()
    scheduled.removeAll()
    lastTime = nil
  }

  func shutdown() {
    reset()
    engine?.stop()
    engine = nil
    node = nil
    engineHasRun = false
  }

  /// Build the graph and preallocate its resources ahead of Play. Building the engine and
  /// touching `mainMixerNode` (audio device setup) on the first playing tick was a visible
  /// hitch on pressing Play. The engine is not started here, so nothing runs while idle.
  func prepare() {
    _ = makeGraphIfNeeded()
  }

  private func startIfNeeded() -> AVAudioPlayerNode? {
    if let engine, let node, engine.isRunning {
      if !node.isPlaying { node.play() }
      return node
    }
    if engineHasRun { shutdown() }
    guard let (engine, node) = makeGraphIfNeeded() else { return nil }
    do {
      try engine.start()
    } catch {
      DiagnosticLogger.shared.logError(.editor, error, "Click sound engine failed to start")
      shutdown()
      return nil
    }
    engineHasRun = true
    node.play()
    return node
  }

  private func makeGraphIfNeeded() -> (AVAudioEngine, AVAudioPlayerNode)? {
    if let engine, let node { return (engine, node) }
    let engine = AVAudioEngine()
    let node = AVAudioPlayerNode()
    engine.attach(node)
    let format = engine.mainMixerNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0,
          let monoFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)
    else { return nil }
    engine.connect(node, to: engine.mainMixerNode, format: monoFormat)
    engine.prepare()
    buffer = VideoEditorClickSound.makeBuffer(format: monoFormat)
    self.engine = engine
    self.node = node
    return (engine, node)
  }

  private func firstIndex(atOrAfter time: TimeInterval) -> Int {
    var low = 0, high = clickTimes.count
    while low < high {
      let mid = (low + high) / 2
      if clickTimes[mid] < time { low = mid + 1 } else { high = mid }
    }
    return low
  }
}
