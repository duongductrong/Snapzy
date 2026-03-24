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
  struct VideoWriteStats {
    let receivedFrames: Int
    let appendedFrames: Int
    let droppedFramesDueToBackpressure: Int
    let failedAppendFrames: Int
  }

  private let lock = NSLock()

  private var _assetWriter: AVAssetWriter?
  private var _videoInput: AVAssetWriterInput?
  private var _pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var _audioInput: AVAssetWriterInput?
  private var _microphoneInput: AVAssetWriterInput?
  private var _sessionStarted = false
  private var _isCapturing = false
  private var _firstTimestamp: CMTime?  // Track first video timestamp for timeline alignment
  private var _onFirstVideoFrame: (() -> Void)?
  private var _videoFramesReceived = 0
  private var _videoFramesAppended = 0
  private var _videoFramesDroppedBackpressure = 0
  private var _videoFramesFailedAppend = 0

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

  func setOnFirstVideoFrame(_ callback: (() -> Void)?) {
    lock.withLock {
      _onFirstVideoFrame = callback
    }
  }
  
  /// Thread-safe check if ready to write frames
  func canWriteFrames() -> Bool {
    lock.withLock {
      _isCapturing && _assetWriter?.status == .writing
    }
  }

  func videoWriteStats() -> VideoWriteStats {
    lock.withLock {
      VideoWriteStats(
        receivedFrames: _videoFramesReceived,
        appendedFrames: _videoFramesAppended,
        droppedFramesDueToBackpressure: _videoFramesDroppedBackpressure,
        failedAppendFrames: _videoFramesFailedAppend
      )
    }
  }

  /// Thread-safe video frame write with lazy session start
  /// Uses pixel buffer adaptor for BGRA format from ScreenCaptureKit
  func appendVideoSample(_ sampleBuffer: CMSampleBuffer) {
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

    let (writer, videoInput, adaptor, shouldStartSession, onFirstVideoFrame): (
      AVAssetWriter?, AVAssetWriterInput?, AVAssetWriterInputPixelBufferAdaptor?, Bool, (() -> Void)?
    ) = lock.withLock {
      guard _isCapturing, let writer = _assetWriter, writer.status == .writing else {
        return (nil, nil, nil, false, nil)
      }

      var needsSessionStart = false
      if !_sessionStarted {
        _sessionStarted = true
        _firstTimestamp = timestamp
        needsSessionStart = true
      }

      return (writer, _videoInput, _pixelBufferAdaptor, needsSessionStart, _onFirstVideoFrame)
    }

    guard let writer = writer,
          let videoInput = videoInput,
          let adaptor = adaptor else { return }

    // Lazy start session at first video timestamp.
    // This avoids rewriting every audio sample (large per-buffer allocations).
    if shouldStartSession {
      writer.startSession(atSourceTime: timestamp)
      print("[RecordingSession] Session started, first frame timestamp: \(timestamp.seconds)s")
      onFirstVideoFrame?()
    }

    lock.withLock { _videoFramesReceived += 1 }

    // Append pixel buffer with calculated presentation time
    if videoInput.isReadyForMoreMediaData {
      let success = adaptor.append(pixelBuffer, withPresentationTime: timestamp)
      if !success {
        lock.withLock { _videoFramesFailedAppend += 1 }
        print("[RecordingSession] Failed to append pixel buffer at \(timestamp.seconds)s")
        if let error = writer.error {
          print("[RecordingSession] Writer error: \(error.localizedDescription)")
        }
      } else {
        lock.withLock { _videoFramesAppended += 1 }
      }
    } else {
      lock.withLock { _videoFramesDroppedBackpressure += 1 }
    }
  }

  /// Thread-safe audio sample write
  func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
    // Get audio timestamp
    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    guard timestamp.isValid else { return }

    let (writer, audioInput, firstTs): (AVAssetWriter?, AVAssetWriterInput?, CMTime?) = lock.withLock {
      guard _isCapturing, let writer = _assetWriter, writer.status == .writing else {
        return (nil, nil, nil)
      }
      return (writer, _audioInput, _firstTimestamp)
    }

    guard let writer = writer, writer.status == .writing else { return }
    guard let audioInput = audioInput else { return }
    // Skip audio until video has started the session
    guard let firstTs = firstTs else { return }

    // Skip audio samples that arrived before video start
    guard CMTimeCompare(timestamp, firstTs) >= 0 else { return }

    // Session starts at first video timestamp, so original timestamps are valid.
    if audioInput.isReadyForMoreMediaData {
      let success = audioInput.append(sampleBuffer)
      if !success {
        print("[RecordingSession] Failed to append audio sample")
        if let error = writer.error {
          print("[RecordingSession] Writer error: \(error.localizedDescription)")
        }
      }
    }
  }

  /// Thread-safe microphone sample write
  func appendMicrophoneSample(_ sampleBuffer: CMSampleBuffer) {
    // Get mic timestamp
    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    guard timestamp.isValid else { return }

    let (writer, microphoneInput, firstTs): (AVAssetWriter?, AVAssetWriterInput?, CMTime?) = lock.withLock {
      guard _isCapturing, let writer = _assetWriter, writer.status == .writing else {
        return (nil, nil, nil)
      }
      return (writer, _microphoneInput, _firstTimestamp)
    }

    guard let writer = writer, writer.status == .writing else { return }
    guard let microphoneInput = microphoneInput else { return }
    // Skip mic audio until video has started the session
    guard let firstTs = firstTs else { return }

    // Skip mic samples that arrived before video start
    guard CMTimeCompare(timestamp, firstTs) >= 0 else { return }

    // Session starts at first video timestamp, so original timestamps are valid.
    if microphoneInput.isReadyForMoreMediaData {
      let success = microphoneInput.append(sampleBuffer)
      if !success {
        print("[RecordingSession] Failed to append microphone sample")
        if let error = writer.error {
          print("[RecordingSession] Writer error: \(error.localizedDescription)")
        }
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
      _onFirstVideoFrame = nil
      _videoFramesReceived = 0
      _videoFramesAppended = 0
      _videoFramesDroppedBackpressure = 0
      _videoFramesFailedAppend = 0
    }
  }
}
