//
//  VideoEditorAddedAudioPlayer.swift
//  Snapzy
//
//  Lightweight live-preview companion audio player for independent audio clips
//  (imported `.file` audio tracks, plus `.primary` audio whenever it is moved,
//  trimmed independently, split, or extends past the end of the video).
//
//  Clips at or below 100% volume play through `AVAudioPlayer` (`0.0 ... 1.0`).
//  Boosted audio files (`> 100%` up to `200%`) route through `AVAudioEngine`
//  (`AVAudioPlayerNode` + `AVAudioUnitTimePitch`), which applies true linear gain
//  above `1.0` matching `AVMutableAudioMixInputParameters` in export; when no
//  hardware output device or `AVAudioFile` reader is available (e.g. headless CI
//  or video-container sidecars), preview gracefully falls back to `AVAudioPlayer`
//  clamped at `1.0`.
//

import AVFoundation
import Foundation
import QuartzCore

@MainActor
final class VideoEditorAddedAudioPlayer {
  private final class BoostedClipChain {
    let url: URL
    let file: AVAudioFile
    let node: AVAudioPlayerNode
    let timePitch: AVAudioUnitTimePitch
    var anchorSourceTime: TimeInterval = 0
    var anchorHostTime: CFTimeInterval = 0
    var scheduledRate: Float = 1.0
    var isScheduledPlaying = false

    init(url: URL, file: AVAudioFile, node: AVAudioPlayerNode, timePitch: AVAudioUnitTimePitch) {
      self.url = url
      self.file = file
      self.node = node
      self.timePitch = timePitch
    }

    var duration: TimeInterval {
      let sr = file.processingFormat.sampleRate
      guard sr > 0 else { return 0 }
      return Double(file.length) / sr
    }

    func estimatedCurrentTime() -> TimeInterval {
      if isScheduledPlaying,
         let nodeTime = node.lastRenderTime,
         let playerTime = node.playerTime(forNodeTime: nodeTime),
         playerTime.sampleRate > 0 {
        return anchorSourceTime + Double(playerTime.sampleTime) / playerTime.sampleRate
      }
      if isScheduledPlaying {
        let elapsed = max(0, CACurrentMediaTime() - anchorHostTime)
        return anchorSourceTime + elapsed * Double(scheduledRate)
      }
      return anchorSourceTime
    }
  }

  private var players: [UUID: AVAudioPlayer] = [:]
  private var playerURLs: [UUID: URL] = [:]
  private var boostEngine: AVAudioEngine?
  private var boostEngineHasRun = false
  private var boostedChains: [UUID: BoostedClipChain] = [:]
  private var syncTimer: Timer?
  private var isPlaying = false
  private var currentTimelineTime: () -> TimeInterval = { 0 }
  private var currentPlaybackRate: () -> Float = { 1.0 }
  private var activeClips: [AudioTimelineClip] = []
  private var isMasterMuted = false
  private var mutedLanes: Set<Int> = []

  /// Supported `AVAudioPlayer.rate` / preview sync range (`0.5× ... 2.0×`). Outside this range
  /// (e.g. `0.25×`, `4×`, `8×`, or reverse shuttle), added audio pauses cleanly instead of stuttering.
  static let minSupportedRate: Float = 0.5
  static let maxSupportedRate: Float = 2.0

  /// Explicit and nonisolated: avoids macOS 13-15 swift_task_deinitOnExecutor abort (#668).
  nonisolated deinit {}

