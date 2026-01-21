# Scout Report: Annotate Feature Files

## Summary
Quick codebase search for Cursor Mode implementation.

## Files Found

### State Management
| File | Description |
|------|-------------|
| `State/AnnotateState.swift` | Central state management for annotation window |
| `State/AnnotationItem.swift` | Annotation item definitions (needs verification) |

### Canvas/Rendering
| File | Description |
|------|-------------|
| `Canvas/AnnotationRenderer.swift` | Renders annotations on canvas |
| `Canvas/CanvasDrawingView.swift` | Handles drawing on canvas |

### Views
| File | Description |
|------|-------------|
| `Views/AnnotateMainView.swift` | Main annotation view |
| `Views/AnnotateToolbarView.swift` | Toolbar with annotation tools |
| `Views/AnnotateCanvasView.swift` | Canvas view container |
| `Views/AnnotateSidebarView.swift` | Main sidebar view |
| `Views/AnnotateSidebarSections.swift` | Sidebar section definitions |
| `Views/AnnotateSidebarComponents.swift` | Sidebar components |
| `Views/AnnotateBottomBarView.swift` | Bottom bar view |
| `Views/TextEditOverlay.swift` | Text editing overlay |
| `Views/TextStylingSection.swift` | Text styling controls |

## Key Files for Cursor Mode
1. **AnnotateState.swift** - Add selection state, cursor mode toggle
2. **AnnotationItem.swift** - Add hit-testing, bounding box logic
3. **CanvasDrawingView.swift** - Handle selection gestures
4. **AnnotationRenderer.swift** - Render selection handles
5. **AnnotateToolbarView.swift** - Add cursor mode button
6. **AnnotateSidebarView.swift** - Bind to selected item properties

## Unresolved Questions
- Exact structure of annotation item models (Arrow, Circle, Text)
- Current gesture handling implementation details
