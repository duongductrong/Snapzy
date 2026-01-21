# Phase 02: Text Editing Overlay

**Parent Plan:** [plan.md](./plan.md)
**Date:** 2026-01-16
**Priority:** High
**Status:** Pending
**Review Status:** Pending

## Overview

Add SwiftUI TextField overlay for inline text editing. Overlay positions over the text annotation using coordinate transformation to match image space.

## Dependencies

- [Phase 01: Double-Click & Edit Mode](./phase-01-double-click-edit-mode.md)

## Key Insights

- Overlay must transform image coords → display coords
- Use @FocusState for automatic focus management
- Enter commits, Escape cancels
- Overlay positioned in AnnotateCanvasView (SwiftUI layer)

## Requirements

1. TextField overlay appears when `editingTextAnnotationId` is set
2. Overlay positioned correctly over text annotation
3. Position updates when padding/zoom changes
4. Enter key commits text, Escape cancels
5. Clicking outside commits and exits edit mode

## Architecture

```
AnnotateCanvasView
  └── ZStack
        ├── backgroundLayer
        ├── imageLayer
        ├── CanvasDrawingView (handles mouse events)
        └── TextEditOverlay (conditional, when editing)
              └── TextField (positioned at annotation bounds)
```

## Related Code Files

| File | Purpose |
|------|---------|
| `AnnotateCanvasView.swift:31-75` | Canvas content with scale calculation |
| `AnnotateState.swift:119-120` | selectedAnnotationId, editingTextAnnotationId |

## Implementation Steps

### Step 1: Create TextEditOverlay view

```swift
// New file or add to AnnotateCanvasView.swift

struct TextEditOverlay: View {
  @ObservedObject var state: AnnotateState
  let scale: CGFloat
  let imageOffset: CGPoint
  let containerSize: CGSize

  @State private var editingText: String = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    if let editingId = state.editingTextAnnotationId,
       let annotation = state.annotations.first(where: { $0.id == editingId }),
       case .text(let currentText) = annotation.type {

      let displayBounds = calculateDisplayBounds(annotation.bounds)

      TextField("", text: $editingText)
        .textFieldStyle(.plain)
        .font(.system(size: annotation.properties.fontSize * scale))
        .foregroundColor(Color(annotation.properties.strokeColor))
        .focused($isFocused)
        .frame(width: max(displayBounds.width, 50), height: displayBounds.height)
        .position(
          x: displayBounds.midX,
          y: displayBounds.midY
        )
        .onAppear {
          editingText = currentText
          isFocused = true
        }
        .onSubmit {
          commitEdit(id: editingId)
        }
        .onExitCommand {
          cancelEdit()
        }
    }
  }

  private func calculateDisplayBounds(_ imageBounds: CGRect) -> CGRect {
    // Convert image coords to display coords
    // Account for container centering and image offset
    let centerX = containerSize.width / 2
    let centerY = containerSize.height / 2

    let imgWidth = state.imageWidth * scale
    let imgHeight = state.imageHeight * scale

    // Image top-left in container coords
    let imgOriginX = centerX - imgWidth / 2 + imageOffset.x
    let imgOriginY = centerY - imgHeight / 2 + imageOffset.y

    return CGRect(
      x: imgOriginX + imageBounds.origin.x * scale,
      y: imgOriginY + imageBounds.origin.y * scale,
      width: imageBounds.width * scale,
      height: imageBounds.height * scale
    )
  }

  private func commitEdit(id: UUID) {
    state.saveState()
    state.updateAnnotationText(id: id, text: editingText)
    state.editingTextAnnotationId = nil
  }

  private func cancelEdit() {
    state.editingTextAnnotationId = nil
  }
}
```

### Step 2: Integrate overlay into AnnotateCanvasView

```swift
// AnnotateCanvasView.swift - modify canvasContent
private func canvasContent(in containerSize: CGSize) -> some View {
  // ... existing scale calculations ...

  return ZStack {
    backgroundLayer(width: bgWidth, height: bgHeight)

    imageLayer(width: imgWidth, height: imgHeight)
      .offset(x: offset.x, y: offset.y)

    CanvasDrawingView(state: state, displayScale: scale)
      .frame(width: imgWidth, height: imgHeight)
      .offset(x: offset.x, y: offset.y)

    // Text editing overlay
    TextEditOverlay(
      state: state,
      scale: scale,
      imageOffset: offset,
      containerSize: CGSize(width: bgWidth, height: bgHeight)
    )
  }
  .scaleEffect(state.zoomLevel)
}
```

### Step 3: Hide text in renderer when editing

```swift
// AnnotationRenderer.swift - modify drawText
private func drawText(_ content: String, in bounds: CGRect, properties: AnnotationProperties) {
  // Skip drawing if this annotation is being edited (overlay handles display)
  // Note: Need to pass editing state or check differently

  let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: properties.fontSize),
    .foregroundColor: NSColor(properties.strokeColor)
  ]
  let text = content as NSString
  text.draw(at: bounds.origin, withAttributes: attributes)
}
```

## Todo List

- [ ] Create TextEditOverlay view component
- [ ] Implement coordinate conversion for overlay positioning
- [ ] Add @FocusState for automatic focus
- [ ] Handle Enter (commit) and Escape (cancel)
- [ ] Integrate overlay into AnnotateCanvasView
- [ ] Test overlay positioning with different padding values
- [ ] Test overlay updates when zoom changes

## Success Criteria

- [ ] TextField appears over text annotation when editing
- [ ] TextField is properly positioned matching annotation bounds
- [ ] Typing updates the text content
- [ ] Enter key commits changes
- [ ] Escape key cancels without saving
- [ ] Position updates correctly when padding changes

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Coordinate conversion incorrect | High | Test with various padding/zoom values |
| Focus not gained automatically | Medium | Use onAppear + @FocusState |
| Y-axis inversion issues | Medium | SwiftUI vs AppKit Y direction |

## Security Considerations

None - local text input only.

## Next Steps

After completing this phase, proceed to [Phase 03: Text Rendering Enhancement](./phase-03-text-rendering-enhancement.md) to improve text display.
