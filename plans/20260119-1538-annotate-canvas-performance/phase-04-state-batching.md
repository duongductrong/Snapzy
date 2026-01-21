# Phase 4: State Update Batching During Drag

## Objective
Reduce SwiftUI view recomputation by batching state updates during drag operations.

## Current Problem
`AnnotateState.swift` line 359: `updateAnnotationBounds()` modifies `@Published annotations` array.
Each modification triggers SwiftUI to recompute views, causing cascade of updates during drag.

## Solution
Use local drag state in NSView, only commit to `@Published` model on mouseUp.

## Implementation Steps

### Step 1: Add local drag state to DrawingCanvasNSView
File: `ZapShot/Features/Annotate/Canvas/CanvasDrawingView.swift`

```swift
final class DrawingCanvasNSView: NSView {
    // Local drag state (not @Published, no SwiftUI updates)
    private var localDragBounds: CGRect?
    private var localDragAnnotation: AnnotationItem?

    // Track if we're using local state
    private var isUsingLocalDragState: Bool { localDragAnnotation != nil }
}
```

### Step 2: Capture annotation at drag start
```swift
override func mouseDown(with event: NSEvent) {
    // ... existing code ...

    if let annotation = state.selectAnnotation(at: imagePoint) {
        isDraggingAnnotation = true

        // Capture copy of annotation for local manipulation
        localDragAnnotation = annotation
        localDragBounds = annotation.bounds

        dragOffset = CGPoint(
            x: imagePoint.x - annotation.bounds.origin.x,
            y: imagePoint.y - annotation.bounds.origin.y
        )
        originalBounds = annotation.bounds
        NSCursor.closedHand.set()
        needsDisplay = true
        return
    }
}
```

### Step 3: Update local state during drag (no @Published)
```swift
override func mouseDragged(with event: NSEvent) {
    // ... existing code ...

    // Handle dragging with LOCAL state only
    if isDraggingAnnotation, localDragAnnotation != nil {
        let newOrigin = CGPoint(
            x: imagePoint.x - dragOffset.x,
            y: imagePoint.y - dragOffset.y
        )
        localDragBounds = CGRect(origin: newOrigin, size: originalBounds.size)

        // Update local copy (not state.annotations)
        localDragAnnotation?.bounds = localDragBounds!

        // Also update embedded coordinates for arrows/lines
        updateLocalAnnotationCoordinates(dx: newOrigin.x - originalBounds.origin.x,
                                          dy: newOrigin.y - originalBounds.origin.y)

        needsDisplay = true  // or setNeedsDisplay(dirtyRect) from Phase 2
        return
    }
}

private func updateLocalAnnotationCoordinates(dx: CGFloat, dy: CGFloat) {
    guard var annotation = localDragAnnotation else { return }

    switch annotation.type {
    case .arrow(let start, let end):
        let originalStart = /* store at drag start */
        annotation.type = .arrow(
            start: CGPoint(x: originalStart.x + dx, y: originalStart.y + dy),
            end: CGPoint(x: originalEnd.x + dx, y: originalEnd.y + dy)
        )
    case .line(let start, let end):
        // Similar to arrow
    case .path(let points):
        annotation.type = .path(originalPoints.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
    default:
        break
    }

    localDragAnnotation = annotation
}
```

### Step 4: Commit to model on mouseUp
```swift
override func mouseUp(with event: NSEvent) {
    if isDraggingAnnotation, let annotation = localDragAnnotation,
       let finalBounds = localDragBounds {

        // Single state update at end of drag
        Task { @MainActor in
            state.saveState()
            state.updateAnnotationBounds(id: annotation.id, bounds: finalBounds)
        }

        // Clear local state
        localDragAnnotation = nil
        localDragBounds = nil
        isDraggingAnnotation = false

        updateCursor(for: event)
        needsDisplay = true
        return
    }

    // ... rest of existing mouseUp code ...
}
```

### Step 5: Draw local annotation during drag
```swift
override func draw(_ dirtyRect: NSRect) {
    // ... existing setup ...

    for annotation in state.annotations {
        // Use local bounds for dragged annotation
        var annotationToDraw = annotation
        if isDraggingAnnotation,
           annotation.id == localDragAnnotation?.id,
           let localAnnotation = localDragAnnotation {
            annotationToDraw = localAnnotation
        }

        renderer.draw(annotationToDraw)

        if annotationToDraw.id == state.selectedAnnotationId {
            drawSelectionHandles(for: annotationToDraw.bounds, in: context)
        }
    }

    // ... rest of drawing ...
}
```

## Testing Checklist
- [ ] Drag updates visually smooth
- [ ] No SwiftUI recomposition during drag (verify with Instruments)
- [ ] Final position commits correctly on mouseUp
- [ ] Undo captures correct state
- [ ] Arrow/line/path endpoints update correctly

## Success Metrics
- Zero `@Published` mutations during drag
- SwiftUI body recomputation only on mouseUp
- Reduced main thread work during drag

## Rollback
Remove local state variables, revert to direct `state.updateAnnotationBounds()` calls.

## Risk Assessment
- **LOW** - Pattern well-established (local state + commit)
- Must ensure local/model state stays synchronized
- Arrow/line coordinate updates need careful handling
