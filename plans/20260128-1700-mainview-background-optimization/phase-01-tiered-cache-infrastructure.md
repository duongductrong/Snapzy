# Phase 1: Tiered Cache Infrastructure

## Context

- [SystemWallpaperManager.swift](/Users/duongductrong/Developer/ZapShot/ClaudeShot/Core/Services/SystemWallpaperManager.swift) - existing thumbnail cache at 128px
- [Research findings](/Users/duongductrong/Developer/ZapShot/plans/20260128-1634-video-wallpaper-implementation/research) - ImageIO preferred over sips

## Overview

Extend SystemWallpaperManager with preview-tier caching (2048px) using the same ImageIO downsampling pattern already proven for thumbnails.

## Key Insights

1. Existing `createDownsampledThumbnail()` uses ImageIO - reusable pattern
2. NSCache already configured with 50MB limit for thumbnails
3. Preview cache needs separate NSCache (larger images, different eviction)
4. 2048px = 4K retina quality, sufficient for main view display

## Requirements

- [ ] Add `previewCache: NSCache<NSURL, NSImage>` property
- [ ] Add `previewSize: CGFloat = 2048` constant
- [ ] Implement `loadPreviewImage(for:completion:)` method
- [ ] Implement `cachedPreviewImage(for:)` for sync access
- [ ] Configure preview cache limits (100MB, 20 items)

## Related Code Files

- `/ClaudeShot/Core/Services/SystemWallpaperManager.swift`

## Implementation Steps

### Step 1: Add preview cache properties (lines 21-24)

```swift
// MARK: - Preview Cache (Main View Display)

private let previewCache = NSCache<NSURL, NSImage>()
private let previewSize: CGFloat = 2048  // 4K retina quality
private var loadingPreviewURLs = Set<URL>()
```

### Step 2: Configure preview cache in init() (after line 51)

```swift
// Configure preview cache limits (larger than thumbnails)
previewCache.countLimit = 20  // Fewer items, larger size
previewCache.totalCostLimit = 100 * 1024 * 1024  // 100MB max
```

### Step 3: Add cachedPreviewImage method (after line 59)

```swift
/// Get cached preview image or nil if not yet loaded
func cachedPreviewImage(for url: URL) -> NSImage? {
  previewCache.object(forKey: url as NSURL)
}
```

### Step 4: Add loadPreviewImage method (after cachedPreviewImage)

```swift
/// Load and cache preview image with downsampling (async, non-blocking)
func loadPreviewImage(for url: URL, completion: @escaping (NSImage?) -> Void) {
  // Skip preset URLs
  guard url.scheme != "preset" else {
    completion(nil)
    return
  }

  // Check cache first
  if let cached = previewCache.object(forKey: url as NSURL) {
    completion(cached)
    return
  }

  // Prevent duplicate loads
  cacheQueue.sync {
    guard !loadingPreviewURLs.contains(url) else {
      completion(nil)
      return
    }
    loadingPreviewURLs.insert(url)
  }

  // Load and downsample on background thread
  DispatchQueue.global(qos: .userInitiated).async { [weak self] in
    guard let self = self else { return }

    let preview = self.createDownsampledImage(from: url, maxSize: self.previewSize)

    if let preview = preview {
      self.previewCache.setObject(preview, forKey: url as NSURL)
    }

    self.cacheQueue.sync {
      self.loadingPreviewURLs.remove(url)
    }

    DispatchQueue.main.async {
      completion(preview)
    }
  }
}
```

### Step 5: Refactor createDownsampledThumbnail to be reusable (replace lines 101-124)

```swift
/// Create downsampled image using ImageIO (memory efficient)
/// - Parameters:
///   - url: Source image URL
///   - maxSize: Maximum dimension in pixels (width or height)
/// - Returns: Downsampled NSImage or nil
private func createDownsampledImage(from url: URL, maxSize: CGFloat) -> NSImage? {
  let options: [CFString: Any] = [
    kCGImageSourceShouldCache: false
  ]

  guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
    return nil
  }

  let maxDimension = maxSize * 2  // Retina

  let downsampleOptions: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceShouldCacheImmediately: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: maxDimension
  ]

  guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions as CFDictionary) else {
    return nil
  }

  return NSImage(cgImage: cgImage, size: NSSize(width: maxSize, height: maxSize))
}

/// Create downsampled thumbnail (128px)
private func createDownsampledThumbnail(from url: URL) -> NSImage? {
  createDownsampledImage(from: url, maxSize: thumbnailSize)
}
```

## Success Criteria

- [ ] `loadPreviewImage()` returns 2048px downsampled image
- [ ] Preview cache evicts correctly at 100MB limit
- [ ] No memory spikes when loading multiple previews
- [ ] Existing thumbnail functionality unchanged

## Risk Assessment

- **Low**: Direct extension of proven thumbnail pattern
- **Mitigation**: Keep thumbnail and preview caches separate to avoid eviction conflicts