  func configure(
    clips: [AudioTimelineClip],
    includePrimary: Bool,
    urlProvider: (AudioTimelineClip) -> URL,
    isMasterMuted: Bool,
    mutedLanes: Set<Int> = [],
    playbackRateProvider: @escaping () -> Float = { 1.0 },
    timelineTimeProvider: @escaping () -> TimeInterval
  ) {
    activeClips = includePrimary ? clips : clips.filter { !$0.isPrimary }
    self.isMasterMuted = isMasterMuted
    self.mutedLanes = mutedLanes
    currentPlaybackRate = playbackRateProvider
    currentTimelineTime = timelineTimeProvider

    let validIds = Set(activeClips.map(\.id))
    for (id, player) in players where !validIds.contains(id) {
      player.stop()
      players.removeValue(forKey: id)
      playerURLs.removeValue(forKey: id)
    }
    for id in Array(boostedChains.keys) where !validIds.contains(id) {
      detachBoostedChain(id: id)
    }

    for clip in activeClips {
      let url = urlProvider(clip)
      if boostedChains[clip.id] != nil, boostedChains[clip.id]?.url != url {
        detachBoostedChain(id: clip.id)
      }
      if players[clip.id] != nil, playerURLs[clip.id] == url {
        continue
      }
      players[clip.id]?.stop()
      guard let audioPlayer = try? AVAudioPlayer(contentsOf: url) else { continue }
      audioPlayer.enableRate = true
      audioPlayer.prepareToPlay()
      players[clip.id] = audioPlayer
      playerURLs[clip.id] = url
    }

    if isPlaying {
      syncAll(to: currentTimelineTime(), forceSeek: false)
    }
  }

  func play(at timelineTime: TimeInterval, forceSeek: Bool = true) {
    isPlaying = true
    syncAll(to: timelineTime, forceSeek: forceSeek)
    ensureSyncTimerRunning()
  }

  func pause() {
    isPlaying = false
    stopSyncTimer()
    for player in players.values where player.isPlaying {
      player.pause()
    }
    for chain in boostedChains.values where chain.isScheduledPlaying {
      chain.node.stop()
      chain.isScheduledPlaying = false
    }
  }

  func seek(to timelineTime: TimeInterval) {
    if isPlaying {
      syncAll(to: timelineTime, forceSeek: true)
    } else {
      for player in players.values where player.isPlaying {
        player.pause()
      }
      for chain in boostedChains.values where chain.isScheduledPlaying {
        chain.node.stop()
        chain.isScheduledPlaying = false
      }
    }
  }

  func stopAll() {
    isPlaying = false
    stopSyncTimer()
    for player in players.values {
      player.stop()
    }
    players.removeAll()
    playerURLs.removeAll()
    shutdownBoostEngine()
  }

  // MARK: - Sync

