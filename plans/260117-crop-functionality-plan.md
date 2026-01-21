# Plan: Crop Functionality for Annotation Canvas

**Date:** 2025-01-17
**Feature:** Implement crop tool for canvas image cropping
**Complexity:** Hard (multi-file changes across state, views, canvas, export)

---

## Overview

Implement crop functionality allowing users to define a rectangular crop region on the canvas. The cropped area will be applied to the final exported image along with annotations.

---

## Current State Analysis

### Existing Infrastructure
- `AnnotationToolType.crop` - Already defined in enum (shortcut: "c", icon: "crop")
- `AnnotateToolbarView` - Crop button exists but only sets `state.selectedTool = .crop`
- `CanvasDrawingView` - Handles mouse events, has coordinate transformation utilities
- `AnnotateState` - Central state management with @Published properties
- `AnnotateExporter` - Renders final image with annotations

### Gap Analysis
- No crop state properties in `AnnotateState`
- No crop overlay rendering in canvas
- No crop-specific mouse handling in `CanvasDrawingView`
- No crop application in `AnnotateExporter`

---

## Implementation Plan

### Phase 1: State Management (AnnotateState.swift)

**Add crop-related properties:**

```swift
// MARK: - Crop State
@Published var cropRect: CGRect? = nil  // nil = no crop, full image
@Published var isCropActive: Bool = false  // Whether crop mode is actively being edited
```

**Add crop helper methods:**

```swift
// Initialize crop to full image bounds
func initializeCrop() {
    cropRect = CGRect(origin: .zero, size: CGSize(width: imageWidth, height: imageHeight))
    isCropActive = true
}

// Apply crop (confirm)
func applyCrop() {
    isCropActive = false
    // cropRect remains set for export
}

// Cancel crop
func cancelCrop() {
    cropRect = nil
    isCropActive = false
    selectedTool = .selection
}

// Reset crop to nil
func resetCrop() {
    cropRect = nil
    isCropActive = false
}
```

**Files:** `ZapShot/Features/Annotate/State/AnnotateState.swift`
**Lines affected:** ~20 new lines in crop section

---

### Phase 2: Crop Overlay View (New File)

**Create:** `ZapShot/Features/Annotate/Views/CropOverlayView.swift`

SwiftUI overlay that renders:
1. Semi-transparent darkening outside crop region
2. Crop border with dashed line
3. Corner and edge resize handles
4. Rule of thirds grid (optional, toggleable)

```swift
struct CropOverlayView: View {
    @ObservedObject var state: AnnotateState
    let scale: CGFloat
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dim overlay outside crop
                CropDimOverlay(cropRect: scaledCropRect, containerSize: geometry.size)

                // Crop border and handles
                CropHandlesView(
                    cropRect: $state.cropRect,
                    scale: scale,
                    imageSize: imageSize
                )
            }
        }
    }
}
```

**Components:**
- `CropDimOverlay` - Four rectangles around crop area with 0.5 opacity black
- `CropHandlesView` - Border + 8 handles (4 corners + 4 edges)
- Handle size: 12pt, white fill with blue border

**Files:** New file `CropOverlayView.swift` (~120 lines)

---

### Phase 3: Crop Mouse Handling (CanvasDrawingView.swift)

**Add crop-specific state:**

```swift
// Crop interaction state
private var isCropDragging = false
private var isCropResizing = false
private var activeCropHandle: CropHandle?
private var cropDragStart: CGPoint?
private var originalCropRect: CGRect?

enum CropHandle {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight
    case body  // For moving entire crop
}
```

**Modify mouse event handlers:**

In `mouseDown`:
```swift
if state.selectedTool == .crop {
    if state.cropRect == nil {
        // Initialize crop to full image
        state.initializeCrop()
    }
    // Check for handle hit or body hit
    if let handle = hitTestCropHandle(at: imagePoint) {
        isCropResizing = true
        activeCropHandle = handle
        originalCropRect = state.cropRect
    } else if state.cropRect?.contains(imagePoint) == true {
        isCropDragging = true
        cropDragStart = imagePoint
        originalCropRect = state.cropRect
    }
    return
}
```

In `mouseDragged`:
```swift
if isCropResizing, let handle = activeCropHandle {
    updateCropRect(handle: handle, currentPoint: imagePoint)
    needsDisplay = true
    return
}
if isCropDragging {
    moveCropRect(to: imagePoint)
    needsDisplay = true
    return
}
```

