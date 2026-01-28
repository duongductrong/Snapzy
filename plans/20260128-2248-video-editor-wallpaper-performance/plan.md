# VideoEditor Wallpaper Performance Improvement Plan

**Created:** 2026-01-28
**Target:** >= 60fps wallpaper rendering in VideoEditor preview
**Status:** Planning

---

## Overview

VideoEditor wallpaper rendering suffers from 3 critical issues causing frame drops:
1. Disk I/O during render (NSImage loaded every frame)
2. No `.drawingGroup()` rasterization (SwiftUI recomputes hierarchy per frame)
3. Real-time blur computation (expensive filter per frame)

Annotate feature solved these via cached images, pre-computed blur, and Metal rasterization.

---

## Performance Target

| Metric | Current | Target |
|--------|---------|--------|
| Preview FPS | ~20-30fps | >= 60fps |
| Slider responsiveness | Laggy | Smooth |
| Export wallpaper overhead | High | Minimal |

---

## Phases

| # | Phase | Priority | Status | Link |
|---|-------|----------|--------|------|
| 1 | Rendering Optimization | P0 | Pending | [phase-01-rendering-optimization.md](./phase-01-rendering-optimization.md) |
| 2 | State Management | P1 | Pending | [phase-02-state-management.md](./phase-02-state-management.md) |
| 3 | Performance Validation | P2 | Pending | [phase-03-performance-validation.md](./phase-03-performance-validation.md) |

---

## Key Changes Summary

**Phase 1 (Critical):**
- Add `cachedBackgroundImage` and `cachedBlurredImage` to `VideoEditorState`
- Apply `.drawingGroup()` to background layer in `ZoomPreviewOverlay`
- Remove `NSImage(contentsOf:)` from render path

**Phase 2:**
- Implement preview value pattern for smooth slider dragging
- Add async image loading with `SystemWallpaperManager`
- Pre-compute blur on style change

**Phase 3:**
- Measure FPS with Instruments
- Validate 60fps target achieved
- Document performance metrics

---

## Reports

- [01-analysis-report.md](./reports/01-analysis-report.md) - Detailed comparison of Annotate vs VideoEditor

---

## Success Criteria

1. Preview renders at >= 60fps with wallpaper background
2. Slider drag is smooth without frame drops
3. No disk I/O during render cycle
4. Export performance improved (wallpaper cached once)
