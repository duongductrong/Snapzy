# Phase 2: Dirty Rect Optimization

## Objective
Redraw only changed canvas regions instead of full canvas on every mouse event.

## Current Problem
`CanvasDrawingView.swift` line 25: `nsView.needsDisplay = true` triggers full canvas redraw.
`AnnotationRenderer` iterates ALL annotations on every draw (lines 532-539 in scout report).

## Solution
Track dirty regions, use `setNeedsDisplay(_:)` with specific rects, clip drawing to dirty area.

## Implementation Steps

### Step 1: Track previous bounds during drag
File: `ZapShot/Features/Annotate/Canvas/CanvasDrawingView.swift`

```swift
final class DrawingCanvasNSView: NSView {
    // Add tracking for dirty rect calculation
    private var previousDragBounds: CGRect = .zero

    // In mouseDragged, calculate union of old + new bounds
    override func mouseDragged(with event: NSEvent) {
        // ... existing code ...

        if isDraggingAnnotation, let selectedId = state.selectedAnnotationId,
           let annotation = state.annotations.first(where: { $0.id == selectedId }) {
            // Calculate dirty rect (old position + new position + padding for handles)
            let padding: CGFloat = 20
            let oldRect = previousDragBounds.insetBy(dx: -padding, dy: -padding)
            let newRect = annotation.bounds.insetBy(dx: -padding, dy: -padding)
            let dirtyRect = oldRect.union(newRect)

            // Convert to display coordinates
            let displayDirty = imageToDisplay(dirtyRect)
            setNeedsDisplay(displayDirty)

            previousDragBounds = annotation.bounds
            return
        }

        // Fallback for other cases
        needsDisplay = true
    }
}
```

### Step 2: Initialize previousDragBounds on drag start
```swift
override func mouseDown(with event: NSEvent) {
    // ... existing selection code ...

    if let annotation = state.selectAnnotation(at: imagePoint) {
        isDraggingAnnotation = true
        previousDragBounds = annotation.bounds  // Track initial position
        // ... rest of existing code ...
    }
}
```

### Step 3: Optimize draw() to respect dirtyRect
```swift
override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let context = NSGraphicsContext.current?.cgContext else { return }

    context.saveGState()
    context.scaleBy(x: displayScale, y: displayScale)

    // Convert dirtyRect to image coordinates for filtering
    let imageDirtyRect = displayToImage(dirtyRect)

    // Only draw annotations that intersect dirty rect
    for annotation in state.annotations {
        let expandedBounds = annotation.bounds.insetBy(dx: -10, dy: -10)
        guard expandedBounds.intersects(imageDirtyRect) else { continue }

        renderer.draw(annotation)

        if annotation.id == state.selectedAnnotationId {
            drawSelectionHandles(for: annotation.bounds, in: context)
        }
    }

    // ... rest of drawing code ...
    context.restoreGState()
}
```

### Step 4: Handle resize with dirty rect
```swift
// In mouseDragged resize handling
if isResizingAnnotation, let handle = activeResizeHandle,
   let selectedId = state.selectedAnnotationId,
   let annotation = state.annotations.first(where: { $0.id == selectedId }) {

    let padding: CGFloat = 20
    let oldRect = previousDragBounds.insetBy(dx: -padding, dy: -padding)
    let newBounds = calculateResizedBounds(handle: handle, currentPoint: imagePoint)
    let newRect = newBounds.insetBy(dx: -padding, dy: -padding)

    let dirtyRect = oldRect.union(newRect)
    setNeedsDisplay(imageToDisplay(dirtyRect))

    previousDragBounds = newBounds
    // ... update bounds ...
}
```

## Testing Checklist
- [ ] Dragging annotation only redraws affected region
- [ ] Selection handles render correctly at new position
- [ ] No visual artifacts from partial redraw
- [ ] Overlapping annotations render correctly
- [ ] Resize operations update correctly

## Success Metrics
- Draw call scope reduced (verify with Instruments)
- Frame time improvement for canvases with many annotations
- CPU usage lower during drag (fewer pixels processed)

## Rollback
Revert to `needsDisplay = true` for all cases. Single-line change.

## Risk Assessment
- **LOW** - NSView dirty rect is standard pattern
- Edge case: fast drags may need larger padding
- Overlapping annotations may need union calculation