In `mouseUp`:
```swift
if isCropResizing || isCropDragging {
    isCropResizing = false
    isCropDragging = false
    activeCropHandle = nil
    return
}
```

**Add keyboard handling for crop:**

In `keyDown`:
```swift
case 36: // Enter - confirm crop
    if state.selectedTool == .crop && state.isCropActive {
        state.applyCrop()
        state.selectedTool = .selection
    }

case 53: // Escape - cancel crop (already exists, extend)
    if state.selectedTool == .crop && state.isCropActive {
        state.cancelCrop()
    }
```

**Files:** `ZapShot/Features/Annotate/Canvas/CanvasDrawingView.swift`
**Lines affected:** ~80 new lines for crop handling

---

### Phase 4: Crop Rendering in Canvas

**Option A (Recommended):** Render crop overlay in SwiftUI layer

In `AnnotateCanvasView.swift`, add crop overlay after drawing canvas:

```swift
// Inside canvasContent ZStack, after TextEditOverlay
if state.selectedTool == .crop || state.cropRect != nil {
    CropOverlayView(
        state: state,
        scale: scale,
        imageSize: CGSize(width: state.imageWidth, height: state.imageHeight)
    )
    .frame(width: imgWidth, height: imgHeight)
    .offset(x: offset.x, y: offset.y)
    .allowsHitTesting(state.selectedTool == .crop)
}
```

**Option B:** Render in `DrawingCanvasNSView.draw()` method

Add crop drawing after annotations:
```swift
// Draw crop overlay if active
if state.selectedTool == .crop, let cropRect = state.cropRect {
    drawCropOverlay(cropRect: cropRect, in: context)
}
```

**Recommendation:** Use Option A (SwiftUI) for cleaner separation, consistent with `TextEditOverlay` pattern.

**Files:** `ZapShot/Features/Annotate/Views/AnnotateCanvasView.swift`
**Lines affected:** ~15 new lines

---

### Phase 5: Export with Crop (AnnotateExporter.swift)

**Modify `renderFinalImage` to respect crop bounds:**

```swift
private static func renderFinalImage(state: AnnotateState) -> NSImage? {
    guard let sourceImage = state.sourceImage else { return nil }

    // Determine effective image bounds (crop or full)
    let effectiveBounds: CGRect
    if let cropRect = state.cropRect {
        effectiveBounds = cropRect
    } else {
        effectiveBounds = CGRect(origin: .zero, size: sourceImage.size)
    }

    let padding = state.backgroundStyle != .none ? state.padding : 0
    let totalSize = NSSize(
        width: effectiveBounds.width + padding * 2,
        height: effectiveBounds.height + padding * 2
    )

    let image = NSImage(size: totalSize)
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return nil
    }

    // Draw background
    drawBackground(state: state, in: context, size: totalSize)

    // Draw cropped portion of source image
    let destRect = NSRect(
        x: padding,
        y: padding,
        width: effectiveBounds.width,
        height: effectiveBounds.height
    )

    // Source rect in image coordinates (flip Y for NSImage)
    let sourceRect = NSRect(
        x: effectiveBounds.origin.x,
        y: sourceImage.size.height - effectiveBounds.origin.y - effectiveBounds.height,
        width: effectiveBounds.width,
        height: effectiveBounds.height
    )

    if state.cornerRadius > 0 {
        let path = NSBezierPath(roundedRect: destRect, xRadius: state.cornerRadius, yRadius: state.cornerRadius)
        path.addClip()
    }

    sourceImage.draw(in: destRect, from: sourceRect, operation: .sourceOver, fraction: 1.0)

    context.resetClip()

    // Draw annotations (offset by padding AND crop origin)
    let renderer = AnnotationRenderer(context: context)
    for annotation in state.annotations {
        // Only include annotations within crop bounds
        if let cropRect = state.cropRect {
            guard annotation.bounds.intersects(cropRect) else { continue }
        }
        let offsetAnnotation = offsetAnnotationForCrop(
            annotation,
            cropOrigin: effectiveBounds.origin,
            padding: padding
        )
        renderer.draw(offsetAnnotation)
    }

    image.unlockFocus()
    return image
}

private static func offsetAnnotationForCrop(
    _ annotation: AnnotationItem,
    cropOrigin: CGPoint,
    padding: CGFloat
) -> AnnotationItem {
    var result = annotation
    result.bounds = CGRect(
        x: annotation.bounds.origin.x - cropOrigin.x + padding,
        y: annotation.bounds.origin.y - cropOrigin.y + padding,
        width: annotation.bounds.width,
        height: annotation.bounds.height
    )

    // Offset internal points for lines/arrows/paths
    switch annotation.type {
    case .arrow(let start, let end):
        result.type = .arrow(
            start: CGPoint(x: start.x - cropOrigin.x + padding, y: start.y - cropOrigin.y + padding),
            end: CGPoint(x: end.x - cropOrigin.x + padding, y: end.y - cropOrigin.y + padding)
        )
    case .line(let start, let end):
        result.type = .line(
            start: CGPoint(x: start.x - cropOrigin.x + padding, y: start.y - cropOrigin.y + padding),
            end: CGPoint(x: end.x - cropOrigin.x + padding, y: end.y - cropOrigin.y + padding)
        )
    case .path(let points):
        result.type = .path(points.map {
            CGPoint(x: $0.x - cropOrigin.x + padding, y: $0.y - cropOrigin.y + padding)
        })
    case .highlight(let points):
        result.type = .highlight(points.map {
            CGPoint(x: $0.x - cropOrigin.x + padding, y: $0.y - cropOrigin.y + padding)
        })
    default:
        break
    }

    return result
}
```

