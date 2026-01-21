# Plan: Blur Tool Implementation for Annotate Feature

**Date:** 2026-01-18
**Status:** Draft
**Complexity:** Medium

## Overview

Implement functional blur effect for the existing blur tool in ZapShot's annotation editor. The infrastructure exists (toolbar button, annotation types, factory) but actual blur rendering is not implemented.

## Current State Analysis

### What Exists
- `AnnotationToolType.blur` - Tool enum with icon "aqi.medium", shortcut "b"
- `AnnotationType.blur` - Annotation type in data model
- Toolbar button in `AnnotateToolbarView.swift` line 95
- Factory creates blur annotations with bounds (`AnnotationFactory.swift` line 58-59)
- Hit testing treats blur like rectangle (`AnnotationItem.swift` line 75-76)
- Undo/redo system works via `state.saveState()`

### What's Missing
- `AnnotationRenderer.swift` line 58-59: `case .blur: break` - no rendering
- No source image access in renderer for blur effect
- No live preview during blur tool drag
- Export doesn't apply blur to image regions

## Technical Approach

**Chosen Method: Pixelation Effect**

Rationale:
- Simpler implementation than Gaussian blur
- More performant (no CIFilter conversion overhead)
- Effectively obscures sensitive content
- Works well with CGContext-based rendering

Alternative considered: CIGaussianBlur via CIFilter - rejected due to complexity of CGImage conversion in render pipeline.

## Architecture Changes

### 1. BlurEffectRenderer (New Helper)

Create dedicated blur rendering helper that:
- Takes source image + region bounds
- Renders pixelated version of that region
- Works with CGContext for both canvas and export

```
ZapShot/Features/Annotate/Canvas/BlurEffectRenderer.swift
```

### 2. AnnotationRenderer Modification

- Add optional `sourceImage: NSImage?` property
- Call BlurEffectRenderer for `.blur` case
- Blur annotations render FIRST (before other annotations)

### 3. CanvasDrawingView Changes

- Pass source image to renderer
- Add live preview for blur tool during drag
- Render blur annotations before other annotations

### 4. AnnotateExporter Changes

- Pass source image to renderer during export
- Ensure blur regions render correctly with crop/padding offsets

## Implementation Steps

### Step 1: Create BlurEffectRenderer Helper
**File:** `ZapShot/Features/Annotate/Canvas/BlurEffectRenderer.swift`

```swift
struct BlurEffectRenderer {
  static func drawPixelatedRegion(
    in context: CGContext,
    sourceImage: NSImage,
    region: CGRect,
    pixelSize: CGFloat = 10
  )
}
```

Logic:
1. Extract region from source image as CGImage
2. Calculate grid of pixel blocks
3. Sample average color for each block
4. Fill each block with sampled color

### Step 2: Update AnnotationRenderer
**File:** `ZapShot/Features/Annotate/Canvas/AnnotationRenderer.swift`

Changes:
- Add `sourceImage: NSImage?` property to init
- Implement blur case to call BlurEffectRenderer
- Add `drawBlurAnnotations()` method for z-order control

### Step 3: Update CanvasDrawingView
**File:** `ZapShot/Features/Annotate/Canvas/CanvasDrawingView.swift`

Changes:
- Store reference to source image from state
- Pass image to AnnotationRenderer
- Draw blur annotations first, then other annotations
- Add blur preview in `drawCurrentStroke` for blur tool

### Step 4: Update AnnotateExporter
**File:** `ZapShot/Features/Annotate/Export/AnnotateExporter.swift`

Changes:
- Pass source image to AnnotationRenderer in `renderFinalImage()`
- Ensure blur renders correctly with crop offset

### Step 5: Add Blur Intensity Control (Optional Enhancement)
**File:** `ZapShot/Features/Annotate/State/AnnotationProperties.swift`

Add `blurIntensity: CGFloat` property for configurable pixel size.

## File Changes Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `Canvas/BlurEffectRenderer.swift` | NEW | Pixelation rendering helper |
| `Canvas/AnnotationRenderer.swift` | MODIFY | Add sourceImage, implement blur case |
| `Canvas/CanvasDrawingView.swift` | MODIFY | Pass image to renderer, blur preview |
| `Export/AnnotateExporter.swift` | MODIFY | Pass image to renderer |

## Testing Checklist

- [ ] Blur tool creates annotation on drag
- [ ] Blur region shows pixelated effect
- [ ] Blur works with selection tool (select, move, resize)
- [ ] Undo/redo works for blur annotations
- [ ] Multiple blur regions work correctly
- [ ] Export includes blur effect
- [ ] Blur works with crop (only visible portion)
- [ ] Live preview during blur drag operation
- [ ] Performance acceptable with multiple blur regions

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Performance with many blurs | Cache pixelated regions, limit redraw |
| Image coordinate mismatch | Use existing coordinate transform helpers |
| Export crop offset issues | Follow existing offsetAnnotationForCrop pattern |

## Unresolved Questions

1. Should blur intensity be user-configurable via sidebar slider?
2. Default pixel size: 10px seems reasonable, needs testing
3. Should blur have stroke/border indicator when selected?

## Dependencies

- No external dependencies required
- Uses existing CoreGraphics/AppKit APIs
