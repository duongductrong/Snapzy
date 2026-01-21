# Research Report: macOS Screen Recording APIs

## Executive Summary
ScreenCaptureKit (macOS 12.3+) is the recommended framework for screen recording. Combined with AVAssetWriter for video encoding, it provides area selection, multiple format support (.mov, .mp4), and audio capture.

## Key Frameworks

### 1. ScreenCaptureKit (macOS 12.3+)
Primary framework for high-performance screen capture.

**Core Classes:**
- `SCShareableContent` - enumerate displays, windows, apps
- `SCContentFilter` - define what to capture (display/window/area)
- `SCStreamConfiguration` - configure resolution, FPS, audio
- `SCStream` - continuous capture stream
- `SCStreamOutput` - receive CMSampleBuffer frames

**Area Recording Setup:**
```swift
import ScreenCaptureKit

// Get content
let content = try await SCShareableContent.current
guard let display = content.displays.first else { return }

// Create filter for specific display
let filter = SCContentFilter(display: display, excludingWindows: [])

// Configure stream
let config = SCStreamConfiguration()
config.width = Int(rect.width * scaleFactor)
config.height = Int(rect.height * scaleFactor)
config.sourceRect = rect  // Area to capture
config.capturesAudio = true
config.sampleRate = 48000
config.channelCount = 2

// Create and start stream
let stream = SCStream(filter: filter, configuration: config, delegate: self)
try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .main)
try await stream.startCapture()
```

### 2. AVAssetWriter (AVFoundation)
Write video/audio samples to file.

**Setup for .mov/.mp4:**
```swift
import AVFoundation

let outputURL = URL(fileURLWithPath: "/path/to/output.mov")
let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov) // or .mp4

// Video input settings (H.264)
let videoSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height
]
let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
videoInput.expectsMediaDataInRealTime = true
writer.add(videoInput)

// Audio input settings (AAC)
let audioSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: 48000,
    AVNumberOfChannelsKey: 2
]
let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
audioInput.expectsMediaDataInRealTime = true
writer.add(audioInput)

writer.startWriting()
writer.startSession(atSourceTime: .zero)
```

### 3. SCStreamOutput Protocol
Receive video/audio frames:
```swift
extension Recorder: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        switch type {
        case .screen:
            if videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
            }
        case .audio:
            if audioInput.isReadyForMoreMediaData {
                audioInput.append(sampleBuffer)
            }
        @unknown default: break
        }
    }
}
```

## Video Format Options

| Format | File Type | Codec | Pros | Cons |
|--------|-----------|-------|------|------|
| .mov | AVFileType.mov | H.264/HEVC | Native macOS, best quality | Larger files |
| .mp4 | AVFileType.mp4 | H.264 | Universal compatibility | Slightly less features |

**Codec Options:**
- `AVVideoCodecType.h264` - universal, hardware accelerated
- `AVVideoCodecType.hevc` - better compression, macOS 10.13+

## Audio Capture
```swift
config.capturesAudio = true           // Enable audio
config.excludesCurrentProcessAudio = true  // Don't capture app's own audio
config.sampleRate = 48000
config.channelCount = 2
```

For microphone: Use AVAudioEngine separately and mix with system audio.

## Permission Handling
Same as screenshots - uses Screen Recording permission in System Preferences.

## Sources
- [Apple ScreenCaptureKit Documentation](https://developer.apple.com/documentation/screencapturekit)
- [Apple AVFoundation Documentation](https://developer.apple.com/documentation/avfoundation)
- [WWDC 2022: Meet ScreenCaptureKit](https://developer.apple.com/videos/play/wwdc2022/10156/)