**Files:** `ZapShot/Features/Annotate/Export/AnnotateExporter.swift`
**Lines affected:** ~60 modified/new lines

---

### Phase 6: UI Polish & Edge Cases

**1. Toolbar feedback:**
- Show "Apply" and "Cancel" buttons when crop is active
- Or rely on keyboard shortcuts (Enter/Escape) with tooltip

**2. Minimum crop size:**
- Enforce minimum 20x20 pixels to prevent zero-size crops

**3. Constrain crop to image bounds:**
```swift
func constrainCropToImageBounds(_ rect: CGRect) -> CGRect {
    var constrained = rect
    constrained.origin.x = max(0, constrained.origin.x)
    constrained.origin.y = max(0, constrained.origin.y)
    constrained.size.width = min(constrained.width, imageWidth - constrained.origin.x)
    constrained.size.height = min(constrained.height, imageHeight - constrained.origin.y)
    return constrained
}
```

**4. Reset crop when loading new image:**
In `loadImage(from:)` and `loadImage(_:url:)`:
```swift
cropRect = nil
isCropActive = false
```

**5. Cursor updates:**
- Crosshair for corner handles
- Resize arrows for edge handles
- Move cursor when over crop body

---

## File Summary

| File | Action | Lines |
|------|--------|-------|
| `State/AnnotateState.swift` | Modify | +25 |
| `Views/CropOverlayView.swift` | Create | ~120 |
| `Canvas/CanvasDrawingView.swift` | Modify | +80 |
| `Views/AnnotateCanvasView.swift` | Modify | +15 |
| `Export/AnnotateExporter.swift` | Modify | +60 |

**Total:** ~300 lines of new/modified code

---

## Testing Checklist

- [ ] Select crop tool from toolbar
- [ ] Initial crop covers full image
- [ ] Drag corners to resize crop
- [ ] Drag edges to resize crop
- [ ] Drag inside crop to move region
- [ ] Enter key confirms crop
- [ ] Escape key cancels crop
- [ ] Exported image respects crop bounds
- [ ] Annotations within crop are exported correctly
- [ ] Annotations outside crop are excluded
- [ ] Crop works with background/padding settings
- [ ] Crop persists when switching tools and back
- [ ] Loading new image resets crop
- [ ] Crop handles scale properly with zoom

---

## Unresolved Questions

1. **Aspect ratio lock?** Should we support Shift+drag to maintain aspect ratio? (Suggest: v2 feature)
2. **Preset ratios?** Common ratios like 16:9, 4:3, 1:1 in dropdown? (Suggest: v2 feature)
3. **Crop preview in sidebar?** Show dimensions/preview in sidebar? (Suggest: optional enhancement)

---

## Recommendation

Proceed with implementation in phases. Phase 1-3 are core functionality. Phase 4-5 complete the feature. Phase 6 handles edge cases and polish.

Estimated complexity: **Medium-Hard** - follows existing patterns but requires careful coordinate handling.
