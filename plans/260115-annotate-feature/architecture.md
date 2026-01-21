# Architecture

## Directory Structure

```
ZapShot/Features/Annotate/
├── Window/
│   ├── AnnotateWindowController.swift    # NSWindowController for annotation window
│   └── AnnotateWindow.swift              # NSWindow subclass with dark mode styling
├── Views/
│   ├── AnnotateMainView.swift            # Main SwiftUI container view
│   ├── AnnotateToolbarView.swift         # Top toolbar with all tools
│   ├── AnnotateSidebarView.swift         # Left sidebar for background settings
│   ├── AnnotateCanvasView.swift          # Center canvas for image + annotations
│   └── AnnotateBottomBarView.swift       # Bottom bar with zoom/actions
├── Canvas/
│   ├── CanvasView.swift                  # NSView for drawing (Core Graphics)
│   ├── CanvasRenderer.swift              # Renders annotations on image
│   └── AnnotationLayer.swift             # Layer containing all annotations
├── Tools/
│   ├── AnnotationTool.swift              # Protocol + enum for tools
│   ├── SelectionTool.swift               # Select/move annotations
│   ├── PencilTool.swift                  # Freehand drawing
│   ├── ShapeTool.swift                   # Rectangle, Circle, Arrow, Line
│   ├── TextTool.swift                    # Text annotations
│   ├── HighlighterTool.swift             # Highlighter strokes
│   ├── BlurTool.swift                    # Blur/pixelate regions
│   ├── CounterTool.swift                 # Numbered markers
│   └── CropTool.swift                    # Image cropping
├── Background/
│   ├── BackgroundStyle.swift             # Enum for background types
│   ├── BackgroundPresets.swift           # Predefined gradients/colors
│   └── BackgroundRenderer.swift          # Apply background to image
├── State/
│   ├── AnnotateState.swift               # ObservableObject for state
│   ├── AnnotationItem.swift              # Model for single annotation
│   ├── UndoRedoManager.swift             # Undo/redo stack
│   └── ToolSettings.swift                # Tool-specific settings (color, size)
├── Export/
│   ├── AnnotateExporter.swift            # Save/export functionality
│   └── ShareManager.swift                # Share sheet integration
└── AnnotateManager.swift                 # Singleton to open annotation window
```

## Dependencies

### Internal (Apple Frameworks)
- **SwiftUI** - UI components, state management
- **AppKit** - NSWindow, NSWindowController, NSView, NSImage
- **Core Graphics** - Drawing, image manipulation
- **Combine** - Reactive state management
- **UniformTypeIdentifiers** - File type handling for export

### External
None required.

## File Modifications

| File | Changes |
|------|---------|
| `FloatingCardView.swift` | Add double-tap gesture, blur on hover, border, text buttons |
| `CardActionButton.swift` | Replace with `CardTextButton.swift` or modify for text style |

## Component Communication

```
FloatingCardView
    │ (double-tap)
    ▼
AnnotateManager.shared.openAnnotation(for: item)
    │
    ▼
AnnotateWindowController
    │ (creates)
    ▼
AnnotateWindow + AnnotateMainView
    │
    ├── AnnotateState (shared across all views)
    │
    ├── AnnotateToolbarView ──► Tool selection, settings
    │
    ├── AnnotateSidebarView ──► Background configuration
    │
    ├── AnnotateCanvasView ──► Drawing surface
    │       │
    │       └── CanvasView (NSViewRepresentable)
    │               │
    │               └── Current Tool handles mouse events
    │
    └── AnnotateBottomBarView ──► Zoom, actions, export
```
