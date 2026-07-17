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
    let microphoneSamplesReceived: Int
    let microphoneSamplesAppended: Int
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
  private var _pauseOffsetAccumulator: CMTime = .zero
  private var _onFirstVideoFrame: (() -> Void)?
  private var _videoFramesReceived = 0
  private var _videoFramesAppended = 0
  private var _videoFramesDroppedBackpressure = 0
  private var _videoFramesFailedAppend = 0
  private var _microphoneSamplesReceived = 0
  private var _microphoneSamplesAppended = 0
  private var _expectedVideoWidth: Int?
  private var _expectedVideoHeight: Int?
  private var _didLogMissingPixelBuffer = false
  private var _didLogFrameDimensionMismatch = false
  private var _didLogVideoAppendFailure = false
  private var _didLogAudioAppendFailure = false
  private var _didLogMicrophoneAppendFailure = false
  private var _didLogSystemAudioSampleFormat = false
  private var _didLogMicrophoneAudioSampleFormat = false

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

  func configureExpectedVideoDimensions(width: Int, height: Int) {
    lock.withLock {
      _expectedVideoWidth = width
      _expectedVideoHeight = height
      _didLogFrameDimensionMismatch = false
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
        failedAppendFrames: _videoFramesFailedAppend,
        microphoneSamplesReceived: _microphoneSamplesReceived,
        microphoneSamplesAppended: _microphoneSamplesAppended
      )
    }
  }

  /// Set the total accumulated pause duration for PTS adjustment.
  /// Called by ScreenRecordingManager on each resume.
  func setAccumulatedPauseOffset(_ offset: CMTime) {
    lock.withLock {
      _pauseOffsetAccumulator = offset
    }
  }

  /// Create a copy of the audio sample buffer with PTS adjusted for pause offset.
  /// Returns nil if the copy fails or if the adjustment is invalid.
  private func adjustedAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer, offset: CMTime) -> CMSampleBuffer? {
    guard offset.isNumeric, offset > .zero else { return sampleBuffer }

    var timingInfo = CMSampleTimingInfo()
    let status = CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timingInfo)
    guard status == noErr else { return nil }

    timingInfo.presentationTimeStamp = CMTimeSubtract(timingInfo.presentationTimeStamp, offset)
    if timingInfo.decodeTimeStamp.isValid {
      timingInfo.decodeTimeStamp = CMTimeSubtract(timingInfo.decodeTimeStamp, offset)
    }

    var adjustedBuffer: CMSampleBuffer?
    let copyStatus = CMSampleBufferCreateCopyWithNewTiming(
      allocator: kCFAllocatorDefault,
      sampleBuffer: sampleBuffer,
      sampleTimingEntryCount: 1,
      sampleTimingArray: &timingInfo,
      sampleBufferOut: &adjustedBuffer
    )
    return copyStatus == noErr ? adjustedBuffer : nil
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
      let shouldLog = lock.withLock {
        if _didLogMissingPixelBuffer { return false }
        _didLogMissingPixelBuffer = true
        return true
      }
      if shouldLog {
        DiagnosticLogger.shared.log(
          .warning,
          .recording,
          "Complete recording frame missing pixel buffer"
        )
      }
      return
    }

    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    guard timestamp.isValid else { return }

    // Consolidate locks and read dimensions/offset in one acquisition
    var shouldLogDimensionMismatch = false
    let (writer, videoInput, adaptor, shouldStartSession, onFirstVideoFrame, offset, expectedWidth, expectedHeight, pixelWidth, pixelHeight): (
      AVAssetWriter?, AVAssetWriterInput?, AVAssetWriterInputPixelBufferAdaptor?, Bool, (() -> Void)?, CMTime, Int?, Int?, Int, Int
    ) = lock.withLock {
      guard _isCapturing, let writer = _assetWriter, writer.status == .writing else {
        return (nil, nil, nil, false, nil, .zero, nil, nil, 0, 0)
      }

      let w = CVPixelBufferGetWidth(pixelBuffer)
      let h = CVPixelBufferGetHeight(pixelBuffer)
      if let expectedWidth = _expectedVideoWidth,
         let expectedHeight = _expectedVideoHeight,
         (w != expectedWidth || h != expectedHeight),
         !_didLogFrameDimensionMismatch {
        _didLogFrameDimensionMismatch = true
        shouldLogDimensionMismatch = true
      }

      let offset = _pauseOffsetAccumulator
      let adjustedTimestamp = offset.isNumeric && offset > .zero ? CMTimeSubtract(timestamp, offset) : timestamp

      var needsSessionStart = false
      if !_sessionStarted {
        _sessionStarted = true
        _firstTimestamp = adjustedTimestamp
        needsSessionStart = true
      }

      _videoFramesReceived += 1

      return (writer, _videoInput, _pixelBufferAdaptor, needsSessionStart, _onFirstVideoFrame, offset, _expectedVideoWidth, _expectedVideoHeight, w, h)
    }

    if shouldLogDimensionMismatch, let expectedWidth = expectedWidth, let expectedHeight = expectedHeight {
      DiagnosticLogger.shared.log(.warning, .recording, "Recording frame dimension mismatch", context: [
        "expected": "\(expectedWidth)x\(expectedHeight)",
        "actual": "\(pixelWidth)x\(pixelHeight)",
      ])
    }

    guard let writer = writer,
          let videoInput = videoInput,
          let adaptor = adaptor else { return }

    let adjustedTimestamp = offset.isNumeric && offset > .zero ? CMTimeSubtract(timestamp, offset) : timestamp

    // Lazy start session at first video timestamp.
    // This avoids rewriting every audio sample (large per-buffer allocations).
    if shouldStartSession {
      writer.startSession(atSourceTime: adjustedTimestamp)
      DiagnosticLogger.shared.log(.debug, .recording, "Recording writer session started", context: [
        "firstFrameTimestampSeconds": String(format: "%.3f", adjustedTimestamp.seconds)
      ])
      onFirstVideoFrame?()
    }

    // Append pixel buffer with calculated presentation time
    if videoInput.isReadyForMoreMediaData {
      let success = adaptor.append(pixelBuffer, withPresentationTime: adjustedTimestamp)
      if !success {
        let shouldLog = lock.withLock {
          _videoFramesFailedAppend += 1
          if _didLogVideoAppendFailure { return false }
          _didLogVideoAppendFailure = true
          return true
        }
        if shouldLog {
          logWriterIssue(
            "Failed to append recording video frame",
            writer: writer,
            context: ["timestampSeconds": String(format: "%.3f", adjustedTimestamp.seconds)]
          )
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
    logAudioSampleFormatIfNeeded(sampleBuffer, role: .systemAudio)

    let (writer, audioInput, firstTs, offset): (AVAssetWriter?, AVAssetWriterInput?, CMTime?, CMTime) = lock.withLock {
      guard _isCapturing, let writer = _assetWriter, writer.status == .writing else {
        return (nil, nil, nil, .zero)
      }
      return (writer, _audioInput, _firstTimestamp, _pauseOffsetAccumulator)
    }

    guard let writer = writer, writer.status == .writing else { return }
    guard let audioInput = audioInput else { return }
    // Skip audio until video has started the session
    guard let firstTs = firstTs else { return }

    let adjustedTimestamp = offset.isNumeric && offset > .zero ? CMTimeSubtract(timestamp, offset) : timestamp

    // Skip audio samples that arrived before video start
    guard CMTimeCompare(adjustedTimestamp, firstTs) >= 0 else { return }

    if audioInput.isReadyForMoreMediaData {
      guard let bufferToAppend = adjustedAudioSampleBuffer(sampleBuffer, offset: offset) else { return }
      let success = audioInput.append(bufferToAppend)
      if !success {
        let shouldLog = lock.withLock {
          if _didLogAudioAppendFailure { return false }
          _didLogAudioAppendFailure = true
          return true
        }
        if shouldLog {
          logWriterIssue(
            "Failed to append recording system audio sample",
            writer: writer,
            context: ["timestampSeconds": String(format: "%.3f", adjustedTimestamp.seconds)]
          )
        }
      }
    }
  }

  /// Thread-safe microphone sample write
  func appendMicrophoneSample(_ sampleBuffer: CMSampleBuffer) {
    // Get mic timestamp
    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    guard timestamp.isValid else { return }
    logAudioSampleFormatIfNeeded(sampleBuffer, role: .microphone)

    let (writer, microphoneInput, firstTs, offset): (AVAssetWriter?, AVAssetWriterInput?, CMTime?, CMTime) = lock.withLock {
      guard _isCapturing, let writer = _assetWriter, writer.status == .writing else {
        return (nil, nil, nil, .zero)
      }
      return (writer, _microphoneInput, _firstTimestamp, _pauseOffsetAccumulator)
    }

    guard let writer = writer, writer.status == .writing else { return }
    guard let microphoneInput = microphoneInput else { return }
    // Skip mic audio until video has started the session
    guard let firstTs = firstTs else { return }

    let adjustedTimestamp = offset.isNumeric && offset > .zero ? CMTimeSubtract(timestamp, offset) : timestamp

    // Skip mic samples that arrived before video start
    guard CMTimeCompare(adjustedTimestamp, firstTs) >= 0 else { return }

    lock.withLock { _microphoneSamplesReceived += 1 }

    if microphoneInput.isReadyForMoreMediaData {
      guard let bufferToAppend = adjustedAudioSampleBuffer(sampleBuffer, offset: offset) else { return }
      let success = microphoneInput.append(bufferToAppend)
      if success {
        lock.withLock { _microphoneSamplesAppended += 1 }
      } else {
        let shouldLog = lock.withLock {
          if _didLogMicrophoneAppendFailure { return false }
          _didLogMicrophoneAppendFailure = true
          return true
        }
        if shouldLog {
          logWriterIssue(
            "Failed to append recording microphone sample",
            writer: writer,
            context: ["timestampSeconds": String(format: "%.3f", adjustedTimestamp.seconds)]
          )
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
      DiagnosticLogger.shared.log(.warning, .recording, "Recording finish requested without asset writer")
      return
    }

    DiagnosticLogger.shared.log(.debug, .recording, "Finishing recording writer", context: [
      "writerStatus": writerStatusLabel(writer.status)
    ])

    if writer.status == .writing {
      await writer.finishWriting()
      if let error = writer.error {
        logWriterIssue("Recording writer finished with error", writer: writer)
      } else {
        DiagnosticLogger.shared.log(.debug, .recording, "Recording writer finished", context: [
          "writerStatus": writerStatusLabel(writer.status)
        ])
      }
    } else {
      logWriterIssue("Recording writer not in writing state during finish", writer: writer)
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
      _pauseOffsetAccumulator = .zero
      _onFirstVideoFrame = nil
      _videoFramesReceived = 0
      _videoFramesAppended = 0
      _videoFramesDroppedBackpressure = 0
      _videoFramesFailedAppend = 0
      _microphoneSamplesReceived = 0
      _microphoneSamplesAppended = 0
      _expectedVideoWidth = nil
      _expectedVideoHeight = nil
      _didLogMissingPixelBuffer = false
      _didLogFrameDimensionMismatch = false
      _didLogVideoAppendFailure = false
      _didLogAudioAppendFailure = false
      _didLogMicrophoneAppendFailure = false
      _didLogSystemAudioSampleFormat = false
      _didLogMicrophoneAudioSampleFormat = false
    }
  }

  private enum AudioSampleRole {
    case systemAudio
    case microphone

    var logValue: String {
      switch self {
      case .systemAudio: return "systemAudio"
      case .microphone: return "microphone"
      }
    }
  }

  private func logAudioSampleFormatIfNeeded(_ sampleBuffer: CMSampleBuffer, role: AudioSampleRole) {
    let shouldLog = lock.withLock {
      switch role {
      case .systemAudio:
        if _didLogSystemAudioSampleFormat { return false }
        _didLogSystemAudioSampleFormat = true
        return true
      case .microphone:
        if _didLogMicrophoneAudioSampleFormat { return false }
        _didLogMicrophoneAudioSampleFormat = true
        return true
      }
    }
    guard shouldLog else { return }

    var context: [String: String] = ["role": role.logValue]
    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    if timestamp.isValid, timestamp.seconds.isFinite {
      context["timestampSeconds"] = String(format: "%.3f", timestamp.seconds)
    }

    let duration = CMSampleBufferGetDuration(sampleBuffer)
    if duration.isValid, duration.seconds.isFinite {
      context["durationMs"] = String(format: "%.2f", duration.seconds * 1000)
    }

    var observedSampleRate: Double?
    if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
      context["mediaSubType"] = fourCC(CMFormatDescriptionGetMediaSubType(formatDescription))
      if let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee {
        observedSampleRate = streamDescription.mSampleRate
        context["sampleRate"] = String(format: "%.0f", streamDescription.mSampleRate)
        context["channels"] = "\(streamDescription.mChannelsPerFrame)"
        context["formatID"] = fourCC(streamDescription.mFormatID)
        context["formatFlags"] = String(format: "0x%X", streamDescription.mFormatFlags)
        context["bitsPerChannel"] = "\(streamDescription.mBitsPerChannel)"
        context["framesPerPacket"] = "\(streamDescription.mFramesPerPacket)"
      }
    }

    DiagnosticLogger.shared.log(
      .info,
      .recording,
      "Recording audio sample format",
      context: context
    )

    // Surface a sample-rate mismatch proactively: a mic captured below the target rate
    // (e.g. a Bluetooth/HFP device at ~16 kHz) resampled to 48 kHz can produce piercing
    // spectral imaging. The capture output pins 48 kHz LPCM, so this should not fire.
    if role == .microphone,
       let observedSampleRate,
       observedSampleRate > 0,
       Int(observedSampleRate.rounded()) != RecordingAudioEncodingSettings.sampleRate {
      DiagnosticLogger.shared.log(
        .warning,
        .recording,
        "Microphone captured at non-target sample rate",
        context: [
          "role": role.logValue,
          "observedSampleRate": String(format: "%.0f", observedSampleRate),
          "expectedSampleRate": "\(RecordingAudioEncodingSettings.sampleRate)",
        ]
      )
    }
  }

  private func fourCC(_ value: FourCharCode) -> String {
    let bytes = [
      UInt8((value >> 24) & 0xff),
      UInt8((value >> 16) & 0xff),
      UInt8((value >> 8) & 0xff),
      UInt8(value & 0xff),
    ]
    guard bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }),
          let string = String(bytes: bytes, encoding: .ascii)
    else {
      return "\(value)"
    }
    return string
  }

  private func logWriterIssue(
    _ message: String,
    writer: AVAssetWriter?,
    context: [String: String] = [:]
  ) {
    var context = context
    if let writer {
      context["writerStatus"] = writerStatusLabel(writer.status)
    }

    if let error = writer?.error {
      DiagnosticLogger.shared.logError(.recording, error, message, context: context)
    } else {
      DiagnosticLogger.shared.log(.error, .recording, message, context: context)
    }
  }

  private func writerStatusLabel(_ status: AVAssetWriter.Status) -> String {
    switch status {
    case .unknown: return "unknown"
    case .writing: return "writing"
    case .completed: return "completed"
    case .failed: return "failed"
    case .cancelled: return "cancelled"
    @unknown default: return "unknown"
    }
  }
}
