# Phase 2: Precomputed Blur

## Context

- Parent: [plan.md](./plan.md)
- Depends on: [Phase 1](./phase-01-preview-cache-integration.md)
- Date: 2026-01-28
- Priority: High
- Implementation Status: Pending
- Review Status: Pending

## Overview

Pre-compute blurred wallpaper variant when `.blurred` style is selected instead of applying real-time SwiftUI `.blur(radius: 20)` on every frame. This eliminates the most expensive rendering operation.

## Key Insights

1. Current code at line 231 applies `.blur(radius: 20)` on every render cycle
2. Blur is static (doesn't animate) - perfect candidate for pre-computation
3. CIFilter GaussianBlur on 2048px image is fast (~50ms one-time)
4. Cache blurred variant alongside normal preview

## Requirements

- [ ] Create `cachedBlurredImage` property in AnnotateState
- [ ] Pre-compute blur when `.blurred` style selected
- [ ] Use cached blur in canvas rendering
- [ ] Remove real-time `.blur()` modifier

## Architecture

```
Blurred Wallpaper Flow:
┌────────────────────┐
│ .blurred(url)      │
│ backgroundStyle    │
└─────────┬──────────┘
          ↓
┌─────────────────────────────────────┐
│ loadBackgroundImage()               │
│ 1. Load preview (2048px)            │
│ 2. Apply CIGaussianBlur             │
│ 3. Cache both normal + blurred      │
└─────────────────────────────────────┘
          ↓
┌─────────────────────────────────────┐
│ Canvas renders cachedBlurredImage   │
│ (no real-time blur processing)      │
└─────────────────────────────────────┘
```

## Related Code Files

| File | Lines | Change |
|------|-------|--------|
| AnnotateState.swift | 63 | Add `cachedBlurredImage` property |
| AnnotateState.swift | 65-72 | Pre-compute blur on load |
| AnnotateCanvasView.swift | 222-234 | Use cached blur, remove `.blur()` |

## Implementation Steps

### Step 1: Add blurred image cache to AnnotateState

```swift
// Add after line 63
private(set) var cachedBlurredImage: NSImage?
```

### Step 2: Update loadBackgroundImage to pre-compute blur

```swift
private func loadBackgroundImage(from url: URL) {
  guard url.scheme != "preset" else {
    cachedBackgroundImage = nil
    cachedBlurredImage = nil
    return
  }

  SystemWallpaperManager.shared.loadPreviewImage(for: url) { [weak self] image in
    Task { @MainActor in
      self?.cachedBackgroundImage = image

      // Pre-compute blurred variant if needed
      if case .blurred = self?.backgroundStyle {
        self?.cachedBlurredImage = self?.applyGaussianBlur(to: image, radius: 20)
      } else {
        self?.cachedBlurredImage = nil
      }
    }
  }
}

/// Apply CIGaussianBlur to NSImage (one-time computation)
private func applyGaussianBlur(to image: NSImage?, radius: CGFloat) -> NSImage? {
  guard let image = image,
        let tiffData = image.tiffRepresentation,
        let ciImage = CIImage(data: tiffData) else { return nil }

  let filter = CIFilter(name: "CIGaussianBlur")
  filter?.setValue(ciImage, forKey: kCIInputImageKey)
  filter?.setValue(radius, forKey: kCIInputRadiusKey)

  guard let output = filter?.outputImage else { return nil }

  let rep = NSCIImageRep(ciImage: output)
  let blurred = NSImage(size: rep.size)
  blurred.addRepresentation(rep)
  return blurred
}
```

### Step 3: Update canvas to use cached blur

Replace lines 222-234 in AnnotateCanvasView.swift:

```swift
case .blurred(let url):
  if url.scheme == "preset" {
    EmptyView()
  } else if let nsImage = state.cachedBlurredImage {
    // Use PRE-COMPUTED blur (no real-time processing)
    Image(nsImage: nsImage)
      .resizable()
      .aspectRatio(contentMode: .fill)
      .frame(width: width, height: height)
      .clipped()
      .cornerRadius(currentCornerRadius)
  } else if let nsImage = state.cachedBackgroundImage {
    // Fallback: show non-blurred while computing
    Image(nsImage: nsImage)
      .resizable()
      .aspectRatio(contentMode: .fill)
      .frame(width: width, height: height)
      .clipped()
      .cornerRadius(currentCornerRadius)
  }
```

## Todo List

- [ ] Add `cachedBlurredImage` property to AnnotateState
- [ ] Add `applyGaussianBlur()` helper method
- [ ] Update `loadBackgroundImage()` to pre-compute blur
- [ ] Update canvas `.blurred` case to use cached image
- [ ] Remove real-time `.blur()` modifier
- [ ] Test blur visual quality matches original
- [ ] Test slider performance with blurred wallpaper

## Success Criteria

- [ ] No per-frame blur computation
- [ ] Blur applied once on wallpaper selection (~50ms)
- [ ] Slider interactions completely smooth
- [ ] Visual blur quality identical to real-time

## Risk Assessment

- **Low**: CIGaussianBlur is GPU-accelerated, well-tested
- **Medium**: CIFilter output extent may need cropping for edge cases

## Next Steps

After completion → [Phase 3: Manual Testing Controls](./phase-03-manual-testing-controls.md)
