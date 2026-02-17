//
//  RecordingSession.swift
//  Snapzy
//
//  Thread-safe session class for managing AVAssetWriter during screen recording.
//  Separated from ScreenRecordingManager to ensure complete isolation from @MainActor.
//

import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// A thread-safe class that holds the AVAssetWriter components.
/// This allows safe access from any thread without crossing @MainActor boundaries.
/// Implements lazy start: session begins when first sample buffer arrives to sync timestamps.
final class RecordingSession: @unchecked Sendable {
  private let lock = NSLock()

  private var _assetWriter: AVAssetWriter?
  private var _videoInput: AVAssetWriterInput?
  private var _pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var _audioInput: AVAssetWriterInput?
  private var _microphoneInput: AVAssetWriterInput?
  private var _sessionStarted = false
  private var _isCapturing = false
  private var _firstTimestamp: CMTime?  // Track first timestamp for relative timing

  init() {}
  
  var assetWriter: AVAssetWriter? {
    get { lock.withLock { _assetWriter } }
    set { lock.withLock { _assetWriter = newValue } }
  }
  
  var videoInput: AVAssetWriterInput? {
    get { lock.withLock { _videoInput } }
    set { lock.withLock { _videoInput = newValue } }
  }

  var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor? {
    get { lock.withLock { _pixelBufferAdaptor } }
    set { lock.withLock { _pixelBufferAdaptor = newValue } }
  }

  var audioInput: AVAssetWriterInput? {
    get { lock.withLock { _audioInput } }
    set { lock.withLock { _audioInput = newValue } }
  }

  var microphoneInput: AVAssetWriterInput? {
    get { lock.withLock { _microphoneInput } }
    set { lock.withLock { _microphoneInput = newValue } }
  }
  
  var sessionStarted: Bool {
    get { lock.withLock { _sessionStarted } }
    set { lock.withLock { _sessionStarted = newValue } }
  }
  
  var isCapturing: Bool {
    get { lock.withLock { _isCapturing } }
    set { lock.withLock { _isCapturing = newValue } }
  }
  
  /// Thread-safe check if ready to write frames
  func canWriteFrames() -> Bool {
    lock.withLock {
      _isCapturing && _assetWriter?.status == .writing
    }
  }

  /// Lazy start session with first sample buffer's timestamp
  /// AVAssetWriter will automatically offset all timestamps relative to this start time
  private func lazyStartSessionIfNeeded(with sampleBuffer: CMSampleBuffer) -> Bool {
    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    guard timestamp.isValid else { return false }

    // First sample: start session at this timestamp
    if !_sessionStarted {
      _assetWriter?.startSession(atSourceTime: timestamp)
      _sessionStarted = true
      _firstTimestamp = timestamp
      print("[RecordingSession] Session started at timestamp: \(timestamp.seconds)s")
    }

    return true
  }

  /// Thread-safe video frame write with lazy session start
  /// Uses pixel buffer adaptor for BGRA format from ScreenCaptureKit
  func appendVideoSample(_ sampleBuffer: CMSampleBuffer) {
    lock.lock()
    defer { lock.unlock() }

    guard _isCapturing else { return }
    guard _assetWriter?.status == .writing else { return }

    // Check if this is a valid frame from ScreenCaptureKit
    // SCStream sends status updates as sample buffers without image data
    guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
          let statusRawValue = attachments.first?[.status] as? Int,
          let status = SCFrameStatus(rawValue: statusRawValue),
          status == .complete else {
      // Not a complete frame - skip silently (these are status updates)
      return
    }

    // Get pixel buffer from sample buffer
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      // Complete frame should have pixel buffer - this is unexpected
      print("[RecordingSession] Complete frame missing pixel buffer")
      return
    }

    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    guard timestamp.isValid else { return }

    // Lazy start session at time zero - we'll use relative timestamps
    if !_sessionStarted {
      _assetWriter?.startSession(atSourceTime: .zero)
      _sessionStarted = true
      _firstTimestamp = timestamp
      print("[RecordingSession] Session started, first frame timestamp: \(timestamp.seconds)s")
    }

    // Calculate presentation time relative to first frame (starts at 0)
    guard let firstTs = _firstTimestamp else { return }
    let presentationTime = CMTimeSubtract(timestamp, firstTs)

