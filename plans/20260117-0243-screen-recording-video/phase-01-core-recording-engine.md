# Phase 1: Core Recording Engine

## Context Links
- [Main Plan](./plan.md)
- [Screen Recording APIs Research](./research/researcher-01-screen-recording-apis.md)
- [Codebase Analysis](./scout/scout-01-codebase-analysis.md)

## Overview
Implement `ScreenRecordingManager` using ScreenCaptureKit SCStream for continuous frame capture and AVAssetWriter for video encoding. Support .mov/.mp4 formats, configurable FPS, optional audio capture.

## Requirements
- R1: Area-based recording using SCStream with sourceRect
- R2: Video formats: .mov (default), .mp4
- R3: Configurable FPS (30/60)
- R4: System audio capture (optional)
- R5: Pause/resume capability
- R6: Timer tracking for elapsed time
- R7: Save to user-configured export location

## Architecture

### Class Diagram
```
ScreenRecordingManager (@MainActor, ObservableObject)
├── Properties
│   ├── state: RecordingState (idle/preparing/recording/paused/stopping)
│   ├── elapsedSeconds: Int
│   ├── formattedDuration: String
│   └── error: RecordingError?
├── Private
│   ├── stream: SCStream?
│   ├── assetWriter: AVAssetWriter?
│   ├── videoInput: AVAssetWriterInput?
│   ├── audioInput: AVAssetWriterInput?
│   ├── timer: Timer?
│   └── startTime: Date?
└── Methods
    ├── prepareRecording(rect:, format:, fps:, captureAudio:)
    ├── startRecording()
    ├── pauseRecording()
    ├── resumeRecording()
    ├── stopRecording() -> URL?
    └── cancelRecording()
```

### Supporting Types
```swift
enum RecordingState { case idle, preparing, recording, paused, stopping }
enum VideoFormat { case mov, mp4 }
enum RecordingError: Error { case permissionDenied, setupFailed, writeFailed, cancelled }
```

## Related Code Files

### Reference (Read)
| File | Purpose |
|------|---------|
| `ZapShot/Core/ScreenCaptureManager.swift` | Pattern for SCShareableContent, permissions |
| `ZapShot/Features/Preferences/PreferencesKeys.swift` | AppStorage keys pattern |

### Create
| File | Purpose |
|------|---------|
| `ZapShot/Core/ScreenRecordingManager.swift` | Main recording engine |

## Implementation Steps

### Step 1: Create VideoFormat and RecordingState enums
```swift
// In ScreenRecordingManager.swift
enum VideoFormat: String, CaseIterable {
    case mov, mp4

    var fileType: AVFileType {
        switch self {
        case .mov: return .mov
        case .mp4: return .mp4
        }
    }

    var fileExtension: String { rawValue }
}

enum RecordingState: Equatable {
    case idle
    case preparing
    case recording
    case paused
    case stopping
}

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
```

### Step 2: Create ScreenRecordingManager class skeleton
```swift
@MainActor
final class ScreenRecordingManager: NSObject, ObservableObject {
    static let shared = ScreenRecordingManager()

    // Published state
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

    // Recording components
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?

    // Timing
    private var timer: Timer?
    private var startTime: Date?
    private var pausedDuration: TimeInterval = 0
    private var pauseStartTime: Date?

    // Config
    private var recordingRect: CGRect = .zero
    private var videoFormat: VideoFormat = .mov
    private var fps: Int = 30
    private var captureAudio: Bool = true
    private var outputURL: URL?

    // Queue for frame processing
    private let processingQueue = DispatchQueue(label: "com.zapshot.recording", qos: .userInitiated)

    private override init() { super.init() }
}
```

### Step 3: Implement prepareRecording
```swift
func prepareRecording(
    rect: CGRect,
    format: VideoFormat = .mov,
    fps: Int = 30,
    captureAudio: Bool = true,
    saveDirectory: URL
) async throws {
    guard state == .idle else { return }
    state = .preparing

    self.recordingRect = rect
    self.videoFormat = format
    self.fps = fps
    self.captureAudio = captureAudio

    // Check permission
    let content: SCShareableContent
    do {
        content = try await SCShareableContent.current
    } catch {
        state = .idle
        throw RecordingError.permissionDenied
    }

    // Find display containing rect
    guard let display = content.displays.first(where: { display in
        let frame = CGRect(x: display.frame.origin.x, y: display.frame.origin.y,
                          width: CGFloat(display.width), height: CGFloat(display.height))
        return frame.intersects(rect)
    }) ?? content.displays.first else {
        state = .idle
        throw RecordingError.noDisplayFound
    }

    // Generate output URL
    let fileName = generateFileName()
    try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
    outputURL = saveDirectory.appendingPathComponent("\(fileName).\(format.fileExtension)")

    // Setup AVAssetWriter
    try setupAssetWriter(width: Int(rect.width * 2), height: Int(rect.height * 2))

    // Setup SCStream
    try await setupStream(display: display, rect: rect)
}
```

