# Phase 4: Export Full Resolution Verification

## Context

- [ZoomCompositor.swift](/Users/duongductrong/Developer/ZapShot/ClaudeShot/Features/VideoEditor/Export/ZoomCompositor.swift) - video export with backgrounds
- Export MUST use full resolution, not preview cache
- Current implementation already loads from URL directly (lines 431-443)

## Overview

Verify that export pipeline uses full-resolution wallpapers from URL, not the preview cache. This phase is primarily verification with minimal code changes.

## Key Insights

1. ZoomCompositor.createBackgroundImage() loads via `CIImage(contentsOf: url)` - line 432
2. This is correct behavior - export needs full quality
3. Preview cache is only for display, never for export
4. No changes needed to ZoomCompositor if it loads from URL

## Requirements

- [ ] Verify ZoomCompositor loads wallpapers from URL (not cached)
- [ ] Verify export output quality matches original wallpaper resolution
- [ ] Add documentation comment clarifying full-res requirement
- [ ] Optional: Add assertion/logging to confirm full-res loading

## Related Code Files

- `/ClaudeShot/Features/VideoEditor/Export/ZoomCompositor.swift`
- `/ClaudeShot/Features/Annotate/Export/AnnotateExporter.swift` (if exists)

## Implementation Steps

### Step 1: Verify ZoomCompositor implementation (lines 431-443)

Current code already loads from URL:

```swift
case .wallpaper(let url):
  guard let image = CIImage(contentsOf: url) else {
    return CIImage(color: .black).cropped(to: rect)
  }
  return scaleToFill(image: image, targetSize: size)

case .blurred(let url):
  guard let image = CIImage(contentsOf: url) else {
    return CIImage(color: .black).cropped(to: rect)
  }
  let scaled = scaleToFill(image: image, targetSize: size)
  return scaled.applyingGaussianBlur(sigma: 20).cropped(to: rect)
```

This is correct - `CIImage(contentsOf:)` loads full resolution.

### Step 2: Add documentation comment (before createBackgroundImage method, line 404)

```swift
/// Create background image for video composition
/// NOTE: Uses full-resolution image from URL for export quality.
/// Display preview uses SystemWallpaperManager.loadPreviewImage() (2048px).
private func createBackgroundImage(style: BackgroundStyle, size: CGSize) -> CIImage {
```

### Step 3: Verify Annotate export (if applicable)

Check if AnnotateState has export functionality that renders backgrounds. Ensure it loads from URL for export, not `cachedBackgroundImage`.

### Step 4: Add debug logging (optional, for verification)

```swift
case .wallpaper(let url):
  print("[Export] Loading full-res wallpaper: \(url.lastPathComponent)")
  guard let image = CIImage(contentsOf: url) else {
    return CIImage(color: .black).cropped(to: rect)
  }
  print("[Export] Wallpaper dimensions: \(image.extent.size)")
  return scaleToFill(image: image, targetSize: size)
```

## Success Criteria

- [ ] Exported video uses full-resolution wallpaper (not 2048px preview)
- [ ] Export quality unchanged from before optimization
- [ ] No regression in export functionality
- [ ] Documentation clarifies display vs export resolution strategy

## Risk Assessment

- **Very Low**: Verification phase, minimal code changes
- **Note**: If export was accidentally using cached image, fix immediately

## Testing Checklist

1. Export video with system wallpaper background
2. Compare exported frame to original wallpaper at 100% zoom
3. Verify no quality loss or artifacts from downsampling
4. Test with 6K HEIC wallpaper to confirm full resolution used
