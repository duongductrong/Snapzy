# Phase 3: Layer Separation for Drag Operations

## Objective
Separate static annotations from moving annotation during drag to avoid redrawing unchanged content.

## Current Problem
All annotations rendered on single layer. Moving one annotation redraws all others every frame.

## Solution
Use CALayer composition:
- Base layer: Static annotations (cached bitmap)
- Overlay layer: Currently dragged annotation (redrawn per frame)
- Composite on mouseUp

## Implementation Steps

### Step 1: Add layer properties to DrawingCanvasNSView
File: `ZapShot/Features/Annotate/Canvas/CanvasDrawingView.swift`

```swift
final class DrawingCanvasNSView: NSView {
    // Layer for static content
    private var staticLayer: CALayer?
    private var staticLayerImage: CGImage?
    private var staticLayerNeedsUpdate: Bool = true

    // ID of annotation being dragged (excluded from static layer)
    private var draggingAnnotationId: UUID?

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // Create static content sublayer
        let static = CALayer()
        static.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        layer?.addSublayer(static)
        staticLayer = static

        // ... existing tracking area code ...
    }
}
```

### Step 2: Render static layer on drag start
```swift
override func mouseDown(with event: NSEvent) {
    // ... existing code ...

    if let annotation = state.selectAnnotation(at: imagePoint) {
        isDraggingAnnotation = true
        draggingAnnotationId = annotation.id

        // Render all OTHER annotations to static layer
        renderStaticLayer(excluding: annotation.id)

        // ... rest of existing code ...
    }
}

private func renderStaticLayer(excluding annotationId: UUID) {
    let size = bounds.size
    guard size.width > 0, size.height > 0 else { return }

    // Create offscreen context
    guard let context = CGContext(
        data: nil,
        width: Int(size.width * displayScale),
        height: Int(size.height * displayScale),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return }

    context.scaleBy(x: displayScale, y: displayScale)

    // Draw all annotations except the one being dragged
    let renderer = AnnotationRenderer(
        context: context,
        editingTextId: state.editingTextAnnotationId,
        sourceImage: state.sourceImage,
        blurCacheManager: blurCacheManager
    )

    for annotation in state.annotations where annotation.id != annotationId {
        renderer.draw(annotation)
    }

    staticLayerImage = context.makeImage()
    staticLayer?.contents = staticLayerImage
}
```

### Step 3: Optimize draw() during drag
```swift
override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let context = NSGraphicsContext.current?.cgContext else { return }

    context.saveGState()
    context.scaleBy(x: displayScale, y: displayScale)

    if isDraggingAnnotation, let dragId = draggingAnnotationId {
        // Static layer handles other annotations via CALayer
        // Only draw the dragged annotation here
        if let annotation = state.annotations.first(where: { $0.id == dragId }) {
            let renderer = AnnotationRenderer(
                context: context,
                editingTextId: state.editingTextAnnotationId,
                sourceImage: state.sourceImage,
                blurCacheManager: blurCacheManager
            )
            renderer.draw(annotation)
            drawSelectionHandles(for: annotation.bounds, in: context)
        }
    } else {
        // Normal mode: draw all annotations
        let renderer = AnnotationRenderer(/* ... */)
        for annotation in state.annotations {
            renderer.draw(annotation)
            if annotation.id == state.selectedAnnotationId {
                drawSelectionHandles(for: annotation.bounds, in: context)
            }
        }
    }

    // ... current stroke drawing ...
    context.restoreGState()
}
```

### Step 4: Clear static layer on drag end
```swift
override func mouseUp(with event: NSEvent) {
    if isDraggingAnnotation {
        // Clear static layer, return to normal rendering
        staticLayer?.contents = nil
        staticLayerImage = nil
        draggingAnnotationId = nil

        // ... existing mouseUp code ...
    }
}
```

## Testing Checklist
- [ ] Static annotations don't flicker during drag
- [ ] Dragged annotation renders smoothly
- [ ] Layer compositing correct on drag end
- [ ] No visual artifacts at layer boundaries
- [ ] Works with overlapping annotations

## Success Metrics
- During drag: only 1 annotation drawn per frame (not N)
- Static layer rendered once at drag start
- Frame time proportional to dragged annotation complexity only

## Rollback
Remove CALayer logic, revert to single-layer drawing in draw().

## Risk Assessment
- **MEDIUM** - CALayer composition adds complexity
- Z-order must be preserved correctly
- Memory usage increases slightly (cached static layer)
