# Research Report: ScreenCaptureKit for Video Recording

## Overview
ScreenCaptureKit (macOS 12.3+) provides high-performance screen/audio capture via `CMSampleBuffer` objects.

## 1. SCStream Configuration for Video

```swift
let filter = SCContentFilter(display: display, excludingWindows: [])
let config = SCStreamConfiguration()
config.width = Int(rect.width * scaleFactor)
config.height = Int(rect.height * scaleFactor)
config.pixelFormat = kCVPixelFormatType_32BGRA
config.queueDepth = 5  // Default 3, max 8

let stream = SCStream(filter: filter, configuration: config, delegate: self)
try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
try await stream.startCapture()
```

## 2. Quality, Frame Rate, Codec Settings

```swift
// Frame rate control
config.minimumFrameInterval = CMTime(value: 1, timescale: 60) // 60 FPS

// For AVAssetWriterInput
let videoSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 10_000_000, // 10 Mbps
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
    ]
]
```

## 3. Audio Capture

```swift
// Enable audio in config
config.capturesAudio = true
config.excludesCurrentProcessAudio = true // Exclude app's own audio

// For microphone - use AVCaptureDevice separately
let audioSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: 44100,
    AVNumberOfChannelsKey: 2
]

// Add audio stream output
try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
```

## 4. AVAssetWriter Integration

```swift
// Setup
let outputURL = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
    .appendingPathExtension("mp4")

let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
videoInput.expectsMediaDataInRealTime = true
writer.add(videoInput)

let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
audioInput.expectsMediaDataInRealTime = true
writer.add(audioInput)

writer.startWriting()

// On first frame
writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)

// Append samples
if videoInput.isReadyForMoreMediaData {
    videoInput.append(sampleBuffer)
}
```

## 5. Start/Stop Best Practices

**Starting:**
- Call `startWriting()` before first frame
- Use first frame's `presentationTimeStamp` for `startSession(atSourceTime:)`
- Request permissions beforehand

**Stopping:**
```swift
await stream.stopCapture()
videoInput.markAsFinished()
audioInput.markAsFinished()
await writer.finishWriting()
// Output file ready at outputURL
```

**Permission Handling:**
```swift
let content = try await SCShareableContent.current
// If permission not granted, throws error - prompt user
```

## Key Classes
- `SCStream` - Main capture stream
- `SCStreamConfiguration` - Video/audio settings
- `SCContentFilter` - What to capture
- `SCStreamOutput` - Protocol for receiving frames
- `AVAssetWriter` - File writing
- `AVAssetWriterInput` - Video/audio track inputs

## Sources
- Apple ScreenCaptureKit Documentation
- Apple AVFoundation AVAssetWriter Documentation
