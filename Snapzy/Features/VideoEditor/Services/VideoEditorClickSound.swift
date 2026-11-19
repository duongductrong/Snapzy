//
//  VideoEditorClickSound.swift
//  Snapzy
//
//  Studio click sound (Decision D4): a short synthesized click (no bundled audio), its
//  placement on the output timeline (follows cuts, reorder and speed), and the PCM
//  lane the exporter mixes in.
//

import AVFoundation
import Foundation

nonisolated enum VideoEditorClickSound {
  static let sampleRate: Double = 48_000
  /// Clicks closer than this on the output timeline (fast speed spans) merge into one.
  static let minimumSpacing: TimeInterval = 0.06

  /// Mono click samples in −1...1: a filtered noise transient over a short tone.
  static let samples: [Float] = {
    let count = Int(sampleRate * 0.03)
    var seed: UInt32 = 0x1234_5678
    var previous: Float = 0
    return (0 ..< count).map { index in
      let t = Float(index) / Float(sampleRate)
      seed = seed &* 1_664_525 &+ 1_013_904_223
      let noise = Float(Int32(bitPattern: seed)) / Float(Int32.max)
      // One-pole low-pass keeps the transient soft rather than hissy.
      previous += 0.35 * (noise - previous)
      let transient = previous * exp(-t / 0.0035)
      let tone = sin(2 * .pi * 2_200 * t) * exp(-t / 0.007) * 0.5
      return (transient + tone) * 0.8
    }
  }()

  /// Output times of every mouse-down in the primary clips, sorted, merged when closer
  /// than `minimumSpacing`.
  static func outputTimes(
    clickSourceTimes: [TimeInterval],
    playbackPlacements: [TimelineSequence.Placement],
    sequenceMap: TimelineSequenceMap
  ) -> [TimeInterval] {
    var times: [TimeInterval] = []
    for source in clickSourceTimes {
      for placement in playbackPlacements where placement.clip.isPrimary
        && source >= placement.sourceAxisStart && source < placement.sourceAxisEnd {
        times.append(sequenceMap.toOutput(placement.sequenceTime(atSource: source)))
      }
    }
    return merge(times.sorted())
  }

  static func merge(_ sorted: [TimeInterval]) -> [TimeInterval] {
    var result: [TimeInterval] = []
    for time in sorted where result.last.map({ time - $0 >= minimumSpacing }) ?? true {
      result.append(time)
    }
    return result
  }

  /// Writes a mono PCM lane of `duration` with a click at each time, scaled by `volume`.
  static func writeLane(times: [TimeInterval], duration: TimeInterval, volume: Float, to url: URL) throws {
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
      throw CocoaError(.fileWriteUnknown)
    }
    let frameCount = AVAudioFrameCount(max(duration, 0.01) * sampleRate)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
          let channel = buffer.floatChannelData?[0]
    else { throw CocoaError(.fileWriteUnknown) }
    buffer.frameLength = frameCount
    channel.update(repeating: 0, count: Int(frameCount))
    let click = samples
    for time in times {
      let start = Int(time * sampleRate)
      guard start >= 0 else { continue }
      for (offset, sample) in click.enumerated() {
        let index = start + offset
        guard index < Int(frameCount) else { break }
        channel[index] = max(-1, min(1, channel[index] + sample * volume))
      }
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
  }

  /// One-click buffer for live playback.
  static func makeBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
      return nil
    }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    for channel in 0 ..< Int(format.channelCount) {
      guard let data = buffer.floatChannelData?[channel] else { continue }
      for (index, sample) in samples.enumerated() { data[index] = sample }
    }
    return buffer
  }
}
