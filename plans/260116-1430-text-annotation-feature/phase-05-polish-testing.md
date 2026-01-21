# Phase 05: Polish & Testing

**Parent Plan:** [plan.md](./plan.md)
**Date:** 2026-01-16
**Priority:** Medium
**Status:** Pending
**Review Status:** Pending

## Overview

Final polish, edge case handling, keyboard shortcuts, and comprehensive testing of the text annotation feature.

## Dependencies

- [Phase 04: Sidebar Text Styling](./phase-04-sidebar-text-styling.md)

## Key Insights

- Need delete key support for selected text annotation
- Empty text should show placeholder or be deleted
- Focus transitions between overlay and canvas
- Export must render text correctly at all padding values

## Requirements

1. Delete key removes selected text annotation
2. Empty text handling (placeholder or delete)
3. Keyboard shortcut 'T' activates text tool
4. Proper cursor changes (text cursor when hovering text tool)
5. Comprehensive testing of coordinate sync

## Architecture

```
Polish Areas:
├── Keyboard handling (Delete, T shortcut)
├── Empty text handling
├── Cursor management
├── Edge cases
└── Testing matrix
```

## Related Code Files

| File | Purpose |
|------|---------|
| `CanvasDrawingView.swift` | Keyboard events |
| `AnnotateToolbarView.swift:90-92` | Tool shortcuts |
| `AnnotateExporter.swift` | Export verification |

## Implementation Steps

### Step 1: Add delete key support

```swift
// CanvasDrawingView.swift - add keyDown handler
override func keyDown(with event: NSEvent) {
  switch event.keyCode {
  case 51, 117: // Delete, Forward Delete
    if state.selectedAnnotationId != nil {
      Task { @MainActor in
        state.deleteSelectedAnnotation()
      }
    }
  default:
    super.keyDown(with: event)
  }
}

// Enable key events
override var acceptsFirstResponder: Bool { true }
```

### Step 2: Handle empty text

```swift
// TextEditOverlay - modify commitEdit
private func commitEdit(id: UUID) {
  let trimmedText = editingText.trimmingCharacters(in: .whitespacesAndNewlines)

  if trimmedText.isEmpty {
    // Delete annotation if text is empty
    state.deleteSelectedAnnotation()
  } else {
    state.saveState()
    state.updateAnnotationTextAndBounds(id: id, text: trimmedText)
  }
  state.editingTextAnnotationId = nil
}
```

### Step 3: Improve text creation with auto-focus

```swift
// CanvasDrawingView.swift - modify createTextAnnotation
private func createTextAnnotation(at point: CGPoint) {
  let bounds = CGRect(x: point.x, y: point.y - 24, width: 100, height: 28)
  let properties = AnnotationProperties(
    strokeColor: state.strokeColor,
    fillColor: .clear,
    strokeWidth: state.strokeWidth,
    fontSize: 16,
    fontName: "SF Pro"
  )
  let item = AnnotationItem(type: .text(""), bounds: bounds, properties: properties)
  state.annotations.append(item)
  state.selectedAnnotationId = item.id
  state.editingTextAnnotationId = item.id  // Enter edit mode immediately
}
```

### Step 4: Add cursor management

```swift
// CanvasDrawingView.swift - add cursor updates
override func resetCursorRects() {
  switch state.selectedTool {
  case .text:
    addCursorRect(bounds, cursor: .iBeam)
  case .selection:
    addCursorRect(bounds, cursor: .arrow)
  default:
    addCursorRect(bounds, cursor: .crosshair)
  }
}
```

## Testing Matrix

### Coordinate Sync Tests

| Test | Steps | Expected |
|------|-------|----------|
| Create text, change padding | Create text at (100,100), increase padding to 50 | Text still at (100,100) relative to image |
| Create text, zoom in | Create text, zoom to 200% | Text scales with image, position preserved |
| Create text, change alignment | Create text, change image alignment | Text moves with image |
| Export with padding | Create text, add padding 30, export | Text at correct position in exported image |

### Editing Tests

| Test | Steps | Expected |
|------|-------|----------|
| Double-click edit | Double-click text | TextField appears, focused |
| Type and commit | Type "Hello", press Enter | Text updates, edit mode exits |
| Cancel edit | Type, press Escape | Original text preserved |
| Empty text delete | Clear text, press Enter | Annotation deleted |
| Click outside | While editing, click canvas | Edit committed |

### Styling Tests

| Test | Steps | Expected |
|------|-------|----------|
| Change font size | Select text, adjust slider | Text and bounds resize |
| Change text color | Select text, pick red | Text renders red |
| Add background | Select text, pick yellow | Yellow background appears |
| Remove background | Select text, click "None" | Background removed |

### Edge Cases

| Test | Steps | Expected |
|------|-------|----------|
| Very long text | Type 200+ characters | Bounds expand, no overflow |
| Very small font | Set font size to 12 | Still legible and selectable |
| Multiple text annotations | Create 5+ text items | All render correctly |
| Undo/Redo text edit | Edit text, undo | Previous text restored |

## Todo List

- [ ] Add delete key handler
- [ ] Handle empty text (delete annotation)
- [ ] Add cursor management
- [ ] Verify keyboard shortcut 'T' works
- [ ] Run coordinate sync test matrix
- [ ] Run editing test matrix
- [ ] Run styling test matrix
- [ ] Run edge case tests
- [ ] Verify export output
- [ ] Test with various image sizes
- [ ] Test with Retina display

## Success Criteria

- [ ] All test matrix items pass
- [ ] Delete key removes text annotation
- [ ] Empty text annotations are deleted
- [ ] Cursor changes appropriately for text tool
- [ ] No visual glitches during editing
- [ ] Export produces correct output

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Edge cases cause crashes | High | Comprehensive testing |
| Performance with many annotations | Medium | Test with 20+ items |
| Retina display scaling issues | Medium | Test on Retina Mac |

## Security Considerations

None - local feature only.

## Next Steps

After completing this phase, the text annotation feature is complete. Consider:
- Adding font family picker (future enhancement)
- Adding text alignment options (future enhancement)
- Adding text rotation (future enhancement)
