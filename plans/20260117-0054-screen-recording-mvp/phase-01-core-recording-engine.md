# Phase 1: Core Recording Engine

## Context
- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** None (foundational)
- **Research:** [ScreenCaptureKit Report](./research/researcher-01-screencapturekit-report.md)

## Overview
| Field | Value |
|-------|-------|
| Date | 2026-01-17 |
| Priority | P0 - Critical |
| Status | pending |
| Effort | 4-6 hours |

Create `ScreenRecorderManager` - core engine handling SCStream video capture, AVAssetWriter file output, and optional microphone audio mixing.

## Key Insights
1. **SCStream** provides `CMSampleBuffer` frames via delegate - must process on dedicated queue
2. **AVAssetWriter** needs `startSession(atSourceTime:)` called with first frame's timestamp
3. **Audio sync** - System audio via SCStream, mic via AVCaptureDevice - separate tracks
4. **Permissions** - Screen recording permission already handled; mic needs separate request
5. **Codec** - H.264 with 10Mbps bitrate for quality/size balance

## Requirements

### Functional
- [x] Start/stop video recording of display or area
- [x] Capture system audio (optional, exclude app's own audio)
- [x] Capture microphone audio (user toggle)
- [x] Output MP4 file to temp directory
- [x] Provide recording state via Combine publisher
- [x] Handle permission requests for mic

### Non-Functional
- Frame rate: 60 FPS max, configurable
- Resolution: Retina-aware (2x scale factor)
- File format: MP4 (H.264 video, AAC audio)
- Memory: Efficient buffer handling for long recordings

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  ScreenRecorderManager                   │
├─────────────────────────────────────────────────────────┤
│ Properties:                                              │
│   - isRecording: Bool (Published)                        │
│   - recordingDuration: TimeInterval (Published)          │
│   - micEnabled: Bool                                     │
│   - currentOutputURL: URL?                               │
├─────────────────────────────────────────────────────────┤
│ Methods:                                                 │
│   + startRecording(filter:, config:) async throws        │
│   + stopRecording() async -> URL                         │
│   + requestMicPermission() async -> Bool                 │
├─────────────────────────────────────────────────────────┤
│ Private:                                                 │
│   - stream: SCStream?                                    │
│   - writer: AVAssetWriter?                               │
│   - videoInput: AVAssetWriterInput?                      │
│   - audioInput: AVAssetWriterInput?                      │
│   - micInput: AVAssetWriterInput?                        │
│   - captureQueue: DispatchQueue                          │
│   - audioQueue: DispatchQueue                            │
└─────────────────────────────────────────────────────────┘
         │ implements
         ▼
┌─────────────────────────────────────────────────────────┐
│              SCStreamOutput (Protocol)                   │
│   stream(_:didOutputSampleBuffer:of:)                    │
└─────────────────────────────────────────────────────────┘
```

## Related Code Files
| File | Purpose |
|------|---------|
| `ZapShot/Core/ScreenCaptureManager.swift` | Reference for SCShareableContent, permission handling |
| `ZapShot/Core/ScreenCaptureViewModel.swift` | Reference for state management pattern |

## Code Draft

```swift
//
//  ScreenRecorderManager.swift
//  ZapShot
//
//  Core manager for screen recording functionality
//

import AVFoundation
import Combine
import Foundation
import ScreenCaptureKit

/// Recording state
enum RecordingState: Equatable {
  case idle
  case preparing
  case recording
  case stopping
  case failed(String)
}

/// Recording configuration
struct RecordingConfig {
  var frameRate: Int = 60
  var captureSystemAudio: Bool = true
  var captureMicrophone: Bool = false
  var videoCodec: AVVideoCodecType = .h264
  var videoBitRate: Int = 10_000_000  // 10 Mbps
  var audioBitRate: Int = 128_000     // 128 kbps
}

/// Manager for screen recording operations
@MainActor
final class ScreenRecorderManager: NSObject, ObservableObject {

  static let shared = ScreenRecorderManager()

  // MARK: - Published State

  @Published private(set) var state: RecordingState = .idle
  @Published private(set) var recordingDuration: TimeInterval = 0
  @Published var micEnabled: Bool = false

  var isRecording: Bool {
    state == .recording
  }

  // MARK: - Private Properties

  private var stream: SCStream?
  private var writer: AVAssetWriter?
  private var videoInput: AVAssetWriterInput?
  private var systemAudioInput: AVAssetWriterInput?
  private var micAudioInput: AVAssetWriterInput?

  private var currentOutputURL: URL?
  private var recordingStartTime: Date?
  private var durationTimer: Timer?

  private let captureQueue = DispatchQueue(label: "com.zapshot.capture.video")
  private let audioQueue = DispatchQueue(label: "com.zapshot.capture.audio")

  private var sessionStarted = false

  // MARK: - Mic Capture (AVCaptureSession)

  private var micCaptureSession: AVCaptureSession?
  private var micOutput: AVCaptureAudioDataOutput?

  // MARK: - Public API

  /// Start recording with given filter and config
  func startRecording(
    filter: SCContentFilter,
    config: RecordingConfig = RecordingConfig()
  ) async throws {
    guard state == .idle else {
      throw RecordingError.alreadyRecording
    }

    state = .preparing
    sessionStarted = false

    do {
      // Setup output file
      let outputURL = generateOutputURL()
      currentOutputURL = outputURL

      // Setup AVAssetWriter
      try setupWriter(url: outputURL, config: config)

      // Setup SCStream
      try await setupStream(filter: filter, config: config)

      // Setup mic if enabled
      if config.captureMicrophone {
        try setupMicCapture(config: config)
      }

      // Start capture
      try await stream?.startCapture()
      micCaptureSession?.startRunning()

      recordingStartTime = Date()
      startDurationTimer()
      state = .recording

    } catch {
      state = .failed(error.localizedDescription)
      cleanup()
      throw error
    }
  }

  /// Stop recording and return output URL
  func stopRecording() async throws -> URL {
    guard state == .recording else {
      throw RecordingError.notRecording
    }

    state = .stopping
    stopDurationTimer()

    // Stop captures
    try? await stream?.stopCapture()
    micCaptureSession?.stopRunning()

    // Finalize writer
    videoInput?.markAsFinished()
    systemAudioInput?.markAsFinished()
    micAudioInput?.markAsFinished()

    await writer?.finishWriting()

    guard let outputURL = currentOutputURL,
          writer?.status == .completed else {
      let error = writer?.error?.localizedDescription ?? "Unknown error"
      state = .failed(error)
      cleanup()
      throw RecordingError.writeFailed(error)
    }

    cleanup()
    state = .idle
    return outputURL
  }

  /// Request microphone permission
  func requestMicPermission() async -> Bool {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    switch status {
    case .authorized:
      return true
    case .notDetermined:
      return await AVCaptureDevice.requestAccess(for: .audio)
    default:
      return false
    }
  }

  // MARK: - Private Setup Methods

  private func generateOutputURL() -> URL {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    let filename = "ZapShot_Recording_\(formatter.string(from: Date())).mp4"
    return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
  }

  private func setupWriter(url: URL, config: RecordingConfig) throws {
    writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

    // Video input will be configured when first frame arrives (need dimensions)
    // Audio inputs configured here

    if config.captureSystemAudio {
      let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44100,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: config.audioBitRate
      ]
      systemAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
      systemAudioInput?.expectsMediaDataInRealTime = true
      writer?.add(systemAudioInput!)
    }

    if config.captureMicrophone {
      let micSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44100,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: config.audioBitRate
      ]
      micAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: micSettings)
      micAudioInput?.expectsMediaDataInRealTime = true
      writer?.add(micAudioInput!)
    }
  }

  private func setupStream(filter: SCContentFilter, config: RecordingConfig) async throws {
    let streamConfig = SCStreamConfiguration()

    // Get dimensions from filter's display
    let content = try await SCShareableContent.current
    if let display = content.displays.first {
      streamConfig.width = display.width * 2  // Retina
      streamConfig.height = display.height * 2
    }

    streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
    streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.frameRate))
    streamConfig.queueDepth = 5
    streamConfig.showsCursor = true

    if config.captureSystemAudio {
      streamConfig.capturesAudio = true
      streamConfig.excludesCurrentProcessAudio = true
    }

    stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)

    try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
    if config.captureSystemAudio {
      try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
    }
  }

  private func setupMicCapture(config: RecordingConfig) throws {
    guard let device = AVCaptureDevice.default(for: .audio) else {
      throw RecordingError.micNotAvailable
    }

    let session = AVCaptureSession()
    let input = try AVCaptureDeviceInput(device: device)
    session.addInput(input)

    let output = AVCaptureAudioDataOutput()
    output.setSampleBufferDelegate(self, queue: audioQueue)
    session.addOutput(output)

    micCaptureSession = session
    micOutput = output
  }

  private func setupVideoInput(from sampleBuffer: CMSampleBuffer, config: RecordingConfig) {
    guard videoInput == nil,
          let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }

    let dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc)

    let videoSettings: [String: Any] = [
      AVVideoCodecKey: config.videoCodec,
      AVVideoWidthKey: dimensions.width,
      AVVideoHeightKey: dimensions.height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: config.videoBitRate,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
      ]
    ]

    videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    videoInput?.expectsMediaDataInRealTime = true
    writer?.add(videoInput!)
  }

  // MARK: - Duration Timer

  private func startDurationTimer() {
    durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, let start = self.recordingStartTime else { return }
        self.recordingDuration = Date().timeIntervalSince(start)
      }
    }
  }

  private func stopDurationTimer() {
    durationTimer?.invalidate()
    durationTimer = nil
    recordingDuration = 0
  }

  // MARK: - Cleanup

  private func cleanup() {
    stream = nil
    writer = nil
    videoInput = nil
    systemAudioInput = nil
    micAudioInput = nil
    micCaptureSession = nil
    micOutput = nil
    currentOutputURL = nil
    recordingStartTime = nil
    sessionStarted = false
  }
}