    // Append pixel buffer with calculated presentation time
    if _videoInput?.isReadyForMoreMediaData == true {
      let success = _pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: presentationTime) ?? false
      if !success {
        print("[RecordingSession] Failed to append pixel buffer at \(presentationTime.seconds)s")
        if let error = _assetWriter?.error {
          print("[RecordingSession] Writer error: \(error.localizedDescription)")
        }
      }
    }
  }

  /// Thread-safe audio sample write
  func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
    lock.lock()
    defer { lock.unlock() }

    guard _isCapturing else { return }
    guard _assetWriter?.status == .writing else { return }

    // Skip audio until video has started the session
    guard _sessionStarted, let firstTs = _firstTimestamp else { return }

    // Get audio timestamp
    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    guard timestamp.isValid else { return }

    // Skip audio samples that arrived before video start
    guard CMTimeCompare(timestamp, firstTs) >= 0 else { return }

    // Calculate relative timestamp (same as video)
    let relativeTime = CMTimeSubtract(timestamp, firstTs)

    // Create audio sample buffer with adjusted timestamp
    var timingInfo = CMSampleTimingInfo(
      duration: CMSampleBufferGetDuration(sampleBuffer),
      presentationTimeStamp: relativeTime,
      decodeTimeStamp: .invalid
    )

    var adjustedBuffer: CMSampleBuffer?
    let status = CMSampleBufferCreateCopyWithNewTiming(
      allocator: kCFAllocatorDefault,
      sampleBuffer: sampleBuffer,
      sampleTimingEntryCount: 1,
      sampleTimingArray: &timingInfo,
      sampleBufferOut: &adjustedBuffer
    )

    guard status == noErr, let buffer = adjustedBuffer else {
      print("[RecordingSession] Failed to adjust audio timestamp")
      return
    }

    // Append adjusted audio sample
    if _audioInput?.isReadyForMoreMediaData == true {
      let success = _audioInput?.append(buffer) ?? false
      if !success {
        print("[RecordingSession] Failed to append audio sample")
      }
    }
  }

  /// Thread-safe microphone sample write
  func appendMicrophoneSample(_ sampleBuffer: CMSampleBuffer) {
    lock.lock()
    defer { lock.unlock() }

    guard _isCapturing else { return }
    guard _assetWriter?.status == .writing else { return }
    guard _microphoneInput != nil else { return }

    // Skip mic audio until video has started the session
    guard _sessionStarted, let firstTs = _firstTimestamp else { return }

    // Get mic timestamp
    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    guard timestamp.isValid else { return }

    // Skip mic samples that arrived before video start
    guard CMTimeCompare(timestamp, firstTs) >= 0 else { return }

    // Calculate relative timestamp (same as video)
    let relativeTime = CMTimeSubtract(timestamp, firstTs)

    // Create mic sample buffer with adjusted timestamp
    var timingInfo = CMSampleTimingInfo(
      duration: CMSampleBufferGetDuration(sampleBuffer),
      presentationTimeStamp: relativeTime,
      decodeTimeStamp: .invalid
    )

    var adjustedBuffer: CMSampleBuffer?
    let status = CMSampleBufferCreateCopyWithNewTiming(
      allocator: kCFAllocatorDefault,
      sampleBuffer: sampleBuffer,
      sampleTimingEntryCount: 1,
      sampleTimingArray: &timingInfo,
      sampleBufferOut: &adjustedBuffer
    )

    guard status == noErr, let buffer = adjustedBuffer else {
      print("[RecordingSession] Failed to adjust microphone timestamp")
      return
    }

    // Append adjusted microphone sample
    if _microphoneInput?.isReadyForMoreMediaData == true {
      let success = _microphoneInput?.append(buffer) ?? false
      if !success {
        print("[RecordingSession] Failed to append microphone sample")
      }
    }
  }
  
  /// Mark inputs as finished
  func finishInputs() {
    lock.withLock {
      _videoInput?.markAsFinished()
      _audioInput?.markAsFinished()
      _microphoneInput?.markAsFinished()
    }
  }
  
  /// Cancel writing
  func cancelWriting() {
    lock.withLock {
      _assetWriter?.cancelWriting()
    }
  }
  
  /// Finish writing asynchronously
  func finishWriting() async {
    let writer = lock.withLock { _assetWriter }
    guard let writer = writer else {
      print("[RecordingSession] No asset writer to finish")
      return
    }

    print("[RecordingSession] Finishing writing, status: \(writer.status.rawValue)")

    if writer.status == .writing {
      await writer.finishWriting()
      print("[RecordingSession] Finish writing completed, final status: \(writer.status.rawValue)")
      if let error = writer.error {
        print("[RecordingSession] Writer error: \(error.localizedDescription)")
      }
    } else {
      print("[RecordingSession] Writer not in writing state, cannot finish")
      if let error = writer.error {
        print("[RecordingSession] Writer error: \(error.localizedDescription)")
      }
    }
  }
  
  /// Reset all state
  func reset() {
    lock.withLock {
      _assetWriter = nil
      _videoInput = nil
      _pixelBufferAdaptor = nil
      _audioInput = nil
      _microphoneInput = nil
      _sessionStarted = false
      _isCapturing = false
      _firstTimestamp = nil
    }
  }
}
