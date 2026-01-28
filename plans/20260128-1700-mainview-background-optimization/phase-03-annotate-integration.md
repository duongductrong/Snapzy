# Phase 3: Annotate Integration

## Context

- [Phase 1](./phase-01-tiered-cache-infrastructure.md) - Preview cache infrastructure
- [AnnotateState.swift](/Users/duongductrong/Developer/ZapShot/ClaudeShot/Features/Annotate/State/AnnotateState.swift) - already has `cachedBackgroundImage` pattern
- Current issue: `loadBackgroundImage()` uses `NSImage(contentsOf:)` - loads full resolution

## Overview

Update AnnotateState to use SystemWallpaperManager's preview cache instead of loading full-resolution images directly.

## Key Insights

1. AnnotateState already has correct architecture: `cachedBackgroundImage` + `loadBackgroundImage()`
2. Problem is in implementation: line 71 uses `NSImage(contentsOf: url)` - full-res
3. Simple fix: replace with SystemWallpaperManager.loadPreviewImage()
4. Maintains existing "effective value" pattern for sliders

## Requirements

- [ ] Update `loadBackgroundImage(from:)` to use SystemWallpaperManager.loadPreviewImage
- [ ] Ensure async loading works correctly with existing didSet trigger
- [ ] Verify canvas rendering uses cachedBackgroundImage (should already work)

## Related Code Files

- `/ClaudeShot/Features/Annotate/State/AnnotateState.swift`
- `/ClaudeShot/Features/Annotate/Views/AnnotateCanvasView.swift` (or equivalent)

## Implementation Steps

### Step 1: Update loadBackgroundImage method (replace lines 65-72)

```swift
private func loadBackgroundImage(from url: URL) {
  // Skip preset URLs (handled via gradient)
  guard url.scheme != "preset" else {
    cachedBackgroundImage = nil
    return
  }

  // Use preview cache from SystemWallpaperManager (2048px, not full-res)
  SystemWallpaperManager.shared.loadPreviewImage(for: url) { [weak self] image in
    Task { @MainActor in
      self?.cachedBackgroundImage = image
    }
  }
}
```

### Step 2: Verify backgroundStyle didSet (lines 50-60) - no changes needed

The existing didSet already triggers `loadBackgroundImage()` correctly:

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

### Step 3: Verify canvas uses cachedBackgroundImage

Check that the canvas view uses `state.cachedBackgroundImage` for rendering, not loading from URL. This should already be the case based on existing architecture.

### Step 4: Ensure .drawingGroup() is applied (if not present)

Verify the canvas background layer uses Metal rendering:

```swift
// In canvas view
backgroundLayer
  .drawingGroup()
```

## Success Criteria

- [ ] Annotate canvas loads 2048px preview instead of full-res
- [ ] Memory usage drops ~90% for wallpaper display
- [ ] Existing slider interactions remain smooth (effective value pattern)
- [ ] No visible quality degradation at normal canvas sizes

## Risk Assessment

- **Very Low**: Minimal code change, existing architecture supports this
- **Note**: Async loading means brief nil state possible - existing code should handle gracefully
