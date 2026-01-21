# Phase 02: Video Thumbnail Generator

**Date:** 2026-01-17
**Priority:** High
**Status:** Pending

## Context Links

- [Plan Overview](./plan.md)
- [Research: AVFoundation APIs](./research/researcher-01-avfoundation-video-apis.md)

## Overview

Extend `ThumbnailGenerator` to support video files using AVFoundation's `AVAssetImageGenerator` for frame extraction and `AVURLAsset` for duration retrieval.

## Requirements

### Functional
- Generate thumbnail from first frame of video
- Extract video duration as TimeInterval
- Support .mov and .mp4 formats
- Maintain existing image thumbnail functionality

### Non-Functional
- Async operation (non-blocking)
- Graceful error handling with nil return
- Consistent thumbnail sizing with images

## Related Code Files

### Files to Modify
| File | Action | Description |
|------|--------|-------------|
| `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/QuickAccess/ThumbnailGenerator.swift` | MODIFY | Add video support |

## Implementation Steps

### Step 1: Add AVFoundation import

```swift
import AVFoundation
```

### Step 2: Add video file extension detection

```swift
private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

private static func isVideoFile(_ url: URL) -> Bool {
  videoExtensions.contains(url.pathExtension.lowercased())
}
```

### Step 3: Add unified generate method

Update existing `generate` method to detect file type:

```swift
/// Generate thumbnail from image or video URL
/// - Parameters:
///   - url: Source file URL (image or video)
///   - maxSize: Maximum dimension for thumbnail
/// - Returns: Tuple of (thumbnail, duration) where duration is nil for images
static func generate(from url: URL, maxSize: CGFloat = 200) async -> (thumbnail: NSImage?, duration: TimeInterval?) {
  if isVideoFile(url) {
    return await generateFromVideo(url: url, maxSize: maxSize)
  } else {
    let thumbnail = await generateFromImage(url: url, maxSize: maxSize)
    return (thumbnail, nil)
  }
}
```

### Step 4: Rename existing method for images

Rename current `generate` to `generateFromImage`:

```swift
/// Generate thumbnail from image file
private static func generateFromImage(url: URL, maxSize: CGFloat = 200) async -> NSImage? {
  // Existing implementation unchanged
  guard let image = NSImage(contentsOf: url) else { return nil }

  let originalSize = image.size
  guard originalSize.width > 0, originalSize.height > 0 else { return nil }

  let scale: CGFloat
  if originalSize.width > originalSize.height {
    scale = min(maxSize / originalSize.width, 1.0)
  } else {
    scale = min(maxSize / originalSize.height, 1.0)
  }

  if scale >= 1.0 { return image }

  let newSize = CGSize(
    width: originalSize.width * scale,
    height: originalSize.height * scale
  )

  let thumbnail = NSImage(size: newSize)
  thumbnail.lockFocus()
  NSGraphicsContext.current?.imageInterpolation = .high
  image.draw(
    in: NSRect(origin: .zero, size: newSize),
    from: NSRect(origin: .zero, size: originalSize),
    operation: .copy,
    fraction: 1.0
  )
  thumbnail.unlockFocus()

  return thumbnail
}
```

### Step 5: Add video thumbnail generation

```swift
/// Generate thumbnail from video file using AVFoundation
private static func generateFromVideo(url: URL, maxSize: CGFloat) async -> (thumbnail: NSImage?, duration: TimeInterval?) {
  let asset = AVURLAsset(url: url)

  // Get duration
  let duration: TimeInterval?
  do {
    let cmDuration = try await asset.load(.duration)
    duration = CMTimeGetSeconds(cmDuration)
  } catch {
    duration = nil
  }

  // Generate thumbnail from first frame
  let imageGenerator = AVAssetImageGenerator(asset: asset)
  imageGenerator.appliesPreferredTrackTransform = true
  imageGenerator.maximumSize = CGSize(width: maxSize * 2, height: maxSize * 2) // 2x for Retina

  let time = CMTimeMakeWithSeconds(0, preferredTimescale: 600)

  do {
    let (cgImage, _) = try await imageGenerator.image(at: time)
    let nsImage = NSImage(cgImage: cgImage, size: NSZeroSize)

    // Scale down if needed
    let scaledThumbnail = scaleImage(nsImage, maxSize: maxSize)
    return (scaledThumbnail, duration)
  } catch {
    print("Error generating video thumbnail: \(error)")
    return (nil, duration)
  }
}

/// Scale NSImage to fit within maxSize
private static func scaleImage(_ image: NSImage, maxSize: CGFloat) -> NSImage {
  let originalSize = image.size
  guard originalSize.width > 0, originalSize.height > 0 else { return image }

  let scale: CGFloat
  if originalSize.width > originalSize.height {
    scale = min(maxSize / originalSize.width, 1.0)
  } else {
    scale = min(maxSize / originalSize.height, 1.0)
  }

  if scale >= 1.0 { return image }

  let newSize = CGSize(
    width: originalSize.width * scale,
    height: originalSize.height * scale
  )

  let thumbnail = NSImage(size: newSize)
  thumbnail.lockFocus()
  NSGraphicsContext.current?.imageInterpolation = .high
  image.draw(
    in: NSRect(origin: .zero, size: newSize),
    from: NSRect(origin: .zero, size: originalSize),
    operation: .copy,
    fraction: 1.0
  )
  thumbnail.unlockFocus()

  return thumbnail
}
```

### Step 6: Add backward-compatible wrapper

Keep original signature working for existing callers:

```swift
/// Backward-compatible method for image-only thumbnail generation
static func generateImageThumbnail(from url: URL, maxSize: CGFloat = 200) async -> NSImage? {
  return await generateFromImage(url: url, maxSize: maxSize)
}
```

## Todo List

- [ ] Add `import AVFoundation`
- [ ] Add `videoExtensions` set and `isVideoFile` helper
- [ ] Update `generate` method signature to return tuple
- [ ] Rename existing implementation to `generateFromImage`
- [ ] Add `generateFromVideo` method
- [ ] Add `scaleImage` helper method
- [ ] Update callers in `QuickAccessManager` to handle new return type
- [ ] Test with .mov and .mp4 files
- [ ] Verify project compiles

## Success Criteria

- [ ] Video thumbnail generates from first frame
- [ ] Duration extracted correctly
- [ ] Image thumbnails still work
- [ ] Async operation doesn't block UI
- [ ] Graceful handling of invalid video files

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| AVAssetImageGenerator fails for some codecs | Low | Return nil, caller handles fallback |
| Duration extraction fails | Low | Return nil duration, UI handles gracefully |

## Security Considerations

- Only local file URLs processed
- No network requests
- No user input validation needed (internal API)

## Next Steps

After completing this phase:
1. Update `QuickAccessManager.addScreenshot` to handle new return type
2. Proceed to [Phase 03: Video Card UI](./phase-03-video-card-ui.md)
