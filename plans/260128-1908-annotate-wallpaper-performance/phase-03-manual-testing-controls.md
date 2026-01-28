# Phase 3: Manual Testing Controls

## Context

- Parent: [plan.md](./plan.md)
- Depends on: [Phase 1](./phase-01-preview-cache-integration.md), [Phase 2](./phase-02-precomputed-blur.md)
- Date: 2026-01-28
- Priority: Medium
- Implementation Status: Pending
- Review Status: Pending

## Overview

Add configurable quality settings for manual performance testing. Allows developers to adjust resolution, blur radius, and toggle optimizations to find optimal balance.

## Key Insights

1. Different displays may need different preview sizes (1K vs 2K vs 4K)
2. Blur radius affects both quality and performance
3. Debug overlay helps verify actual render dimensions
4. Settings should be compile-time constants (not user-facing)

## Requirements

- [ ] Create `WallpaperQualityConfig` with adjustable parameters
- [ ] Wire config into SystemWallpaperManager and AnnotateState
- [ ] Add optional debug overlay showing render stats
- [ ] Document how to adjust values for testing

## Architecture

```swift
// ClaudeShot/Core/Config/WallpaperQualityConfig.swift

struct WallpaperQualityConfig {
  // MARK: - Resolution Settings

  /// Maximum preview dimension in pixels
  /// Options: 1024 (low), 2048 (default), 4096 (high)
  static var maxResolution: CGFloat = 2048

  // MARK: - Blur Settings

  /// Gaussian blur radius for .blurred style
  /// Options: 10 (subtle), 20 (default), 30 (heavy)
  static var blurRadius: CGFloat = 20

  /// Use pre-computed blur (true) or real-time (false)
  static var usePrecomputedBlur: Bool = true

  // MARK: - Debug Settings

  /// Show debug overlay with render dimensions
  static var showDebugOverlay: Bool = false

  /// Log performance metrics to console
  static var logPerformanceMetrics: Bool = false
}
```

## Related Code Files

| File | Lines | Change |
|------|-------|--------|
| NEW: WallpaperQualityConfig.swift | - | Create config struct |
| SystemWallpaperManager.swift | previewSize | Use config value |
| AnnotateState.swift | blur radius | Use config value |
| AnnotateCanvasView.swift | background layer | Add debug overlay |

## Implementation Steps

### Step 1: Create config file

Create `/ClaudeShot/Core/Config/WallpaperQualityConfig.swift`:

```swift
import Foundation

/// Configuration for wallpaper rendering quality and performance testing
/// Adjust these values to test different performance/quality tradeoffs
struct WallpaperQualityConfig {

  // MARK: - Resolution

  /// Max preview dimension (pixels). Affects memory & render speed.
  /// - 1024: Low memory (~1MB), may show pixelation on 4K displays
  /// - 2048: Balanced (~4MB), good for most displays (DEFAULT)
  /// - 4096: High quality (~16MB), for 5K+ displays
  static var maxResolution: CGFloat = 2048

  // MARK: - Blur

  /// Blur radius for .blurred wallpaper style
  static var blurRadius: CGFloat = 20

  /// Pre-compute blur on load vs real-time per-frame
  static var usePrecomputedBlur: Bool = true

  // MARK: - Debug

  /// Overlay showing actual render dimensions on canvas
  static var showDebugOverlay: Bool = false

  /// Console logging of load times and memory usage
  static var logPerformanceMetrics: Bool = false
}
```

### Step 2: Wire config into SystemWallpaperManager

```swift
// In loadPreviewImage()
let preview = self.createDownsampledImage(
  from: url,
  maxSize: WallpaperQualityConfig.maxResolution
)

// Optional logging
if WallpaperQualityConfig.logPerformanceMetrics {
  let elapsed = CFAbsoluteTimeGetCurrent() - startTime
  print("[Wallpaper] Loaded preview at \(WallpaperQualityConfig.maxResolution)px in \(elapsed * 1000)ms")
}
```

### Step 3: Wire config into AnnotateState blur

```swift
// In loadBackgroundImage()
if case .blurred = self?.backgroundStyle, WallpaperQualityConfig.usePrecomputedBlur {
  self?.cachedBlurredImage = self?.applyGaussianBlur(
    to: image,
    radius: WallpaperQualityConfig.blurRadius
  )
}
```

### Step 4: Add debug overlay to canvas

```swift
// In AnnotateCanvasView backgroundLayer
.overlay(alignment: .topLeading) {
  if WallpaperQualityConfig.showDebugOverlay,
     let image = state.cachedBackgroundImage {
    debugOverlay(for: image, displaySize: CGSize(width: width, height: height))
  }
}

private func debugOverlay(for image: NSImage, displaySize: CGSize) -> some View {
  VStack(alignment: .leading, spacing: 2) {
    Text("Source: \(Int(image.size.width))×\(Int(image.size.height))")
    Text("Display: \(Int(displaySize.width))×\(Int(displaySize.height))")
    Text("Config: \(Int(WallpaperQualityConfig.maxResolution))px max")
  }
  .font(.system(size: 10, design: .monospaced))
  .foregroundColor(.white)
  .padding(4)
  .background(Color.black.opacity(0.7))
  .cornerRadius(4)
  .padding(8)
}
```

## Manual Testing Guide

### How to Test Different Resolutions

1. Open `WallpaperQualityConfig.swift`
2. Change `maxResolution` to test value:
   ```swift
   static var maxResolution: CGFloat = 1024  // Low quality test
   ```
3. Build and run (⌘R)
4. Select a wallpaper, test slider interactions
5. Note performance and visual quality

### Recommended Test Matrix

| Setting | Value | Expected Result |
|---------|-------|-----------------|
| maxResolution | 1024 | Fast, may pixelate on retina |
| maxResolution | 2048 | Balanced (recommended) |
| maxResolution | 4096 | High quality, more memory |
| blurRadius | 10 | Subtle blur, fast |
| blurRadius | 30 | Heavy blur, slower compute |
| usePrecomputedBlur | false | Test real-time blur lag |
| showDebugOverlay | true | Verify actual dimensions |

### Performance Metrics to Check

1. **Wallpaper load time**: Should be <100ms for 2048px
2. **Slider responsiveness**: 60fps during drag
3. **Memory usage**: ~4MB per wallpaper at 2048px
4. **Blur compute time**: ~50ms one-time at 2048px

## Todo List

- [ ] Create WallpaperQualityConfig.swift
- [ ] Update SystemWallpaperManager to use config
- [ ] Update AnnotateState blur to use config
- [ ] Add debug overlay to AnnotateCanvasView
- [ ] Test all config combinations
- [ ] Document findings in test report

## Success Criteria

- [ ] All config values adjustable without code changes beyond config file
- [ ] Debug overlay accurately shows render dimensions
- [ ] Performance logging provides actionable metrics
- [ ] Testing guide covers all scenarios

## Risk Assessment

- **Very Low**: Debug-only code, easily removable
- **Note**: Ensure debug overlay doesn't affect release builds (use #if DEBUG)

## Security Considerations

- Config is compile-time only, not user-modifiable
- Debug overlay shows dimensions only, no sensitive data