// MARK: - SCStreamOutput

extension ScreenRecorderManager: SCStreamOutput {
  nonisolated func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    Task { @MainActor in
      guard state == .recording else { return }

      // Start session on first frame
      if !sessionStarted {
        writer?.startWriting()
        writer?.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
        sessionStarted = true

        // Setup video input with actual dimensions
        if type == .screen {
          setupVideoInput(from: sampleBuffer, config: RecordingConfig())
        }
      }

      switch type {
      case .screen:
        if let input = videoInput, input.isReadyForMoreMediaData {
          input.append(sampleBuffer)
        }
      case .audio:
        if let input = systemAudioInput, input.isReadyForMoreMediaData {
          input.append(sampleBuffer)
        }
      @unknown default:
        break
      }
    }
  }
}

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

extension ScreenRecorderManager: AVCaptureAudioDataOutputSampleBufferDelegate {
  nonisolated func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    Task { @MainActor in
      guard state == .recording,
            let input = micAudioInput,
            input.isReadyForMoreMediaData else { return }
      input.append(sampleBuffer)
    }
  }
}

// MARK: - Errors

enum RecordingError: Error, LocalizedError {
  case alreadyRecording
  case notRecording
  case writeFailed(String)
  case micNotAvailable

  var errorDescription: String? {
    switch self {
    case .alreadyRecording: return "Recording already in progress"
    case .notRecording: return "No recording in progress"
    case .writeFailed(let reason): return "Failed to write: \(reason)"
    case .micNotAvailable: return "Microphone not available"
    }
  }
}
```

## Implementation Steps

### Step 1: Create ScreenRecorderManager file
- [ ] Create `ZapShot/Core/ScreenRecorderManager.swift`
- [ ] Add basic class structure with published properties
- [ ] Add RecordingState, RecordingConfig, RecordingError enums

### Step 2: Implement AVAssetWriter setup
- [ ] Add `setupWriter(url:config:)` method
- [ ] Configure video settings (H.264, bitrate)
- [ ] Configure audio settings (AAC, 44.1kHz)
- [ ] Handle output URL generation

### Step 3: Implement SCStream setup
- [ ] Add `setupStream(filter:config:)` method
- [ ] Configure resolution, frame rate, pixel format
- [ ] Add stream outputs for video and audio
- [ ] Implement SCStreamOutput delegate

### Step 4: Implement mic capture
- [ ] Add AVCaptureSession for mic
- [ ] Implement AVCaptureAudioDataOutputSampleBufferDelegate
- [ ] Add mic permission request method

### Step 5: Implement start/stop flow
- [ ] Add `startRecording(filter:config:)` async method
- [ ] Add `stopRecording()` async method
- [ ] Handle session timing (startSession on first frame)
- [ ] Implement cleanup

### Step 6: Add duration timer
- [ ] Add recordingDuration published property
- [ ] Implement timer start/stop

### Step 7: Testing
- [ ] Test fullscreen recording
- [ ] Test area recording
- [ ] Test with/without system audio
- [ ] Test with/without mic
- [ ] Verify output file playable

## Todo
- [ ] Create ScreenRecorderManager.swift
- [ ] Implement video capture via SCStream
- [ ] Implement AVAssetWriter output
- [ ] Add system audio capture
- [ ] Add mic capture with permission
- [ ] Add duration tracking
- [ ] Write unit tests

## Success Criteria
1. Can record fullscreen to MP4 file
2. Can record custom area to MP4 file
3. System audio captured when enabled
4. Mic audio captured when enabled (separate track)
5. Recording duration tracked accurately
6. State published via Combine for UI binding
7. Files playable in QuickTime/Finder preview

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Audio/video sync drift | Medium | High | Use same timebase, sync on first frame |
| Memory pressure on long recordings | Medium | Medium | Use efficient buffer handling, test 10+ min |
| Mic permission denied | Low | Low | Graceful fallback, clear error message |
| Write performance issues | Low | High | Use SSD temp dir, appropriate queue priorities |

## Security Considerations
1. **Permissions** - Only request mic when user enables toggle
2. **File cleanup** - Temp files should be cleaned on app quit or after save
3. **No sensitive data** - Don't log file paths with user data

## Next Steps
After completion:
1. Proceed to Phase 3 (Recording Toolbar UI) - needs ScreenRecorderManager
2. Phase 2 (Keyboard Shortcuts) can run in parallel

## Unresolved Questions
1. Should we support HEVC (H.265) codec for smaller files? Requires macOS 10.13+
2. How to handle recording when display disconnects mid-recording?
3. Should we add pause/resume capability for future versions?