### Step 4: Implement setupAssetWriter
```swift
private func setupAssetWriter(width: Int, height: Int) throws {
    guard let url = outputURL else { throw RecordingError.setupFailed("No output URL") }

    // Remove existing file if any
    try? FileManager.default.removeItem(at: url)

    assetWriter = try AVAssetWriter(outputURL: url, fileType: videoFormat.fileType)

    // Video settings (H.264)
    let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: width * height * 4,
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoMaxKeyFrameIntervalKey: fps
        ]
    ]
    videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    videoInput?.expectsMediaDataInRealTime = true
    assetWriter?.add(videoInput!)

    // Audio settings (AAC) - optional
    if captureAudio {
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true
        assetWriter?.add(audioInput!)
    }
}
```

### Step 5: Implement setupStream
```swift
private func setupStream(display: SCDisplay, rect: CGRect) async throws {
    let filter = SCContentFilter(display: display, excludingWindows: [])

    let config = SCStreamConfiguration()
    config.width = Int(rect.width * 2)  // Retina
    config.height = Int(rect.height * 2)
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
    config.sourceRect = CGRect(x: relativeRect.origin.x, y: flippedY,
                               width: relativeRect.width, height: relativeRect.height)

    // Audio
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
```

### Step 6: Implement startRecording
```swift
func startRecording() async throws {
    guard state == .preparing else { return }

    assetWriter?.startWriting()
    try await stream?.startCapture()

    await MainActor.run {
        state = .recording
        startTime = Date()
        elapsedSeconds = 0
        pausedDuration = 0
        startTimer()
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
```

### Step 7: Implement pause/resume
```swift
func pauseRecording() {
    guard state == .recording else { return }
    pauseStartTime = Date()
    state = .paused
}

func resumeRecording() {
    guard state == .paused, let pauseStart = pauseStartTime else { return }
    pausedDuration += Date().timeIntervalSince(pauseStart)
    pauseStartTime = nil
    state = .recording
}

func togglePause() {
    if state == .recording {
        pauseRecording()
    } else if state == .paused {
        resumeRecording()
    }
}
```

### Step 8: Implement stopRecording
```swift
func stopRecording() async -> URL? {
    guard state == .recording || state == .paused else { return nil }
    state = .stopping

    timer?.invalidate()
    timer = nil

    try? await stream?.stopCapture()
    stream = nil

    videoInput?.markAsFinished()
    audioInput?.markAsFinished()

    await assetWriter?.finishWriting()

    let url = outputURL

    // Reset
    await MainActor.run {
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        outputURL = nil
        state = .idle
        elapsedSeconds = 0
    }

    return url
}
```

### Step 9: Implement cancelRecording
```swift
func cancelRecording() async {
    timer?.invalidate()
    timer = nil

    try? await stream?.stopCapture()
    stream = nil

    assetWriter?.cancelWriting()
    if let url = outputURL {
        try? FileManager.default.removeItem(at: url)
    }

    await MainActor.run {
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        outputURL = nil
        state = .idle
        elapsedSeconds = 0
    }
}
```

### Step 10: Implement SCStreamOutput
```swift
extension ScreenRecordingManager: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream,
                            didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        Task { @MainActor in
            guard self.state == .recording else { return }

            // Start session on first frame
            if self.assetWriter?.status == .unknown {
                self.assetWriter?.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            }

            guard self.assetWriter?.status == .writing else { return }

            switch type {
            case .screen:
                if self.videoInput?.isReadyForMoreMediaData == true {
                    self.videoInput?.append(sampleBuffer)
                }
            case .audio:
                if self.audioInput?.isReadyForMoreMediaData == true {
                    self.audioInput?.append(sampleBuffer)
                }
            @unknown default:
                break
            }
        }
    }
}
```

### Step 11: Add helper method
```swift
private func generateFileName() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    return "ZapShot_Recording_\(formatter.string(from: Date()))"
}
```

## Todo List
- [ ] Create ScreenRecordingManager.swift file
- [ ] Implement VideoFormat, RecordingState, RecordingError enums
- [ ] Implement class skeleton with published properties
- [ ] Implement prepareRecording with display detection
- [ ] Implement setupAssetWriter with video/audio inputs
- [ ] Implement setupStream with SCStream config
- [ ] Implement startRecording with timer
- [ ] Implement pause/resume logic
- [ ] Implement stopRecording with proper cleanup
- [ ] Implement cancelRecording
- [ ] Implement SCStreamOutput extension
- [ ] Test with basic recording flow

## Success Criteria
1. Can record selected area to .mov file
2. Can record to .mp4 file
3. Timer accurately tracks recording duration
4. Pause/resume works without audio sync issues
5. Cancel properly cleans up temp files
6. No memory leaks during extended recording

## Risk Assessment
| Risk | Impact | Mitigation |
|------|--------|------------|
| Audio/video sync drift | High | Use presentationTimeStamp from CMSampleBuffer |
| Memory pressure on long recordings | Medium | Process frames on background queue |
| Permission prompt during recording | Low | Check permission in prepareRecording |
| Multi-monitor sourceRect calculation | Medium | Test thoroughly, use same logic as ScreenCaptureManager |
