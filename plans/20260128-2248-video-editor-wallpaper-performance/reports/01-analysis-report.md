# Analysis Report: VideoEditor Wallpaper Performance

**Date:** 2026-01-28
**Target:** >= 60fps wallpaper rendering in VideoEditor

---

## 1. Annotate Wallpaper Implementation Patterns

### 1.1 State Management (`AnnotateState.swift`)

**Key Optimizations Found:**

1. **Pre-cached Background Images**
   - `cachedBackgroundImage: NSImage?` - loaded once, reused every frame
   - `cachedBlurredImage: NSImage?` - pre-computed blur, not real-time
   - Race condition guard via `loadingBackgroundURL` tracking

2. **Preview Value Pattern**
   - `previewPadding`, `previewInset`, `previewShadowIntensity`, `previewCornerRadius`
   - Effective values computed: `effectivePadding = previewPadding ?? padding`
   - Prevents redundant state updates during slider drag

3. **Async Image Loading**
   - `SystemWallpaperManager.shared.loadPreviewImage()` with callback
   - Preview cache uses 2048px max resolution (`WallpaperQualityConfig.maxResolution`)
   - Loads happen off main thread

4. **Pre-computed Blur**
   - `applyGaussianBlur()` runs once when style changes to `.blurred`
   - Uses `CIGaussianBlur` filter with GPU acceleration
   - Result cached in `cachedBlurredImage`

### 1.2 Rendering (`AnnotateCanvasView.swift`)

**Key Optimizations Found:**

1. **`.drawingGroup()` Modifier**
   - Applied to background layer (line 255)
   - Applied to image layer (line 272)
   - Rasterizes SwiftUI views to Metal texture
   - Critical for 60fps with complex gradients/images

2. **Cached Image Usage**
   - `state.cachedBackgroundImage` used directly in view
   - No disk I/O during render cycle
   - Fallback chain: cachedBlurred -> cachedBackground -> placeholder

3. **Scale-Aware Rendering**
   - `displayScale` computed once per geometry change
   - All dimensions pre-calculated before render

### 1.3 Blur Cache (`BlurCacheManager.swift`)

**Key Optimizations Found:**

1. **UUID-Based Caching**
   - `cache: [UUID: CacheEntry]` keyed by annotation ID
   - Invalidation on bounds change only

2. **Offscreen Rendering**
   - `CGContext` bitmap rendering
   - Shared `CIContext` for GPU acceleration: `BlurEffectRenderer.sharedCIContext`

---

## 2. VideoEditor Current State

### 2.1 State Management (`VideoEditorState.swift`)

**Missing Optimizations:**

1. **No Cached Background Image**
   - `backgroundStyle: BackgroundStyle` stored, but no cached NSImage
   - No `cachedBackgroundImage` equivalent

2. **No Preview Value Pattern**
   - Direct binding to `backgroundPadding`, `backgroundShadowIntensity`, `backgroundCornerRadius`
   - Every slider tick triggers full re-render

3. **No Pre-computed Blur**
   - No `cachedBlurredImage` equivalent
   - Blur computed per-frame in ZoomPreviewOverlay

### 2.2 Rendering (`ZoomPreviewOverlay.swift`)

**Performance Issues Found:**

1. **No `.drawingGroup()` Usage** (Critical)
   - Line 64-93: `backgroundView` renders complex gradients/images without rasterization
   - Every frame recomputes SwiftUI view hierarchy

2. **Disk I/O During Render** (Critical)
   - Line 77: `NSImage(contentsOf: url)` called every frame for wallpaper
   - Line 85: Same for blurred wallpaper
   - File system access blocks main thread

3. **Real-time Blur** (Critical)
   - Line 89: `.blur(radius: 20)` applied every frame
   - SwiftUI blur is expensive without caching

4. **No Scale Factor Caching**
   - `previewScaleFactor()` recalculated every render

### 2.3 Export (`ZoomCompositor.swift`)

**Export-Time Issues:**

1. **Wallpaper Loaded Per-Frame**
   - Line 432-433: `CIImage(contentsOf: url)` in `createBackgroundImage()`
   - Called for every video frame during export
   - Disk I/O * frame count = massive slowdown

2. **Blur Computed Per-Frame**
   - Line 442: `.applyingGaussianBlur(sigma: 20)` every frame
   - No caching between frames

---

## 3. Performance Comparison

| Aspect | Annotate | VideoEditor | Gap |
|--------|----------|-------------|-----|
| Background Image Caching | Yes (cachedBackgroundImage) | No | Critical |
| Pre-computed Blur | Yes (cachedBlurredImage) | No | Critical |
| `.drawingGroup()` | Yes (both layers) | No | Critical |
| Preview Values | Yes (effectiveX pattern) | No | Medium |
| Async Loading | Yes (callback-based) | No | Medium |
| Shared CIContext | Yes (GPU-backed) | Yes | OK |
| Race Condition Guards | Yes (loadingBackgroundURL) | No | Low |

---

## 4. Specific Improvements Needed

### 4.1 Phase 1: Rendering Optimization (Critical)

1. Add `cachedBackgroundImage` to `VideoEditorState`
2. Add `cachedBlurredImage` to `VideoEditorState`
3. Add `.drawingGroup()` to background layer in `ZoomPreviewOverlay`
4. Remove disk I/O from render path

### 4.2 Phase 2: State Management

1. Implement preview value pattern for sliders
2. Add `loadBackgroundImage()` with async loading
3. Add race condition guards
4. Pre-compute blur on style change

### 4.3 Phase 3: Export Optimization

1. Cache wallpaper `CIImage` at export start
2. Cache blurred variant once
3. Reuse across all frames

---

## 5. Expected Performance Impact

| Change | FPS Impact | Priority |
|--------|------------|----------|
| Remove disk I/O from render | +20-30fps | P0 |
| Add `.drawingGroup()` | +10-15fps | P0 |
| Pre-compute blur | +5-10fps | P0 |
| Preview value pattern | +2-5fps | P1 |
| Export caching | N/A (export speed) | P1 |

**Total Expected Improvement:** 37-60fps gain, achieving >= 60fps target

---

## 6. Unresolved Questions

1. Should `VideoEditorState` use same `SystemWallpaperManager` for loading?
2. Is 2048px preview resolution sufficient for 4K video preview?
3. Should export use higher resolution wallpaper than preview?
