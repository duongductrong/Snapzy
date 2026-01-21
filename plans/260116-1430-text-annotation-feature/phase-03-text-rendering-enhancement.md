# Phase 03: Text Rendering Enhancement

**Parent Plan:** [plan.md](./plan.md)
**Date:** 2026-01-16
**Priority:** Medium
**Status:** Pending
**Review Status:** Pending

## Overview

Enhance text rendering to support background fill, improve visual appearance, and auto-size bounds based on text content.

## Dependencies

- [Phase 02: Text Editing Overlay](./phase-02-text-editing-overlay.md)

## Key Insights

- Current `drawText` is minimal - just draws text at origin
- Need background rectangle for readability
- Bounds should auto-size when text content changes
- Font rendering should match TextField appearance

## Requirements

1. Optional background fill behind text
2. Proper text padding within bounds
3. Auto-size bounds when text changes
4. Support different font sizes
5. Hide annotation when being edited (overlay shows instead)

## Architecture

```
drawText(content, bounds, properties)
  ├── Draw background fill (if fillColor != .clear)
  ├── Calculate text position with padding
  └── Draw text with attributes
```

## Related Code Files

| File | Purpose |
|------|---------|
| `AnnotationRenderer.swift:166-174` | Current drawText implementation |
| `AnnotationItem.swift:45-65` | AnnotationProperties with fontSize |
| `AnnotateState.swift:196-200` | updateAnnotationText method |

## Implementation Steps

### Step 1: Enhance drawText in AnnotationRenderer

```swift
// AnnotationRenderer.swift - replace drawText method
private func drawText(_ content: String, in bounds: CGRect, properties: AnnotationProperties) {
  let padding: CGFloat = 4

  // Draw background if fillColor is set
  if properties.fillColor != .clear {
    context.setFillColor(NSColor(properties.fillColor).cgColor)
    let bgRect = bounds.insetBy(dx: -padding, dy: -padding)
    context.fill(bgRect)
  }

  // Draw text
  let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: properties.fontSize, weight: .regular),
    .foregroundColor: NSColor(properties.strokeColor)
  ]

  let text = content as NSString
  let textPoint = CGPoint(
    x: bounds.origin.x,
    y: bounds.origin.y
  )

  // Use NSStringDrawingContext for proper rendering
  text.draw(at: textPoint, withAttributes: attributes)
}
```

### Step 2: Add bounds auto-sizing to AnnotateState

```swift
// AnnotateState.swift - add method
func updateAnnotationTextAndBounds(id: UUID, text: String) {
  guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }

  let properties = annotations[index].properties
  let newBounds = calculateTextBounds(
    text: text,
    fontSize: properties.fontSize,
    origin: annotations[index].bounds.origin
  )

  annotations[index].type = .text(text)
  annotations[index].bounds = newBounds
}

private func calculateTextBounds(text: String, fontSize: CGFloat, origin: CGPoint) -> CGRect {
  let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: fontSize)
  ]
  let displayText = text.isEmpty ? "Text" : text
  let size = (displayText as NSString).size(withAttributes: attributes)

  let padding: CGFloat = 4
  return CGRect(
    x: origin.x,
    y: origin.y,
    width: size.width + padding * 2,
    height: size.height + padding * 2
  )
}
```

### Step 3: Skip rendering when editing

```swift
// AnnotationRenderer.swift - modify draw method
func draw(_ annotation: AnnotationItem, isEditing: Bool = false) {
  // Skip text rendering if being edited (overlay handles display)
  if case .text = annotation.type, isEditing {
    return
  }

  // ... existing draw logic
}
```

### Step 4: Pass editing state to renderer

```swift
// CanvasDrawingView.swift - modify draw loop
for annotation in state.annotations {
  let isEditing = annotation.id == state.editingTextAnnotationId
  renderer.draw(annotation, isEditing: isEditing)

  if annotation.id == state.selectedAnnotationId {
    drawSelectionHandles(for: annotation.bounds, in: context)
  }
}
```

## Todo List

- [ ] Enhance drawText with background fill support
- [ ] Add text padding for better appearance
- [ ] Implement calculateTextBounds helper
- [ ] Add updateAnnotationTextAndBounds method
- [ ] Skip rendering text when being edited
- [ ] Test background colors (clear, solid)
- [ ] Test various font sizes
- [ ] Verify export renders correctly

## Success Criteria

- [ ] Text with fillColor shows background rectangle
- [ ] Text properly padded within bounds
- [ ] Bounds auto-resize when text content changes
- [ ] Different font sizes render correctly
- [ ] Edited text not double-rendered (overlay + canvas)
- [ ] Export produces correct output

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Font metrics differ between contexts | Medium | Use same NSFont for calculation and rendering |
| Bounds calculation off by padding | Low | Test with various text lengths |

## Security Considerations

None - rendering only.

## Next Steps

After completing this phase, proceed to [Phase 04: Sidebar Text Styling](./phase-04-sidebar-text-styling.md) to add UI controls.
