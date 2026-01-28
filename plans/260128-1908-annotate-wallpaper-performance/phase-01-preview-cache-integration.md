# Phase 1: Preview Cache Integration

## Context

- Parent: [plan.md](./plan.md)
- Depends on: [SystemWallpaperManager preview cache](../20260128-1700-mainview-background-optimization/phase-01-tiered-cache-infrastructure.md)
- Date: 2026-01-28
- Priority: High
- Implementation Status: Pending
- Review Status: Pending

## Overview

Replace full-resolution wallpaper loading in AnnotateState with downsampled preview cache. Uses ImageIO for memory-efficient 2048px preview generation.

## Key Insights

1. Current `loadBackgroundImage()` at line 71 uses `NSImage(contentsOf: url)` - loads full 6K+ HEIC
2. SystemWallpaperManager already has `createDownsampledThumbnail()` pattern - reuse for preview
3. AnnotateState architecture is correct (cached property + didSet trigger) - only implementation needs change
4. Export path in AnnotateExporter.swift loads from URL directly - no change needed

## Requirements

- [ ] Add `loadPreviewImage()` to SystemWallpaperManager (if not already present)
- [ ] Update `AnnotateState.loadBackgroundImage()` to use preview cache
- [ ] Verify canvas uses `cachedBackgroundImage` (already does at lines 212, 225)
- [ ] Test slider interactions remain smooth

## Architecture

```
Wallpaper Selection Flow:
┌──────────────┐    ┌───────────────────────┐    ┌────────────────┐
│ backgroundStyle │→│ loadBackgroundImage() │→│ cachedBackground │
│ didSet       │    │ uses preview cache    │    │ Image (2048px) │
└──────────────┘    └───────────────────────┘    └────────────────┘
                              ↓
                    ┌───────────────────────┐
                    │ SystemWallpaperManager │
                    │ loadPreviewImage()    │
                    │ - ImageIO downsample  │
                    │ - NSCache storage     │
                    └───────────────────────┘
```

## Related Code Files

| File | Lines | Change |
|------|-------|--------|
| SystemWallpaperManager.swift | New | Add `loadPreviewImage()` method |
| AnnotateState.swift | 65-72 | Update `loadBackgroundImage()` |
| AnnotateCanvasView.swift | 212, 225 | No change (already uses cache) |

## Implementation Steps

### Step 1: Add preview cache to SystemWallpaperManager

```swift
// Add to SystemWallpaperManager.swift

private let previewCache = NSCache<NSURL, NSImage>()
private let previewSize: CGFloat = 2048  // Retina 1024pt

/// Load preview-sized image for canvas display (2048px max dimension)
func loadPreviewImage(for url: URL, completion: @escaping (NSImage?) -> Void) {
  // Check cache first
  if let cached = previewCache.object(forKey: url as NSURL) {
    completion(cached)
    return
  }

  DispatchQueue.global(qos: .userInitiated).async { [weak self] in
    guard let self = self else { return }

    let preview = self.createDownsampledImage(from: url, maxSize: self.previewSize)

    if let preview = preview {
      self.previewCache.setObject(preview, forKey: url as NSURL)
    }

    DispatchQueue.main.async {
      completion(preview)
    }
  }
}

/// ImageIO-based downsampling (memory efficient)
private func createDownsampledImage(from url: URL, maxSize: CGFloat) -> NSImage? {
  let options: [CFString: Any] = [kCGImageSourceShouldCache: false]

  guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
    return nil
  }

  let downsampleOptions: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceShouldCacheImmediately: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: maxSize
  ]

  guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
    return nil
  }

  return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}
```

### Step 2: Update AnnotateState.loadBackgroundImage()

Replace lines 65-72 in AnnotateState.swift:

```swift
private func loadBackgroundImage(from url: URL) {
  // Skip preset URLs (handled via gradient)
  guard url.scheme != "preset" else {
    cachedBackgroundImage = nil
    return
  }

  // Use preview cache (2048px) instead of full resolution
  SystemWallpaperManager.shared.loadPreviewImage(for: url) { [weak self] image in
    Task { @MainActor in
      self?.cachedBackgroundImage = image
    }
  }
}
```

### Step 3: Verify canvas rendering (no changes needed)

AnnotateCanvasView.swift already uses `state.cachedBackgroundImage` at:
- Line 212: `.wallpaper` case
- Line 225: `.blurred` case

## Todo List

- [ ] Add `previewCache` NSCache to SystemWallpaperManager
- [ ] Add `loadPreviewImage(for:completion:)` method
- [ ] Add `createDownsampledImage(from:maxSize:)` helper
- [ ] Update AnnotateState.loadBackgroundImage() to use preview cache
- [ ] Test wallpaper selection performance
- [ ] Test slider interaction smoothness
- [ ] Verify no visual quality degradation

## Success Criteria

- [ ] Wallpaper loads at 2048px instead of 6K+
- [ ] Memory per wallpaper drops from ~50MB to ~4MB
- [ ] Slider interactions remain lag-free
- [ ] Canvas visually identical at normal zoom levels

## Risk Assessment

- **Low**: ImageIO is battle-tested, same pattern as thumbnail cache
- **Low**: Async loading may show brief nil state - handled by existing conditional rendering

## Security Considerations

- File access remains sandboxed via existing URL patterns
- No user input processed - URLs from trusted system paths

## Next Steps

After completion → [Phase 2: Precomputed Blur](./phase-02-precomputed-blur.md)