  private func ensureSyncTimerRunning() {
    if let syncTimer, syncTimer.isValid {
      return
    }
    syncTimer?.invalidate()
    syncTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
      guard self != nil else {
        timer.invalidate()
        return
      }
      Task { @MainActor [weak self] in
        guard let self, isPlaying else { return }
        syncAll(to: currentTimelineTime(), forceSeek: false)
      }
    }
  }

  private func stopSyncTimer() {
    syncTimer?.invalidate()
    syncTimer = nil
  }

  private func syncAll(to timelineTime: TimeInterval, forceSeek: Bool) {
    let rawRate = currentPlaybackRate()
    let rateSupported = rawRate.isFinite
      && rawRate >= Self.minSupportedRate - 0.01
      && rawRate <= Self.maxSupportedRate + 0.05
    let clampedRate = min(max(rawRate.isFinite ? rawRate : 1.0, Self.minSupportedRate), Self.maxSupportedRate)
    let driftTolerance = max(0.12, 0.12 * Double(clampedRate))

    for clip in activeClips {
      let shouldSilence = !rateSupported
        || isMasterMuted
        || clip.isMuted
        || mutedLanes.contains(clip.trackIndex)
        || !clip.contains(timelineTime: timelineTime)

      if shouldSilence {
        if let player = players[clip.id], player.isPlaying {
          player.pause()
        }
        if let chain = boostedChains[clip.id], chain.isScheduledPlaying {
          chain.node.stop()
          chain.isScheduledPlaying = false
        }
        continue
      }

      let targetVolume = effectivePreviewVolume(for: clip, at: timelineTime)
      let targetSourceTime = clip.sourceStart + (timelineTime - clip.timelineStart)

      if targetVolume > 1.001,
         let url = playerURLs[clip.id],
         syncBoostedClip(
           id: clip.id,
           url: url,
           targetSourceTime: targetSourceTime,
           volume: targetVolume,
           rate: clampedRate,
           driftTolerance: driftTolerance,
           forceSeek: forceSeek
         ) {
        if let player = players[clip.id], player.isPlaying {
          player.pause()
        }
        continue
      }

      if let chain = boostedChains[clip.id], chain.isScheduledPlaying {
        chain.node.stop()
        chain.isScheduledPlaying = false
      }

      guard let player = players[clip.id] else { continue }
      let drift = abs(player.currentTime - targetSourceTime)
      if forceSeek || !player.isPlaying || drift > driftTolerance {
        player.currentTime = max(0, min(targetSourceTime, player.duration))
      }
      if abs(player.rate - clampedRate) > 0.01 {
        player.rate = clampedRate
      }
      // `AVAudioPlayer.volume` is documented as `0.0 ... 1.0`.
      player.volume = min(max(targetVolume, 0), 1.0)
      if !player.isPlaying {
        player.play()
      }
    }
  }

  // MARK: - Boosted `AVAudioEngine` Path (`> 100%` Gain)

  private func ensureBoostEngineRunning() -> AVAudioEngine? {
    if let boostEngine, boostEngine.isRunning {
      return boostEngine
    }
    if boostEngineHasRun {
      shutdownBoostEngine()
    }
    let engine = boostEngine ?? AVAudioEngine()
    let outputFormat = engine.mainMixerNode.outputFormat(forBus: 0)
    guard outputFormat.sampleRate > 0, outputFormat.channelCount > 0 else {
      return nil
    }
    if boostEngine == nil {
      boostEngine = engine
    }
    do {
      try engine.start()
      boostEngineHasRun = true
      return engine
    } catch {
      shutdownBoostEngine()
      return nil
    }
  }

  private func makeOrLookupBoostedChain(id: UUID, url: URL, engine: AVAudioEngine) -> BoostedClipChain? {
    if let existing = boostedChains[id], existing.url == url {
      return existing
    }
    detachBoostedChain(id: id)
    guard let file = try? AVAudioFile(forReading: url),
          file.length > 0,
          file.processingFormat.sampleRate > 0
    else {
      return nil
    }
    let node = AVAudioPlayerNode()
    let timePitch = AVAudioUnitTimePitch()
    engine.attach(node)
    engine.attach(timePitch)
    engine.connect(node, to: timePitch, format: file.processingFormat)
    engine.connect(timePitch, to: engine.mainMixerNode, format: file.processingFormat)
    let chain = BoostedClipChain(url: url, file: file, node: node, timePitch: timePitch)
    boostedChains[id] = chain
    return chain
  }

  private func syncBoostedClip(
    id: UUID,
    url: URL,
    targetSourceTime: TimeInterval,
    volume: Float,
    rate: Float,
    driftTolerance: TimeInterval,
    forceSeek: Bool
  ) -> Bool {
    guard let engine = ensureBoostEngineRunning(),
          let chain = makeOrLookupBoostedChain(id: id, url: url, engine: engine)
    else {
      return false
    }

    let clampedSource = max(0, min(targetSourceTime, max(0, chain.duration - 0.01)))
    let drift = abs(chain.estimatedCurrentTime() - clampedSource)
    chain.timePitch.rate = rate
    chain.node.volume = volume

    if forceSeek || !chain.isScheduledPlaying || abs(chain.scheduledRate - rate) > 0.01 || drift > driftTolerance {
      let sr = chain.file.processingFormat.sampleRate
      let startFrame = min(
        max(0, AVAudioFramePosition((clampedSource * sr).rounded())),
        max(0, chain.file.length - 1)
      )
      let remaining = AVAudioFrameCount(max(1, chain.file.length - startFrame))
      chain.node.stop()
      chain.node.scheduleSegment(
        chain.file,
        startingFrame: startFrame,
        frameCount: remaining,
        at: nil
      )
      chain.anchorSourceTime = Double(startFrame) / sr
      chain.anchorHostTime = CACurrentMediaTime()
      chain.scheduledRate = rate
      chain.node.play()
      chain.isScheduledPlaying = true
    }
    return true
  }

  private func detachBoostedChain(id: UUID) {
    guard let chain = boostedChains.removeValue(forKey: id) else { return }
    chain.node.stop()
    if let boostEngine {
      boostEngine.detach(chain.node)
      boostEngine.detach(chain.timePitch)
    }
  }

  private func shutdownBoostEngine() {
    for chain in boostedChains.values {
      chain.node.stop()
    }
    boostedChains.removeAll()
    boostEngine?.stop()
    boostEngine = nil
    boostEngineHasRun = false
  }

  // MARK: - Testing & Gain Helpers

  func previewStateForTesting(clipId: UUID) -> (isPlaying: Bool, volume: Float, rate: Float)? {
    if let chain = boostedChains[clipId], chain.isScheduledPlaying {
      return (true, chain.node.volume, chain.timePitch.rate)
    }
    guard let player = players[clipId] else { return nil }
    return (player.isPlaying, player.volume, player.rate)
  }

  /// Offline render probe used in tests (including headless CI without output hardware) to
  /// verify that the `AVAudioEngine` boost chain amplifies linear sample amplitude up to `2.0×`.
  nonisolated static func renderBoostedPeakForTesting(
    url: URL,
    volume: Float,
    rate: Float = 1.0
  ) throws -> Float {
    let readFile = try AVAudioFile(forReading: url)
    let format = readFile.processingFormat
    let engine = AVAudioEngine()
    let node = AVAudioPlayerNode()
    let timePitch = AVAudioUnitTimePitch()
    timePitch.rate = rate
    engine.attach(node)
    engine.attach(timePitch)
    engine.connect(node, to: timePitch, format: format)
    engine.connect(timePitch, to: engine.mainMixerNode, format: format)
    let maxFrames: AVAudioFrameCount = 4096
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maxFrames)
    try engine.start()
    defer { engine.stop() }

    node.volume = min(max(volume, 0), AudioTimelineClip.maxVolume)
    node.scheduleFile(readFile, at: nil)
    node.play()

    guard let outBuffer = AVAudioPCMBuffer(
      pcmFormat: engine.manualRenderingFormat,
      frameCapacity: maxFrames
    ) else {
      return 0
    }
    var peak: Float = 0
    for _ in 0 ..< 8 {
      let status = try engine.renderOffline(maxFrames, to: outBuffer)
      guard status == .success, let ch = outBuffer.floatChannelData?[0] else { break }
      for idx in 0 ..< Int(outBuffer.frameLength) {
        peak = max(peak, abs(ch[idx]))
      }
    }
    return peak
  }

  private func effectivePreviewVolume(for clip: AudioTimelineClip, at timelineTime: TimeInterval) -> Float {
    let localTime = timelineTime - clip.timelineStart
    let fades = VideoEditorAudioMixFactory.resolvedFadeDurations(
      fadeIn: clip.fadeIn,
      fadeOut: clip.fadeOut,
      totalDuration: clip.duration
    )
    var envelope: Float = 1.0
    if fades.fadeIn > 0.001, localTime < fades.fadeIn {
      envelope *= Float(max(0, min(1, localTime / fades.fadeIn)))
    }
    if fades.fadeOut > 0.001, localTime > clip.duration - fades.fadeOut {
      envelope *= Float(max(0, min(1, (clip.duration - localTime) / fades.fadeOut)))
    }
    return min(max(clip.volume * envelope, 0), AudioTimelineClip.maxVolume)
  }
}
