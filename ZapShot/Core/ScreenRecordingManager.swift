//
//  ScreenRecordingManager.swift
//  ZapShot
//
//  Core manager for screen recording functionality using ScreenCaptureKit
//

import AVFoundation
import AppKit
import Combine
import CoreMedia
import Foundation
import ScreenCaptureKit

// MARK: - Video Format

enum VideoFormat: String, CaseIterable, Codable {
  case mov
  case mp4

  var fileType: AVFileType {
    switch self {
    case .mov: return .mov
    case .mp4: return .mp4
    }
  }

  var fileExtension: String { rawValue }

  var displayName: String {
    switch self {
    case .mov: return "MOV"
    case .mp4: return "MP4"
    }
  }
}

// MARK: - Video Quality

enum VideoQuality: String, CaseIterable, Codable {
  case high
  case medium
  case low

  /// Bitrate multiplier per pixel (bits per pixel per second)
  var bitrateMultiplier: Int {
    switch self {
    case .high: return 6
    case .medium: return 4
    case .low: return 2
    }
  }
}

// MARK: - Recording State

enum RecordingState: Equatable {
  case idle
  case preparing
  case recording
  case paused
  case stopping
}

// MARK: - Recording Error

enum RecordingError: Error, LocalizedError {
  case permissionDenied
  case noDisplayFound
  case setupFailed(String)
  case writeFailed(String)
  case cancelled

  var errorDescription: String? {
    switch self {
    case .permissionDenied: return "Screen recording permission denied"
    case .noDisplayFound: return "No display found"
    case .setupFailed(let msg): return "Setup failed: \(msg)"
    case .writeFailed(let msg): return "Write failed: \(msg)"
    case .cancelled: return "Recording cancelled"
    }
  }
}

// MARK: - Screen Recording Manager

@MainActor
final class ScreenRecordingManager: NSObject, ObservableObject {

  static let shared = ScreenRecordingManager()

  // MARK: - Published State

  @Published private(set) var state: RecordingState = .idle
  @Published private(set) var elapsedSeconds: Int = 0
  @Published private(set) var error: RecordingError?

  var formattedDuration: String {
    let mins = elapsedSeconds / 60
    let secs = elapsedSeconds % 60
    return String(format: "%02d:%02d", mins, secs)
  }

  var isRecording: Bool { state == .recording }
  var isPaused: Bool { state == .paused }
  var isActive: Bool { state != .idle }

  // MARK: - Recording Components

  private var stream: SCStream?
  private let session = RecordingSession()  // Thread-safe session for frame writing

  // MARK: - Timing

  private var timer: Timer?
  private var startTime: Date?
  private var pausedDuration: TimeInterval = 0
  private var pauseStartTime: Date?

  // MARK: - Configuration

  private var recordingRect: CGRect = .zero
  private var videoFormat: VideoFormat = .mov
  private var videoQuality: VideoQuality = .high
  private var fps: Int = 30
  private var captureAudio: Bool = true
  private var outputURL: URL?

  // Queue for frame processing
  private let processingQueue = DispatchQueue(label: "com.zapshot.recording", qos: .userInitiated)

  private override init() {
    super.init()
  }

  // MARK: - Public API

  /// Prepare recording with specified parameters
  func prepareRecording(
    rect: CGRect,
    format: VideoFormat = .mov,
    quality: VideoQuality = .high,
    fps: Int = 30,
    captureAudio: Bool = true,
    saveDirectory: URL
  ) async throws {
    guard state == .idle else { return }
    state = .preparing
    error = nil
    session.sessionStarted = false

    self.recordingRect = rect
    self.videoFormat = format
    self.videoQuality = quality
    self.fps = fps
    self.captureAudio = captureAudio

    // Check permission
    let content: SCShareableContent
    do {
      content = try await SCShareableContent.current
    } catch {
      state = .idle
      self.error = .permissionDenied
      throw RecordingError.permissionDenied
    }

    // Find display containing rect
    guard
      let display = content.displays.first(where: { display in
        let frame = CGRect(
          x: display.frame.origin.x,
          y: display.frame.origin.y,
          width: CGFloat(display.width),
          height: CGFloat(display.height)
        )
        return frame.intersects(rect)
      }) ?? content.displays.first
    else {
      state = .idle
      self.error = .noDisplayFound
      throw RecordingError.noDisplayFound
    }

    // Get scale factor for Retina
    let scaleFactor: CGFloat
    if let screen = NSScreen.screens.first(where: {
      Int($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0)
        == display.displayID
    }) {
      scaleFactor = screen.backingScaleFactor
    } else {
      scaleFactor = 2.0
    }

    let outputWidth = Int(ceil(rect.width * scaleFactor))
    let outputHeight = Int(ceil(rect.height * scaleFactor))

    // Generate output URL
    let fileName = generateFileName()
    try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
    outputURL = saveDirectory.appendingPathComponent("\(fileName).\(format.fileExtension)")

    // Setup AVAssetWriter
    try setupAssetWriter(width: outputWidth, height: outputHeight)

    // Setup SCStream
    try await setupStream(display: display, rect: rect, scaleFactor: scaleFactor)
  }

