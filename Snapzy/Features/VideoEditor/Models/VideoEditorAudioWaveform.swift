//
//  VideoEditorAudioWaveform.swift
//  Snapzy
//
//  Immutable normalized peak amplitude waveform for timeline audio visualization.
//

import CoreGraphics
import Foundation

/// Immutable normalized peak waveform (`0.0 ... 1.0`) for one audio-bearing media asset.
nonisolated struct VideoEditorAudioWaveform: Equatable, Sendable {
  /// Normalized peak amplitude buckets across `0 ... duration`.
  let samples: [Float]
  /// Duration of the source asset in seconds.
  let duration: TimeInterval

  static let empty = VideoEditorAudioWaveform(samples: [], duration: 0)

  /// Amplitude threshold below which audio is treated as digital silence.
  static let silenceFloor: Float = 0.0005

  /// Perceptual exponent applied to normalized peaks so speech remains legible alongside loud transients.
  static let perceptualExponent: Float = 0.72

  var isEmpty: Bool {
    samples.isEmpty || duration <= 0
  }

  /// True when every extracted sample is effectively silent.
  var isSilent: Bool {
    samples.allSatisfy { $0 <= Self.silenceFloor }
  }

  /// Apply clamping and perceptual shaping to a raw linear peak relative to `globalPeak`.
  static func shapePeak(_ rawPeak: Float, globalPeak: Float) -> Float {
    guard rawPeak.isFinite, globalPeak.isFinite, globalPeak > silenceFloor else { return 0 }
    let normalized = max(0, min(1, rawPeak / globalPeak))
    return powf(normalized, perceptualExponent)
  }

  /// Downsample raw PCM float samples into normalized perceptual peaks in `0 ... 1`.
  static func extractPeaks(from rawSamples: [Float], bucketCount: Int) -> [Float] {
    guard !rawSamples.isEmpty, bucketCount > 0 else { return [] }

    let safeBuckets = min(bucketCount, rawSamples.count)
    var rawPeaks = [Float](repeating: 0, count: safeBuckets)
    var globalPeak: Float = 0

    for bucket in 0 ..< safeBuckets {
      let startIdx = (bucket * rawSamples.count) / safeBuckets
      let endIdx = max(startIdx + 1, ((bucket + 1) * rawSamples.count) / safeBuckets)
      var bucketPeak: Float = 0
      for idx in startIdx ..< min(endIdx, rawSamples.count) {
        let magnitude = abs(rawSamples[idx])
        if magnitude.isFinite, magnitude > bucketPeak {
          bucketPeak = magnitude
        }
      }
      rawPeaks[bucket] = bucketPeak
      if bucketPeak > globalPeak {
        globalPeak = bucketPeak
      }
    }

    guard globalPeak > silenceFloor else {
      return [Float](repeating: 0, count: safeBuckets)
    }

    return rawPeaks.map { shapePeak($0, globalPeak: globalPeak) }
  }

  /// Slice and max-pool peaks for a clip's time range `[startTime, endTime]` into `barCount` bars.
  func slice(from startTime: TimeInterval, to endTime: TimeInterval, barCount: Int) -> [Float] {
    guard !isEmpty, barCount > 0, startTime.isFinite, endTime.isFinite, endTime > startTime else {
      return []
    }

    let clampedStart = max(0, min(startTime, duration))
    let clampedEnd = max(clampedStart, min(endTime, duration))
    guard clampedEnd > clampedStart else { return [] }

    let totalSamples = samples.count
    let startFraction = clampedStart / duration
    let endFraction = clampedEnd / duration

    var bars = [Float](repeating: 0, count: barCount)
    for barIndex in 0 ..< barCount {
      let barStartFrac = startFraction + (endFraction - startFraction) * (Double(barIndex) / Double(barCount))
      let barEndFrac = startFraction + (endFraction - startFraction) * (Double(barIndex + 1) / Double(barCount))

      let rawLo = Int(floor(barStartFrac * Double(totalSamples)))
      let rawHi = Int(ceil(barEndFrac * Double(totalSamples)))
      let lo = max(0, min(rawLo, totalSamples - 1))
      let hi = max(lo + 1, min(rawHi, totalSamples))

      var peak: Float = 0
      for idx in lo ..< hi where samples[idx] > peak {
        peak = samples[idx]
      }
      bars[barIndex] = peak
    }
    return bars
  }

  static let maxSupportedDuration: TimeInterval = 86_400

  /// Recommended bucket count for an asset duration (~12 buckets/sec, clamped `[64, 960]`).
  static func recommendedBucketCount(for duration: TimeInterval) -> Int {
    guard duration.isFinite, duration > 0 else { return 64 }
    let clampedDuration = min(duration, maxSupportedDuration)
    let ideal = Int((clampedDuration * 12.0).rounded())
    return max(64, min(ideal, 960))
  }

  /// Compute an optimal bar count for a clip block width so bars stay crisp at any zoom level.
  static func barCount(forWidth width: CGFloat, barPitch: CGFloat = 3.0, maxBars: Int = 480) -> Int {
    guard width.isFinite, width >= 12, barPitch > 0, maxBars > 0 else { return 0 }
    return max(4, min(Int((width / barPitch).rounded(.down)), maxBars))
  }
}
