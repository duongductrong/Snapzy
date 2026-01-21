# Scout Report: Annotation Architecture

**Date:** 2026-01-16
**Scope:** ZapShot Annotate Feature

## File Structure

```
Features/Annotate/
├── State/
│   ├── AnnotateState.swift        # Central state management
│   ├── AnnotationItem.swift       # Annotation model
│   └── AnnotationToolType.swift   # Tool enum
├── Canvas/
│   ├── CanvasDrawingView.swift    # NSView for mouse events
│   ├── AnnotationRenderer.swift   # CGContext drawing
│   └── AnnotationFactory.swift    # Creates annotations
├── Views/
│   ├── AnnotateMainView.swift     # Main container
│   ├── AnnotateCanvasView.swift   # SwiftUI canvas wrapper
│   ├── AnnotateSidebarView.swift  # Left sidebar
│   ├── AnnotateSidebarSections.swift
│   ├── AnnotateSidebarComponents.swift
│   ├── AnnotateToolbarView.swift  # Top toolbar
│   └── AnnotateBottomBarView.swift
├── Background/
│   └── BackgroundStyle.swift
├── Export/
│   └── AnnotateExporter.swift     # Renders final image
├── Window/
│   ├── AnnotateWindow.swift
│   └── AnnotateWindowController.swift
└── AnnotateManager.swift
```

## Key Patterns

### 1. Coordinate Transformation
All annotations stored in IMAGE coordinates. Display uses `displayScale`.

```swift
// CanvasDrawingView.swift:100-135
private func displayToImage(_ point: CGPoint) -> CGPoint {
  return CGPoint(x: point.x / displayScale, y: point.y / displayScale)
}

private func imageToDisplay(_ point: CGPoint) -> CGPoint {
  return CGPoint(x: point.x * displayScale, y: point.y * displayScale)
}
```

### 2. Scale Calculation
```swift
// AnnotateCanvasView.swift:41-43
let scaleX = availableWidth / logicalCanvasWidth
let scaleY = availableHeight / logicalCanvasHeight
let scale = min(scaleX, scaleY, 1.0)
```

### 3. Text Already Partially Implemented
- `AnnotationType.text(String)` exists
- `AnnotationToolType.text` with icon "textformat", shortcut "t"
- `createTextAnnotation(at:)` in CanvasDrawingView:314-327
- `drawText()` in AnnotationRenderer:166-174
- `editingTextAnnotationId` state property exists

### 4. Selection/Drag Pattern
- Single-click selects via `selectAnnotation(at:)`
- Drag updates bounds via `updateAnnotationBounds(id:bounds:)`
- Selection handles drawn via `drawSelectionHandles()`

### 5. Export Flow
- `renderFinalImage()` creates NSImage at full resolution
- Annotations offset by padding via `offsetAnnotation(_:by:)`
- No scale transform needed - draws at 1:1 image coords

## Missing for Text Feature

1. **No double-click detection** for edit mode
2. **No SwiftUI text input overlay** when editing
3. **No sidebar section** for text styling (font size, color)
4. **Text rendering** doesn't handle background fill
5. **Bounds not auto-sized** to text content
