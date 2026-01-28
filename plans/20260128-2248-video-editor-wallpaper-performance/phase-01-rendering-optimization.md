# Phase 1: Rendering Optimization

**Parent:** [plan.md](./plan.md)
**Dependencies:** None

---

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-28 |
| Description | Eliminate disk I/O and add Metal rasterization to achieve 60fps |
| Priority | P0 - Critical |
| Status | Pending |

---

## Key Insights

1. `ZoomPreviewOverlay.backgroundView` loads `NSImage(contentsOf: url)` every frame
2. Missing `.drawingGroup()` forces SwiftUI to recompute view hierarchy per frame
3. `.blur(radius: 20)` applied in real-time without caching
4. Annotate achieves 60fps by caching images and using Metal rasterization

---

## Requirements

1. Cache wallpaper image in `VideoEditorState` (load once, render many)
2. Cache blurred variant in `VideoEditorState` (compute once)
3. Add `.drawingGroup()` to background layer for Metal rasterization
4. Remove all disk I/O from render path

---

## Architecture

```
VideoEditorState
├── backgroundStyle: BackgroundStyle (existing)
├── cachedBackgroundImage: NSImage? (NEW)
├── cachedBlurredImage: NSImage? (NEW)
└── loadBackgroundImage(from: URL) (NEW)

ZoomPreviewOverlay.backgroundView
├── Use state.cachedBackgroundImage (instead of NSImage(contentsOf:))
├── Use state.cachedBlurredImage (instead of real-time blur)
└── Wrap in .drawingGroup() (NEW)
```

---

## Related Code Files

| File | Purpose |
|------|---------|
| `/Users/duongductrong/Developer/ZapShot/ClaudeShot/Features/VideoEditor/State/VideoEditorState.swift` | Add cached image properties and loading logic |
| `/Users/duongductrong/Developer/ZapShot/ClaudeShot/Features/VideoEditor/Views/Zoom/ZoomPreviewOverlay.swift` | Use cached images, add .drawingGroup() |
| `/Users/duongductrong/Developer/ZapShot/ClaudeShot/Features/Annotate/State/AnnotateState.swift` | Reference implementation |

---

## Implementation Steps

### Step 1: Add Cached Image Properties to VideoEditorState

```swift
// VideoEditorState.swift - Add after line 84

/// Cached background image for performance (avoids disk reads during render)
@Published private(set) var cachedBackgroundImage: NSImage?

/// Cached pre-computed blurred image (avoids real-time blur)
@Published private(set) var cachedBlurredImage: NSImage?

/// Track URL being loaded to prevent race conditions
private var loadingBackgroundURL: URL?
```

### Step 2: Add didSet Observer to backgroundStyle

```swift
// VideoEditorState.swift - Modify backgroundStyle property

@Published var backgroundStyle: BackgroundStyle = .none {
  didSet {
    switch backgroundStyle {
    case .wallpaper(let url), .blurred(let url):
      loadBackgroundImage(from: url)
    default:
      cachedBackgroundImage = nil
      cachedBlurredImage = nil
      loadingBackgroundURL = nil
    }
  }
}
```

### Step 3: Add Image Loading Method

```swift
// VideoEditorState.swift - Add new method

private func loadBackgroundImage(from url: URL) {
  loadingBackgroundURL = url

  SystemWallpaperManager.shared.loadPreviewImage(for: url) { [weak self] image in
    Task { @MainActor in
      guard self?.loadingBackgroundURL == url else { return }

      self?.cachedBackgroundImage = image
      self?.loadingBackgroundURL = nil

      // Pre-compute blur if needed
      if case .blurred = self?.backgroundStyle {
        self?.cachedBlurredImage = self?.applyGaussianBlur(
          to: image,
          radius: WallpaperQualityConfig.blurRadius
        )
      } else {
        self?.cachedBlurredImage = nil
      }
    }
  }
}

private func applyGaussianBlur(to image: NSImage?, radius: CGFloat) -> NSImage? {
  guard let image = image,
        let tiffData = image.tiffRepresentation,
        let ciImage = CIImage(data: tiffData) else { return nil }

  let filter = CIFilter(name: "CIGaussianBlur")
  filter?.setValue(ciImage, forKey: kCIInputImageKey)
  filter?.setValue(radius, forKey: kCIInputRadiusKey)

  guard let output = filter?.outputImage else { return nil }
  let croppedOutput = output.cropped(to: ciImage.extent)

  let rep = NSCIImageRep(ciImage: croppedOutput)
  let blurred = NSImage(size: rep.size)
  blurred.addRepresentation(rep)
  return blurred
}
```

### Step 4: Update ZoomPreviewOverlay.backgroundView

```swift
// ZoomPreviewOverlay.swift - Replace backgroundView computed property

@ViewBuilder
private var backgroundView: some View {
  Group {
    switch state.backgroundStyle {
    case .none:
      Color.clear
    case .gradient(let preset):
      LinearGradient(
        colors: preset.colors,
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    case .solidColor(let color):
      color
    case .wallpaper:
      if let nsImage = state.cachedBackgroundImage {
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Color.gray // Placeholder while loading
      }
    case .blurred:
      if let nsImage = state.cachedBlurredImage {
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else if let nsImage = state.cachedBackgroundImage {
        // Fallback to non-blurred while computing
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Color.gray
      }
    }
  }
  .drawingGroup() // Metal rasterization for 60fps
}
```

---

## Todo List

- [ ] Add `cachedBackgroundImage` property to VideoEditorState
- [ ] Add `cachedBlurredImage` property to VideoEditorState
- [ ] Add `loadingBackgroundURL` tracking property
- [ ] Add `didSet` observer to `backgroundStyle`
- [ ] Implement `loadBackgroundImage(from:)` method
- [ ] Implement `applyGaussianBlur(to:radius:)` method
- [ ] Update `backgroundView` in ZoomPreviewOverlay to use cached images
- [ ] Add `.drawingGroup()` to background layer
- [ ] Test wallpaper selection triggers proper caching
- [ ] Test blurred wallpaper pre-computes blur

---

## Success Criteria

1. No `NSImage(contentsOf:)` calls during render cycle
2. No `.blur(radius:)` modifier during render cycle
3. `.drawingGroup()` applied to background layer
4. Preview renders smoothly when switching wallpapers
5. FPS >= 60 measured in Instruments

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Race condition during rapid wallpaper switching | Medium | Low | `loadingBackgroundURL` guard prevents stale updates |
| Memory pressure from cached images | Low | Medium | Use 2048px preview resolution via WallpaperQualityConfig |
| Initial load shows placeholder | High | Low | Acceptable UX tradeoff for smooth rendering |

---

## Security Considerations

- File URL access already sandboxed by macOS
- No user input processed in image loading
- No network requests (local wallpapers only)

---

## Next Steps

After completing Phase 1:
1. Measure FPS improvement with Instruments
2. If < 60fps, proceed to Phase 2 for additional optimizations
3. Document baseline vs improved metrics
