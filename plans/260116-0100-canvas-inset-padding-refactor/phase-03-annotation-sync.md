# Phase 03: Annotation Coordinate Synchronization

## Objective

Update `CanvasDrawingView` to handle coordinate transformations between display and image space.

## Problem

Annotations stored in image-relative coordinates. With inset padding, display scale changes dynamically. Must transform:
- User input (display coords) -> storage (image coords)
- Stored annotations (image coords) -> rendering (display coords)

## File: `CanvasDrawingView.swift`

### Add Display Scale Property

```swift
struct CanvasDrawingView: NSViewRepresentable {
    @ObservedObject var state: AnnotateState
    var displayScale: CGFloat = 1.0  // Add this

    func makeNSView(context: Context) -> DrawingCanvasNSView {
        let view = DrawingCanvasNSView(state: state)
        view.displayScale = displayScale  // Pass to NSView
        return view
    }

    func updateNSView(_ nsView: DrawingCanvasNSView, context: Context) {
        nsView.state = state
        nsView.displayScale = displayScale  // Update on change
        nsView.needsDisplay = true
    }
}
```

### Update DrawingCanvasNSView

Add property and coordinate transformation methods:

```swift
final class DrawingCanvasNSView: NSView {
    var state: AnnotateState
    var displayScale: CGFloat = 1.0  // Add this

    // ... existing properties ...

    // MARK: - Coordinate Transformation

    /// Convert display point to image coordinates (for storage)
    private func displayToImage(_ point: CGPoint) -> CGPoint {
        guard displayScale > 0 else { return point }
        return CGPoint(
            x: point.x / displayScale,
            y: point.y / displayScale
        )
    }

    /// Convert image point to display coordinates (for rendering)
    private func imageToDisplay(_ point: CGPoint) -> CGPoint {
        return CGPoint(
            x: point.x * displayScale,
            y: point.y * displayScale
        )
    }

    /// Convert image rect to display coordinates
    private func imageToDisplay(_ rect: CGRect) -> CGRect {
        return CGRect(
            x: rect.origin.x * displayScale,
            y: rect.origin.y * displayScale,
            width: rect.width * displayScale,
            height: rect.height * displayScale
        )
    }

    /// Convert display rect to image coordinates
    private func displayToImage(_ rect: CGRect) -> CGRect {
        guard displayScale > 0 else { return rect }
        return CGRect(
            x: rect.origin.x / displayScale,
            y: rect.origin.y / displayScale,
            width: rect.width / displayScale,
            height: rect.height / displayScale
        )
    }
}
```

### Update Mouse Event Handlers

#### mouseDown (around line 93)

```swift
override func mouseDown(with event: NSEvent) {
    let displayPoint = convert(event.locationInWindow, from: nil)
    let imagePoint = displayToImage(displayPoint)  // Convert to image coords
    dragStart = imagePoint  // Store in image coords

    // Check handles using display coordinates (handles are drawn in display space)
    if let selectedId = state.selectedAnnotationId,
       let annotation = state.annotations.first(where: { $0.id == selectedId }) {
        let displayBounds = imageToDisplay(annotation.bounds)
        if let handle = hitTestHandle(at: displayPoint, for: displayBounds) {
            isResizingAnnotation = true
            activeResizeHandle = handle
            originalBounds = annotation.bounds  // Store in image coords
            return
        }
    }

    // Selection uses image coordinates
    if state.selectedTool == .selection {
        if let annotation = state.selectAnnotation(at: imagePoint) {
            isDraggingAnnotation = true
            dragOffset = CGPoint(
                x: imagePoint.x - annotation.bounds.origin.x,
                y: imagePoint.y - annotation.bounds.origin.y
            )
            originalBounds = annotation.bounds
            needsDisplay = true
            return
        }
    }

    // Drawing starts in image coordinates
    isDrawing = true
    switch state.selectedTool {
    case .pencil, .highlighter:
        currentPath = [imagePoint]
    case .text:
        Task { @MainActor in
            state.saveState()
            createTextAnnotation(at: imagePoint)
        }
        isDrawing = false
    default:
        break
    }
}
```

#### mouseDragged (around line 139)

```swift
override func mouseDragged(with event: NSEvent) {
    let displayPoint = convert(event.locationInWindow, from: nil)
    let imagePoint = displayToImage(displayPoint)

    // Resizing uses image coordinates
    if isResizingAnnotation, let handle = activeResizeHandle,
       let selectedId = state.selectedAnnotationId {
        let newBounds = calculateResizedBounds(handle: handle, currentPoint: imagePoint)
        Task { @MainActor in
            state.updateAnnotationBounds(id: selectedId, bounds: newBounds)
        }
        needsDisplay = true
        return
    }

    // Dragging uses image coordinates
    if isDraggingAnnotation, let selectedId = state.selectedAnnotationId {
        let newOrigin = CGPoint(
            x: imagePoint.x - dragOffset.x,
            y: imagePoint.y - dragOffset.y
        )
        let newBounds = CGRect(origin: newOrigin, size: originalBounds.size)
        Task { @MainActor in
            state.updateAnnotationBounds(id: selectedId, bounds: newBounds)
        }
        needsDisplay = true
        return
    }

    // Drawing in image coordinates
    guard isDrawing else { return }

    switch state.selectedTool {
    case .pencil, .highlighter:
        currentPath.append(imagePoint)
        needsDisplay = true
    default:
        currentPath = [imagePoint]
        needsDisplay = true
    }
}
```

#### mouseUp (around line 180)

```swift
override func mouseUp(with event: NSEvent) {
    let displayPoint = convert(event.locationInWindow, from: nil)
    let imagePoint = displayToImage(displayPoint)

    // ... existing resize/drag finish logic unchanged ...

    guard isDrawing, let start = dragStart else { return }

    Task { @MainActor in
        state.saveState()
        createAnnotation(from: start, to: imagePoint)  // Already in image coords
    }

    // ... rest unchanged ...
}
```

### Update Drawing Method

```swift
override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let context = NSGraphicsContext.current?.cgContext else { return }

    // Apply scale transform for rendering
    context.saveGState()
    context.scaleBy(x: displayScale, y: displayScale)

    // Draw annotations at image coordinates (transform handles scaling)
    let renderer = AnnotationRenderer(context: context)
    for annotation in state.annotations {
        renderer.draw(annotation)

        if annotation.id == state.selectedAnnotationId {
            drawSelectionHandles(for: annotation.bounds, in: context)
        }
    }

    // Draw current stroke
    if isDrawing, let start = dragStart {
        renderer.drawCurrentStroke(
            tool: state.selectedTool,
            start: start,
            currentPath: currentPath,
            strokeColor: state.strokeColor,
            strokeWidth: state.strokeWidth
        )
    }

    context.restoreGState()
}
```

### Update Handle Hit Testing

Handle rects need adjustment for scale:

```swift
private func handleRect(at center: CGPoint) -> CGRect {
    // Handle size in display coordinates (constant visual size)
    let displayHandleSize = handleSize / displayScale
    return CGRect(
        x: center.x - displayHandleSize / 2,
        y: center.y - displayHandleSize / 2,
        width: displayHandleSize,
        height: displayHandleSize
    )
}
```

## Validation

- [ ] New annotations created at correct positions
- [ ] Existing annotations render at correct positions after scale change
- [ ] Selection and dragging work correctly
- [ ] Resizing works correctly
- [ ] Undo/redo maintains correct positions

## Edge Cases

- Very high padding (image scales very small)
- Zoom combined with padding
- Annotations near image edges
