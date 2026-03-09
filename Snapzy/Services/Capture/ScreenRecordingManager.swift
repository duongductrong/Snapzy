//
//  ScreenRecordingManager.swift
//  Snapzy
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

  var displayName: String {
    switch self {
    case .high: return "High"
    case .medium: return "Medium"
    case .low: return "Low"
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
  case microphonePermissionDenied
  case noDisplayFound
  case setupFailed(String)
  case writeFailed(String)
  case cancelled

  var errorDescription: String? {
    switch self {
    case .permissionDenied: return "Screen recording permission denied"
    case .microphonePermissionDenied: return "Microphone permission denied"
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
  private var captureSystemAudio: Bool = true
  private var captureMicrophone: Bool = false
  private var excludeOwnApplicationFromCapture: Bool = true
  private var excludeDesktopIconsFromCapture: Bool = false
  private var excludeDesktopWidgetsFromCapture: Bool = false
  private var excludedWindowIDs = Set<CGWindowID>()
  private var exceptedWindowIDs = Set<CGWindowID>()
  private var outputURL: URL?
  private var mouseTracker: RecordingMouseTracker?
  private var exportDirectoryAccess: SandboxFileAccessManager.ScopedAccess?
  private var registeredOutputTypes: Set<SCStreamOutputType> = []

  // Dedicated queues to avoid audio starvation behind video processing work.
  private let videoProcessingQueue = DispatchQueue(
    label: "com.snapzy.recording.video",
    qos: .userInitiated
  )
  private let audioProcessingQueue = DispatchQueue(
    label: "com.snapzy.recording.audio",
    qos: .userInteractive
  )
  private let microphoneProcessingQueue = DispatchQueue(
    label: "com.snapzy.recording.microphone",
    qos: .userInteractive
  )

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
    captureSystemAudio: Bool = true,
    captureMicrophone: Bool = false,
    saveDirectory: URL,
    excludeDesktopIcons: Bool = false,
    excludeDesktopWidgets: Bool = false,
    excludeOwnApplication: Bool = true,
    excludedWindowIDs: [CGWindowID] = []
  ) async throws {
    guard state == .idle else { return }
    state = .preparing
    error = nil
    session.sessionStarted = false

    self.recordingRect = rect
    self.videoFormat = format
    self.videoQuality = quality
    self.fps = fps
    self.captureSystemAudio = captureSystemAudio
    self.captureMicrophone = captureMicrophone
    self.excludeOwnApplicationFromCapture = excludeOwnApplication
    self.excludeDesktopIconsFromCapture = excludeDesktopIcons
    self.excludeDesktopWidgetsFromCapture = excludeDesktopWidgets
    self.excludedWindowIDs = Set(excludedWindowIDs)
    self.exceptedWindowIDs.removeAll()

    // Check permission and get shareable content
    let content: SCShareableContent
    do {
      content = try await SCShareableContent.current
    } catch {
      state = .idle
      self.error = .permissionDenied
      throw RecordingError.permissionDenied
    }

    // Find the display containing the rect using NSScreen (same coordinate system as input rect)
    // Then get the matching SCDisplay by displayID
    var targetScreen: NSScreen?
    for screen in NSScreen.screens {
      if screen.frame.intersects(rect) {
        targetScreen = screen
        break
      }
    }

    // Get the display ID from NSScreen
    let targetDisplayID: CGDirectDisplayID
    if let screen = targetScreen,
       let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
      targetDisplayID = displayID
    } else {
      targetDisplayID = CGMainDisplayID()
    }

    // Find matching SCDisplay
    guard let display = content.displays.first(where: { $0.displayID == Int(targetDisplayID) })
            ?? content.displays.first
    else {
      state = .idle
      self.error = .noDisplayFound
      throw RecordingError.noDisplayFound
    }

    // Get scale factor for Retina from the matching NSScreen
    let scaleFactor: CGFloat
    if let screen = targetScreen {
      scaleFactor = screen.backingScaleFactor
    } else if let screen = NSScreen.screens.first(where: {
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
    exportDirectoryAccess?.stop()
    let directoryAccess = SandboxFileAccessManager.shared.beginAccessingURL(saveDirectory)
    exportDirectoryAccess = directoryAccess

    let scopedSaveDirectory = directoryAccess.url

    do {
      try FileManager.default.createDirectory(at: scopedSaveDirectory, withIntermediateDirectories: true)
    } catch {
      exportDirectoryAccess?.stop()
      exportDirectoryAccess = nil
      state = .idle
      self.error = .writeFailed(error.localizedDescription)
      throw RecordingError.writeFailed(error.localizedDescription)
    }

    outputURL = scopedSaveDirectory.appendingPathComponent("\(fileName).\(format.fileExtension)")

    // Setup AVAssetWriter
    try setupAssetWriter(width: outputWidth, height: outputHeight, captureSystemAudio: captureSystemAudio, captureMicrophone: captureMicrophone)

    try await setupStream(
      display: display,
      rect: rect,
      scaleFactor: scaleFactor,
      captureSystemAudio: captureSystemAudio,
      captureMicrophone: captureMicrophone,
      content: content
    )

    mouseTracker = RecordingMouseTracker(recordingRect: rect, fps: fps)
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
    mouseTracker?.start()

    state = .recording
    DiagnosticLogger.shared.log(.info, .recording, "Recording started \(Int(recordingRect.width))x\(Int(recordingRect.height)) \(fps)fps \(videoFormat.rawValue)")
    self.startTime = Date()
    elapsedSeconds = 0
    pausedDuration = 0
    startTimer()
  }

  /// Pause the recording
  func pauseRecording() {
    guard state == .recording else { return }
    session.isCapturing = false
    mouseTracker?.pause()
    pauseStartTime = Date()
    state = .paused
    DiagnosticLogger.shared.log(.info, .recording, "Recording paused")
  }

  /// Resume the recording
  func resumeRecording() {
    guard state == .paused, let pauseStart = pauseStartTime else { return }
    pausedDuration += Date().timeIntervalSince(pauseStart)
    pauseStartTime = nil
    session.isCapturing = true
    mouseTracker?.resume()
    state = .recording
    DiagnosticLogger.shared.log(.info, .recording, "Recording resumed")
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

    if let activeStream = stream {
      await teardownStream(activeStream)
    }

    session.finishInputs()

    await session.finishWriting()

    let mouseSamples = mouseTracker?.stop() ?? []
    let url = outputURL
    if let url = url {
      if mouseSamples.count >= 2 {
        do {
          let metadata = RecordingMetadata(
            captureSize: recordingRect.size,
            samplesPerSecond: mouseTracker?.samplesPerSecond ?? fps,
            mouseSamples: mouseSamples
          )
          try RecordingMetadataStore.save(metadata, for: url)
        } catch {
          print("[RecordingMetadata] Failed to save mouse tracking data: \(error.localizedDescription)")
        }
      }
      DiagnosticLogger.shared.log(.info, .recording, "Recording stopped: \(url.lastPathComponent) (\(elapsedSeconds)s)")
    }

    // Reset state
    cleanup()

    return url
  }

  /// Cancel the recording without saving
  func cancelRecording() async {
    guard state != .idle else { return }

    timer?.invalidate()
    timer = nil

    if let activeStream = stream {
      await teardownStream(activeStream)
    }

    session.cancelWriting()
    mouseTracker?.reset()
    DiagnosticLogger.shared.log(.info, .recording, "Recording cancelled")
    if let url = outputURL {
      try? FileManager.default.removeItem(at: url)
    }

    cleanup()
  }

  // MARK: - Private Methods

  private func setupAssetWriter(width: Int, height: Int, captureSystemAudio: Bool, captureMicrophone: Bool) throws {
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

    // Audio settings (AAC) for system audio
    if captureSystemAudio {
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

    // Microphone audio settings (AAC) - separate track
    if captureMicrophone {
      let micSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: 1,  // Mono for microphone
        AVEncoderBitRateKey: 64000,
      ]
      let micIn = AVAssetWriterInput(mediaType: .audio, outputSettings: micSettings)
      micIn.expectsMediaDataInRealTime = true
      session.microphoneInput = micIn
      writer.add(micIn)
    }
  }

  private func setupStream(display: SCDisplay, rect: CGRect, scaleFactor: CGFloat, captureSystemAudio: Bool, captureMicrophone: Bool, content: SCShareableContent) async throws {
    let filter = makeContentFilter(display: display, content: content)

    let config = SCStreamConfiguration()
    config.queueDepth = 3
    config.width = Int(ceil(rect.width * scaleFactor))
    config.height = Int(ceil(rect.height * scaleFactor))
    config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.showsCursor = true

    // Get the NSScreen frame for coordinate conversion (Cocoa coordinates)
    // This ensures we use the same coordinate system as the input rect
    guard let matchingScreen = NSScreen.screens.first(where: {
      Int($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0)
        == display.displayID
    }) else {
      throw RecordingError.noDisplayFound
    }

    let screenFrame = matchingScreen.frame

    // Calculate relative rect within the screen (in Cocoa coordinates)
    let relativeRect = CGRect(
      x: rect.origin.x - screenFrame.origin.x,
      y: rect.origin.y - screenFrame.origin.y,
      width: rect.width,
      height: rect.height
    )

    // Clamp to screen bounds
    let screenBounds = CGRect(x: 0, y: 0, width: screenFrame.width, height: screenFrame.height)
    let clampedRect = relativeRect.intersection(screenBounds)

    // Guard against empty intersection
    guard !clampedRect.isEmpty else {
      throw RecordingError.setupFailed("Selection area is outside display bounds")
    }

    // ScreenCaptureKit uses top-left origin for sourceRect
    // Convert from bottom-left (Cocoa) to top-left coordinate system
    let flippedY = screenFrame.height - clampedRect.origin.y - clampedRect.height
    config.sourceRect = CGRect(
      x: clampedRect.origin.x,
      y: flippedY,
      width: clampedRect.width,
      height: clampedRect.height
    )

    // Update dimensions to use clamped rect
    config.width = Int(ceil(clampedRect.width * scaleFactor))
    config.height = Int(ceil(clampedRect.height * scaleFactor))

    // System audio configuration
    if captureSystemAudio {
      config.capturesAudio = true
      config.excludesCurrentProcessAudio = true
      config.sampleRate = 48000
      config.channelCount = 2
    }

    // Microphone configuration (requires macOS 15.0+)
    if captureMicrophone {
      // Check microphone permission before configuring
      let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
      switch micStatus {
      case .notDetermined:
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        if !granted {
          throw RecordingError.microphonePermissionDenied
        }
      case .denied, .restricted:
        throw RecordingError.microphonePermissionDenied
      case .authorized:
        break
      @unknown default:
        break
      }

      if #available(macOS 15.0, *) {
        config.captureMicrophone = true
        config.microphoneCaptureDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID
      }
    }

    stream = SCStream(filter: filter, configuration: config, delegate: nil)
    registeredOutputTypes.removeAll()
    try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoProcessingQueue)
    registeredOutputTypes.insert(.screen)

    if captureSystemAudio {
      try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioProcessingQueue)
      registeredOutputTypes.insert(.audio)
    }

    if captureMicrophone {
      if #available(macOS 15.0, *) {
        try stream?.addStreamOutput(
          self,
          type: .microphone,
          sampleHandlerQueue: microphoneProcessingQueue
        )
        registeredOutputTypes.insert(.microphone)
      }
    }
  }

  private func makeContentFilter(display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
    let iconManager = DesktopIconManager.shared

    if excludeOwnApplicationFromCapture {
      var excludedApps: [SCRunningApplication] = []
      if let bundleID = Bundle.main.bundleIdentifier {
        excludedApps += content.applications.filter { $0.bundleIdentifier == bundleID }
      }

      var exceptedWindows = content.windows.filter { exceptedWindowIDs.contains($0.windowID) }
      if excludeDesktopIconsFromCapture {
        excludedApps += iconManager.getFinderApps(from: content)
        exceptedWindows += iconManager.getVisibleFinderWindows(from: content)
      }
      if excludeDesktopWidgetsFromCapture {
        excludedApps += iconManager.getWidgetApps(from: content)
      }

      return SCContentFilter(
        display: display,
        excludingApplications: uniqueApplications(excludedApps),
        exceptingWindows: uniqueWindows(exceptedWindows)
      )
    }

    var excludedWindows = content.windows.filter { excludedWindowIDs.contains($0.windowID) }
    if excludeDesktopIconsFromCapture {
      excludedWindows += iconManager.getDesktopIconWindows(from: content)
    }
    if excludeDesktopWidgetsFromCapture {
      excludedWindows += iconManager.getWidgetWindows(from: content)
    }

    return SCContentFilter(
      display: display,
      excludingWindows: uniqueWindows(excludedWindows)
    )
  }

  private func uniqueWindows(_ windows: [SCWindow]) -> [SCWindow] {
    var seenWindowIDs = Set<CGWindowID>()
    return windows.filter { seenWindowIDs.insert($0.windowID).inserted }
  }

  private func uniqueApplications(_ applications: [SCRunningApplication]) -> [SCRunningApplication] {
    var seenBundleIDs = Set<String>()
    var uniqueApps: [SCRunningApplication] = []

    for application in applications {
      let bundleID = application.bundleIdentifier
      guard seenBundleIDs.insert(bundleID).inserted else { continue }
      uniqueApps.append(application)
    }

    return uniqueApps
  }

  private func currentDisplay(from content: SCShareableContent) -> SCDisplay? {
    let targetDisplayID: CGDirectDisplayID
    if let screen = NSScreen.screens.first(where: { $0.frame.intersects(recordingRect) }),
       let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
      targetDisplayID = displayID
    } else {
      targetDisplayID = CGMainDisplayID()
    }

    return content.displays.first(where: { $0.displayID == Int(targetDisplayID) })
      ?? content.displays.first
  }

  private func updateContentFilter(for activeStream: SCStream) async {
    do {
      let content = try await SCShareableContent.current
      guard let display = currentDisplay(from: content) else { return }
      let filter = makeContentFilter(display: display, content: content)
      try await activeStream.updateContentFilter(filter)
    } catch {
      print("Failed to update recording filter: \(error.localizedDescription)")
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
    return "Snapzy_Recording_\(formatter.string(from: Date()))"
  }

  private func cleanup() {
    timer?.invalidate()
    timer = nil
    startTime = nil
    pauseStartTime = nil
    pausedDuration = 0
    exportDirectoryAccess?.stop()
    exportDirectoryAccess = nil
    registeredOutputTypes.removeAll()
    excludedWindowIDs.removeAll()
    exceptedWindowIDs.removeAll()
    excludeOwnApplicationFromCapture = true
    excludeDesktopIconsFromCapture = false
    excludeDesktopWidgetsFromCapture = false
    mouseTracker = nil
    session.reset()
    outputURL = nil
    state = .idle
    elapsedSeconds = 0
  }

  private func teardownStream(_ activeStream: SCStream) async {
    // Remove outputs first so SCStream can release pipeline buffers immediately.
    for outputType in registeredOutputTypes {
      do {
        try activeStream.removeStreamOutput(self, type: outputType)
      } catch {
        // Non-fatal: continue best-effort teardown.
      }
    }
    registeredOutputTypes.removeAll()

    do {
      try await activeStream.stopCapture()
    } catch {
      // Ignore error if stream already stopped.
    }

    stream = nil
  }

  /// Add a window to the capture filter's exceptingWindows list
  /// Used to include annotation overlay in recording despite app being excluded
  func addExceptedWindow(windowID: CGWindowID) async {
    guard let activeStream = stream else { return }
    guard excludeOwnApplicationFromCapture else { return }

    exceptedWindowIDs.insert(windowID)
    await updateContentFilter(for: activeStream)
  }
}

// MARK: - SCStreamOutput

extension ScreenRecordingManager: SCStreamOutput {
  nonisolated func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    autoreleasepool {
      guard sampleBuffer.isValid else { return }

      // Write frames using the thread-safe session (no @MainActor crossing)
      switch type {
      case .screen:
        session.appendVideoSample(sampleBuffer)
      case .audio:
        session.appendAudioSample(sampleBuffer)
      case .microphone:
        session.appendMicrophoneSample(sampleBuffer)
      @unknown default:
        break
      }
    }
  }
}
