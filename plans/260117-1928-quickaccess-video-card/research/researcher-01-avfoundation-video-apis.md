# Research Report: AVFoundation Video APIs for Thumbnail & Duration

**Date:** 2026-01-17
**Topic:** Video thumbnail generation and duration extraction using AVFoundation

## Summary

AVFoundation provides robust APIs for extracting video thumbnails and duration on macOS.

## Key APIs

### 1. AVAssetImageGenerator - Thumbnail Generation

```swift
import AVFoundation
import AppKit

func generateVideoThumbnail(for videoURL: URL) async -> NSImage? {
    let asset = AVURLAsset(url: videoURL)
    let imageGenerator = AVAssetImageGenerator(asset: asset)
    imageGenerator.appliesPreferredTrackTransform = true
    imageGenerator.maximumSize = CGSize(width: 200, height: 0)

    let time = CMTimeMakeWithSeconds(0, preferredTimescale: 600)

    do {
        let (cgImage, _) = try await imageGenerator.image(at: time)
        return NSImage(cgImage: cgImage, size: NSZeroSize)
    } catch {
        print("Error generating thumbnail: \(error)")
        return nil
    }
}
```

### 2. AVURLAsset - Duration Extraction

```swift
func getVideoDuration(from url: URL) async throws -> TimeInterval {
    let asset = AVAsset(url: url)
    let duration = try await asset.load(.duration)
    return CMTimeGetSeconds(duration)
}
```

### 3. Duration Formatting

```swift
func formatDuration(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "00:00s" }

    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%02d:%02ds", mins, secs)
}
```

## Supported Formats

- `.mov` - QuickTime Movie
- `.mp4` - MPEG-4

## Best Practices

1. **Always async** - Use `async/await` for thumbnail generation
2. **Set `appliesPreferredTrackTransform = true`** - Correct orientation
3. **Use `maximumSize`** - Control thumbnail dimensions
4. **Handle errors gracefully** - Return nil on failure

## Pitfalls to Avoid

- Blocking main thread with synchronous calls
- Ignoring video orientation transform
- Not handling corrupt/invalid video files
