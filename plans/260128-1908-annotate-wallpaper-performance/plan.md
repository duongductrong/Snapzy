# Annotate Wallpaper Rendering Performance Optimization

## Overview

Reduce wallpaper render size and quality in Annotate feature to eliminate lag during canvas interactions. Add manual configuration controls for performance testing.

## Problem Summary

| Issue | Impact | Root Cause |
|-------|--------|------------|
| Lag on wallpaper selection | High | Full 6K+ HEIC loaded via `NSImage(contentsOf:)` |
| Slow slider interactions | High | Real-time blur on full-res image |
| Memory bloat | Medium | 50MB+ per wallpaper in memory |

## Solution Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Tiered Image Cache                     │
├─────────────┬─────────────┬─────────────────────────────┤
│ Thumbnail   │ Preview     │ Full Resolution             │
│ 128px       │ 2048px      │ Original                    │
│ Sidebar     │ Canvas      │ Export only                 │
└─────────────┴─────────────┴─────────────────────────────┘
```

## Phases

| Phase | Description | Status |
|-------|-------------|--------|
| [Phase 1](./phase-01-preview-cache-integration.md) | Integrate preview cache into AnnotateState | ✅ Complete |
| [Phase 2](./phase-02-precomputed-blur.md) | Pre-compute blurred wallpaper variant | ✅ Complete |
| [Phase 3](./phase-03-manual-testing-controls.md) | Add configurable quality settings for testing | ✅ Complete |

## Dependencies

- Requires `SystemWallpaperManager.loadPreviewImage()` from [mainview-background-optimization plan](../20260128-1700-mainview-background-optimization/plan.md)
- If Phase 1 of that plan not implemented, Phase 1 here includes the infrastructure

## Success Metrics

- Memory: ~90% reduction (4MB vs 50MB per wallpaper)
- Slider lag: Eliminated (preview + cached blur)
- Export quality: Unchanged (full-res on-demand)

## Manual Testing Controls (Phase 3)

```swift
// Debug settings for performance testing
struct WallpaperQualityConfig {
  static var maxResolution: CGFloat = 2048  // 1024, 2048, 4096
  static var blurRadius: CGFloat = 20       // 10, 20, 30
  static var usePrecomputedBlur: Bool = true
  static var showDebugOverlay: Bool = false // Shows actual render dimensions
}
```

## Related Files

- [AnnotateState.swift](../../ClaudeShot/Features/Annotate/State/AnnotateState.swift) - Line 65-71 needs update
- [AnnotateCanvasView.swift](../../ClaudeShot/Features/Annotate/Views/AnnotateCanvasView.swift) - Line 212-234 background rendering
- [SystemWallpaperManager.swift](../../ClaudeShot/Core/Services/SystemWallpaperManager.swift) - Cache infrastructure
