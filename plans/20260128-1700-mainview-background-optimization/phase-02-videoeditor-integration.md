# Phase 2: VideoEditor Integration

## Context

- [Phase 1](./phase-01-tiered-cache-infrastructure.md) - Preview cache infrastructure
- [VideoEditorState.swift](/Users/duongductrong/Developer/ZapShot/ClaudeShot/Features/VideoEditor/State/VideoEditorState.swift) - stores `backgroundStyle: BackgroundStyle`
- Currently loads full-res wallpaper directly from URL in views

## Overview

Integrate preview cache into VideoEditor by adding cached background image pattern (similar to AnnotateState) and using SystemWallpaperManager's new preview loading.

## Key Insights

1. VideoEditorState has `backgroundStyle` but no cached image property
2. AnnotateState pattern: `cachedBackgroundImage` + `loadBackgroundImage(from:)`
3. Main view renders background in video player section
4. Need "effective value" pattern for smooth slider interactions

## Requirements

- [ ] Add `cachedBackgroundImage: NSImage?` to VideoEditorState
- [ ] Add `loadBackgroundImage(from:)` using SystemWallpaperManager.loadPreviewImage
- [ ] Update backgroundStyle didSet to trigger preview loading
- [ ] Update main view to use cached image instead of URL

## Related Code Files

- `/ClaudeShot/Features/VideoEditor/State/VideoEditorState.swift`
- `/ClaudeShot/Features/VideoEditor/Views/VideoPlayerSection.swift` (or equivalent main view)

## Implementation Steps

### Step 1: Add cached background property to VideoEditorState (after line 84)

```swift
// MARK: - Cached Background (Performance Optimization)

/// Cached background image for main view display (preview quality, not full-res)
private(set) var cachedBackgroundImage: NSImage?

/// Load preview-quality background image
private func loadBackgroundImage(from url: URL) {
  // Skip preset URLs (handled via gradient)
  guard url.scheme != "preset" else {
    cachedBackgroundImage = nil
    return
  }

  // Use preview cache from SystemWallpaperManager
  SystemWallpaperManager.shared.loadPreviewImage(for: url) { [weak self] image in
    Task { @MainActor in
      self?.cachedBackgroundImage = image
      self?.objectWillChange.send()
    }
  }
}
```

### Step 2: Update backgroundStyle to trigger loading (modify line 78)

```swift
@Published var backgroundStyle: BackgroundStyle = .none {
  didSet {
    switch backgroundStyle {
    case .wallpaper(let url), .blurred(let url):
      loadBackgroundImage(from: url)
    default:
      cachedBackgroundImage = nil
    }
  }
}
```

### Step 3: Find and update main view background rendering

Locate the view that renders wallpaper backgrounds (likely uses `backgroundStyle` with URL). Update to use `cachedBackgroundImage` when available:

```swift
// Before (loading full-res from URL):
case .wallpaper(let url):
  AsyncImage(url: url) { image in
    image.resizable().aspectRatio(contentMode: .fill)
  }

// After (using cached preview):
case .wallpaper:
  if let cached = editorState.cachedBackgroundImage {
    Image(nsImage: cached)
      .resizable()
      .aspectRatio(contentMode: .fill)
  } else {
    // Placeholder while loading
    Color.gray.opacity(0.3)
  }
```

### Step 4: Add drawingGroup() for Metal rendering (if not present)

Wrap background container with `.drawingGroup()` for GPU-accelerated compositing:

```swift
ZStack {
  // Background layer
  backgroundView
  // Video layer
  videoPlayerView
}
.drawingGroup()  // Metal rendering
```

## Success Criteria

- [ ] VideoEditor main view loads 2048px preview instead of full-res
- [ ] Memory usage drops ~90% for wallpaper display
- [ ] Background changes feel responsive (async loading)
- [ ] No visible quality degradation at normal view sizes

## Risk Assessment

- **Low**: Pattern proven in AnnotateState
- **Medium**: Brief placeholder flash on wallpaper change - acceptable UX trade-off
- **Mitigation**: Could add fade transition on image swap
