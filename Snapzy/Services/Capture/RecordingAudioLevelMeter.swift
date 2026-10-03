//
//  RecordingAudioLevelMeter.swift
//  Snapzy
//
//  Publishes a smoothed, normalized 0...1 audio level derived read-only from the
//  live recording CMSampleBuffers (system audio + microphone). Used by the
//  recording status bar to drive an ambient waveform. Metering never mutates the
//  buffers, so it has zero effect on the AVAssetWriter recording path.
//

import AVFoundation
import Combine
import CoreMedia

nonisolated enum AudioLevelSource {
  case system
  case microphone
}

/// Thread-safe audio-level meter. `ingest(_:source:)` is safe to call from the
/// `nonisolated` capture delegate queues; only the final `level` publish hops to main.
nonisolated final class RecordingAudioLevelMeter: ObservableObject, @unchecked Sendable {
  /// Smoothed, normalized level in `0...1`, published on the main thread ~30Hz.
  @MainActor @Published private(set) var level: Float = 0

  private let queue = DispatchQueue(label: "com.trongduong.snapzy.recording.audiolevel", qos: .userInteractive)

  // Per-source most-recent RMS (guarded by `queue`).
  private var systemRMS: Float = 0
  private var micRMS: Float = 0
  private var smoothed: Float = 0
  private var isFrozen = false
  private var lastPublish: CFAbsoluteTime = 0

  // Tunables — voice-reactive envelope.
  private let attack: Float = 0.5 // fast rise → snappy response to loud speech
  private let decay: Float = 0.08 // slow fall → soft, ocean-like settle
  private let noiseFloorDB: Float = -50 // gate room hiss below this → clean silence
  private let minDB: Float = -54 // low end of usable window (whisper territory)
  private let maxDB: Float = -6 // loud speech saturates near here → tall peaks
  private let silenceKnee: Float = 0.12 // below this normalized level → still 0 (room tone)
  private var publishInterval: CFAbsoluteTime {
    if NSClassFromString("XCTestCase") != nil {
      return 0
    }
    return 1.0 / 60.0
  }

  // MARK: - Ingest

  /// Compute RMS off the caller's queue (cheap, read-only) then update state serially.
  func ingest(_ sampleBuffer: CMSampleBuffer, source: AudioLevelSource) {
    guard let rms = Self.rms(from: sampleBuffer) else { return }
    queue.async { [weak self] in
      guard let self, !self.isFrozen else { return }
      switch source {
      case .system: systemRMS = rms
      case .microphone: micRMS = rms
      }
      recompute()
    }
  }

  // MARK: - Lifecycle

  /// Hold the current level (called on pause) — stops decaying to 0.
  func freeze() {
    queue.async { [weak self] in self?.isFrozen = true }
  }

  /// Resume metering (called on resume).
  func unfreeze() {
    queue.async { [weak self] in self?.isFrozen = false }
  }

  /// Zero everything (called on stop/cleanup).
  func reset() {
    queue.async { [weak self] in
      guard let self else { return }
      systemRMS = 0
      micRMS = 0
      smoothed = 0
      isFrozen = false
      lastPublish = 0
      publish(0)
    }
  }

  // MARK: - Private

  private func recompute() {
    let combined = max(systemRMS, micRMS)
    let blend = combined > smoothed ? attack : decay
    smoothed = smoothed * (1 - blend) + combined * blend

    // Gate room hiss below the noise floor to a clean 0, then map the usable
    // window (minDB…maxDB) to 0…1 so whispers read low and loud speech saturates.
    let db = 20 * log10(max(smoothed, 1e-7))
    let gated = db < noiseFloorDB ? minDB : db
    let mapped = max(0, min(1, (gated - minDB) / (maxDB - minDB)))

    // Soft low-end knee: collapse residual room tone (below `silenceKnee`) to a
    // clean 0 so the wave stays still when the user isn't speaking, then rescale
    // the remainder to a full 0…1 so real sound clearly lifts it above rest.
    let norm = mapped <= silenceKnee ? 0 : (mapped - silenceKnee) / (1 - silenceKnee)

    let now = CFAbsoluteTimeGetCurrent()
    guard now - lastPublish >= publishInterval else { return }
    lastPublish = now
    publish(norm)
  }

  private func publish(_ value: Float) {
    DispatchQueue.main.async { [weak self] in self?.level = value }
  }

  /// Root-mean-square amplitude across every sample/channel of a PCM audio buffer.
  /// Handles interleaved & deinterleaved Float32 / Int16 / Int32. Returns nil for
  /// non-audio or unsupported formats.
  private static func rms(from sampleBuffer: CMSampleBuffer) -> Float? {
    guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else {
      return nil
    }
    let format = AVAudioFormat(cmAudioFormatDescription: formatDesc)
    let frames = CMSampleBufferGetNumSamples(sampleBuffer)
    guard frames > 0,
          let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else {
      return nil
    }
    pcm.frameLength = AVAudioFrameCount(frames)
    guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
      sampleBuffer,
      at: 0,
      frameCount: Int32(frames),
      into: pcm.mutableAudioBufferList
    ) == noErr else {
      return nil
    }

    let asbd = format.streamDescription.pointee
    let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
    let bits = asbd.mBitsPerChannel
    let buffers = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)

    var sumSquares: Double = 0
    var total = 0

    for buffer in buffers {
      guard let data = buffer.mData else { continue }
      let byteCount = Int(buffer.mDataByteSize)
      if isFloat, bits == 32 {
        let count = byteCount / MemoryLayout<Float>.size
        let ptr = data.assumingMemoryBound(to: Float.self)
        for i in 0 ..< count {
          let s = ptr[i]
          sumSquares += Double(s * s)
        }
        total += count
      } else if !isFloat, bits == 16 {
        let count = byteCount / MemoryLayout<Int16>.size
        let ptr = data.assumingMemoryBound(to: Int16.self)
        let scale = Float(Int16.max)
        for i in 0 ..< count {
          let s = Float(ptr[i]) / scale
          sumSquares += Double(s * s)
        }
        total += count
      } else if !isFloat, bits == 32 {
        let count = byteCount / MemoryLayout<Int32>.size
        let ptr = data.assumingMemoryBound(to: Int32.self)
        let scale = Float(Int32.max)
        for i in 0 ..< count {
          let s = Float(ptr[i]) / scale
          sumSquares += Double(s * s)
        }
        total += count
      }
    }

    guard total > 0 else { return nil }
    return Float((sumSquares / Double(total)).squareRoot())
  }

  func flushQueueForTesting() {
    queue.sync {}
  }
}