  /// Start the recording
  func startRecording() async throws {
    guard state == .preparing else { return }

    session.assetWriter?.startWriting()

    // Validate writer status
    guard session.assetWriter?.status == .writing else {
      let errorMsg = session.assetWriter?.error?.localizedDescription ?? "Failed to start writing"
      state = .idle
      self.error = .setupFailed(errorMsg)
      throw RecordingError.setupFailed(errorMsg)
    }

    // Session will start lazily when first sample buffer arrives
    // This ensures timestamp synchronization with SCStream

    do {
      try await stream?.startCapture()
    } catch {
      state = .idle
      self.error = .setupFailed(error.localizedDescription)
      throw RecordingError.setupFailed(error.localizedDescription)
    }

    session.isCapturing = true

    state = .recording
    self.startTime = Date()
    elapsedSeconds = 0
    pausedDuration = 0
    startTimer()
  }

  /// Pause the recording
  func pauseRecording() {
    guard state == .recording else { return }
    session.isCapturing = false
    pauseStartTime = Date()
    state = .paused
  }

  /// Resume the recording
  func resumeRecording() {
    guard state == .paused, let pauseStart = pauseStartTime else { return }
    pausedDuration += Date().timeIntervalSince(pauseStart)
    pauseStartTime = nil
    session.isCapturing = true
    state = .recording
  }

  /// Toggle pause/resume
  func togglePause() {
    if state == .recording {
      pauseRecording()
    } else if state == .paused {
      resumeRecording()
    }
  }

  /// Stop the recording and save the file
  func stopRecording() async -> URL? {
    guard state == .recording || state == .paused else { return nil }

    session.isCapturing = false

    state = .stopping

    timer?.invalidate()
    timer = nil

    do {
      try await stream?.stopCapture()
    } catch {
      print("Error stopping capture: \(error)")
    }
    stream = nil

    session.finishInputs()

    await session.finishWriting()

    let url = outputURL

    // Reset state
    cleanup()

    return url
  }

  /// Cancel the recording without saving
  func cancelRecording() async {
    timer?.invalidate()
    timer = nil

    do {
      try await stream?.stopCapture()
    } catch {
      print("Error stopping capture: \(error)")
    }
    stream = nil

    session.cancelWriting()
    if let url = outputURL {
      try? FileManager.default.removeItem(at: url)
    }

    cleanup()
  }

  // MARK: - Private Methods

  private func setupAssetWriter(width: Int, height: Int) throws {
    guard let url = outputURL else {
      throw RecordingError.setupFailed("No output URL")
    }

    // Remove existing file if any
    try? FileManager.default.removeItem(at: url)

    let writer = try AVAssetWriter(outputURL: url, fileType: videoFormat.fileType)
    session.assetWriter = writer

    // Video settings (H.264)
    let bitrate = width * height * videoQuality.bitrateMultiplier
    let videoSettings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: bitrate,
        AVVideoExpectedSourceFrameRateKey: fps,
        AVVideoMaxKeyFrameIntervalKey: fps,
      ],
    ]
    let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    videoIn.expectsMediaDataInRealTime = true
    session.videoInput = videoIn
    writer.add(videoIn)

    // Create pixel buffer adaptor for BGRA input from ScreenCaptureKit
    let sourcePixelBufferAttributes: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: width,
      kCVPixelBufferHeightKey as String: height,
    ]
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: videoIn,
      sourcePixelBufferAttributes: sourcePixelBufferAttributes
    )
    session.pixelBufferAdaptor = adaptor

    // Audio settings (AAC) - optional
    if captureAudio {
      let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 128000,
      ]
      let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
      audioIn.expectsMediaDataInRealTime = true
      session.audioInput = audioIn
      writer.add(audioIn)
    }
  }

  private func setupStream(display: SCDisplay, rect: CGRect, scaleFactor: CGFloat) async throws {
    let filter = SCContentFilter(display: display, excludingWindows: [])

    let config = SCStreamConfiguration()
    config.width = Int(ceil(rect.width * scaleFactor))
    config.height = Int(ceil(rect.height * scaleFactor))
    config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.showsCursor = true

    // Convert rect to sourceRect (top-left origin)
    let displayFrame = display.frame
    let relativeRect = CGRect(
      x: rect.origin.x - displayFrame.origin.x,
      y: rect.origin.y - displayFrame.origin.y,
      width: rect.width,
      height: rect.height
    )
    let flippedY = displayFrame.height - relativeRect.origin.y - relativeRect.height
    config.sourceRect = CGRect(
      x: relativeRect.origin.x,
      y: flippedY,
      width: relativeRect.width,
      height: relativeRect.height
    )

    // Audio configuration
    if captureAudio {
      config.capturesAudio = true
      config.excludesCurrentProcessAudio = true
      config.sampleRate = 48000
      config.channelCount = 2
    }

    stream = SCStream(filter: filter, configuration: config, delegate: nil)
    try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: processingQueue)

    if captureAudio {
      try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: processingQueue)
    }
  }

  private func startTimer() {
    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.updateElapsedTime()
      }
    }
    }

  private func updateElapsedTime() {
    guard let start = startTime, state == .recording else { return }
    elapsedSeconds = Int(Date().timeIntervalSince(start) - pausedDuration)
  }

  private func generateFileName() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    return "ZapShot_Recording_\(formatter.string(from: Date()))"
  }

  private func cleanup() {
    session.reset()
    outputURL = nil
    state = .idle
    elapsedSeconds = 0
  }
}

// MARK: - SCStreamOutput

extension ScreenRecordingManager: SCStreamOutput {
  nonisolated func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard sampleBuffer.isValid else { return }

    // Write frames using the thread-safe session (no @MainActor crossing)
    switch type {
    case .screen:
      session.appendVideoSample(sampleBuffer)
    case .audio:
      session.appendAudioSample(sampleBuffer)
    case .microphone:
      break
    @unknown default:
      break
    }
  }
}
