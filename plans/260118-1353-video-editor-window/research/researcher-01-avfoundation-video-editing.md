# AVFoundation Video Editing for macOS

## Summary
Research on AVFoundation capabilities for video playback, trimming, frame extraction, and export on macOS.

## Key Components

### 1. Video Playback with AVPlayer
```swift
import AVKit
import SwiftUI

struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none  // Custom controls
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

// Loading video
let url = URL(fileURLWithPath: "/path/to/video.mp4")
let player = AVPlayer(url: url)
```

### 2. Timeline Seeking
```swift
// Seek to specific time
let targetTime = CMTime(seconds: 5.0, preferredTimescale: 600)
player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)

// Periodic time observer for playhead sync
let interval = CMTime(seconds: 0.033, preferredTimescale: 600) // ~30fps
player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
    let seconds = CMTimeGetSeconds(time)
    // Update UI playhead position
}
```

### 3. Frame Extraction for Thumbnails
```swift
func extractFrames(from asset: AVAsset, count: Int) async -> [NSImage] {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    generator.maximumSize = CGSize(width: 120, height: 68) // Thumbnail size

    guard let duration = try? await asset.load(.duration) else { return [] }
    let totalSeconds = CMTimeGetSeconds(duration)
    let interval = totalSeconds / Double(count)

    var images: [NSImage] = []
    for i in 0..<count {
        let time = CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
        if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
            images.append(NSImage(cgImage: cgImage, size: NSSize(width: 120, height: 68)))
        }
    }
    return images
}
```

### 4. Video Trimming with AVAssetExportSession
```swift
func trimVideo(
    asset: AVAsset,
    startTime: CMTime,
    endTime: CMTime,
    outputURL: URL
) async throws {
    let timeRange = CMTimeRange(start: startTime, end: endTime)

    guard let exportSession = AVAssetExportSession(
        asset: asset,
        presetName: AVAssetExportPresetHighestQuality
    ) else {
        throw NSError(domain: "VideoEditor", code: 1)
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.timeRange = timeRange

    await exportSession.export()

    if exportSession.status != .completed {
        throw exportSession.error ?? NSError(domain: "VideoEditor", code: 2)
    }
}
```

### 5. Save Options: Replace vs Copy
```swift
// Generate copy URL
func generateCopyURL(from original: URL) -> URL {
    let directory = original.deletingLastPathComponent()
    let baseName = original.deletingPathExtension().lastPathComponent
    let ext = original.pathExtension
    return directory.appendingPathComponent("\(baseName)_edited.\(ext)")
}

// Replace original (export to temp, then replace)
func replaceOriginal(asset: AVAsset, originalURL: URL, trimRange: CMTimeRange) async throws {
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".mp4")

    try await trimVideo(asset: asset, startTime: trimRange.start,
                        endTime: trimRange.end, outputURL: tempURL)

    try FileManager.default.removeItem(at: originalURL)
    try FileManager.default.moveItem(at: tempURL, to: originalURL)
}
```

## Key Considerations

1. **Non-destructive Editing**: Use AVMutableComposition for complex edits
2. **Export Presets**: Choose based on quality/size tradeoff
3. **Progress Tracking**: Monitor `exportSession.progress` for UI feedback
4. **Audio Handling**: AVAssetExportSession preserves audio by default
5. **File Types**: Support .mov and .mp4 (match ScreenRecordingManager formats)

## Video Duration & Metadata
```swift
// Get video duration
let duration = try await asset.load(.duration)
let seconds = CMTimeGetSeconds(duration)

// Get video dimensions
if let track = try await asset.loadTracks(withMediaType: .video).first {
    let size = try await track.load(.naturalSize)
}
```

## Sources
- [Apple AVFoundation Documentation](https://developer.apple.com/documentation/avfoundation)
- [AVAssetExportSession](https://developer.apple.com/documentation/avfoundation/avassetexportsession)
- [AVAssetImageGenerator](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator)
