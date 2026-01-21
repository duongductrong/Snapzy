# Phase 04: UX Enhancements

## Context Links
- [Main Plan](./plan.md)
- [Previous: Phase 03](./phase-03-property-binding.md)
- Related: `ZapShot/Features/Annotate/Canvas/CanvasDrawingView.swift`
- Related: `ZapShot/Features/Annotate/State/AnnotateState.swift`

## Overview

| Field | Value |
|-------|-------|
| Date | 260116 |
| Description | Keyboard shortcuts, cursor feedback, and edge case handling |
| Priority | Medium |
| Status | Pending |
| Effort | 1 day |

## Key Insights

1. **Partial keyboard support exists** - Delete key (51, 117) and Escape (53) already handled
2. **No arrow key nudging** - Selected annotations cannot be moved with arrow keys
3. **No cursor feedback** - Cursor stays default regardless of hover state
4. **Tool shortcuts defined** - Each tool has `shortcut` property but not wired to canvas
5. **Minimum size exists** - 20pt minimum enforced in `calculateResizedBounds`

## Requirements

### Functional
- [ ] Arrow keys nudge selected annotation by 1pt (10pt with Shift)
- [ ] Escape key deselects current annotation
- [ ] V key switches to selection tool
- [ ] Cursor changes to move cursor when hovering selected annotation
- [ ] Cursor changes to resize cursor when hovering resize handles
- [ ] Prevent accidental annotation creation when clicking empty space in selection mode

### Non-Functional
- [ ] Keyboard shortcuts work when canvas has focus
- [ ] Cursor changes are immediate (no delay)
- [ ] Nudge respects image coordinate system

## Architecture

### Keyboard Shortcut Map

| Key | Code | Action | Condition |
|-----|------|--------|-----------|
| Delete | 51 | Delete selected | Has selection, not editing text |
| Fwd Delete | 117 | Delete selected | Has selection, not editing text |
| Escape | 53 | Deselect / exit edit | Any |
| Arrow Up | 126 | Nudge up | Has selection |
| Arrow Down | 125 | Nudge down | Has selection |
| Arrow Left | 123 | Nudge left | Has selection |
| Arrow Right | 124 | Nudge right | Has selection |
| V | 9 | Selection tool | Any |

### Cursor Types

| Context | Cursor |
|---------|--------|
| Default | Arrow |
| Over selected annotation | Open hand |
| Dragging annotation | Closed hand |
| Over resize handle | Resize cursor (directional) |
| Resizing | Resize cursor |

## Related Code Files

| File | Change Type |
|------|-------------|
| `Canvas/CanvasDrawingView.swift` | Add keyboard handling, cursor management |
| `State/AnnotateState.swift` | Add nudgeAnnotation method |

## Implementation Steps

### Step 1: Add Nudge Method to AnnotateState

**File**: `ZapShot/Features/Annotate/State/AnnotateState.swift`

Add after `deleteSelectedAnnotation()`:

```swift
/// Nudge selected annotation by delta
func nudgeSelectedAnnotation(dx: CGFloat, dy: CGFloat) {
  guard let selectedId = selectedAnnotationId,
        let index = annotations.firstIndex(where: { $0.id == selectedId }) else { return }

  saveState()
  annotations[index].bounds.origin.x += dx
  annotations[index].bounds.origin.y += dy

  // Also update embedded points for arrows/lines
  switch annotations[index].type {
  case .arrow(let start, let end):
    annotations[index].type = .arrow(
      start: CGPoint(x: start.x + dx, y: start.y + dy),
      end: CGPoint(x: end.x + dx, y: end.y + dy)
    )
  case .line(let start, let end):
    annotations[index].type = .line(
      start: CGPoint(x: start.x + dx, y: start.y + dy),
      end: CGPoint(x: end.x + dx, y: end.y + dy)
    )
  case .path(let points):
    annotations[index].type = .path(points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
  case .highlight(let points):
    annotations[index].type = .highlight(points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
  default:
    break
  }
}

/// Deselect current annotation
func deselectAnnotation() {
  selectedAnnotationId = nil
  editingTextAnnotationId = nil
}
```

### Step 2: Enhance keyDown Handler

**File**: `ZapShot/Features/Annotate/Canvas/CanvasDrawingView.swift`

Replace `keyDown(with:)` method:

```swift
override func keyDown(with event: NSEvent) {
  let shift = event.modifierFlags.contains(.shift)
  let nudgeAmount: CGFloat = shift ? 10 : 1

  switch event.keyCode {
  case 51, 117: // Delete, Forward Delete
    if state.selectedAnnotationId != nil && state.editingTextAnnotationId == nil {
      Task { @MainActor in
        state.deleteSelectedAnnotation()
      }
      needsDisplay = true
    }

  case 53: // Escape
    Task { @MainActor in
      state.deselectAnnotation()
    }
    needsDisplay = true

  case 126: // Arrow Up
    if state.selectedAnnotationId != nil && state.editingTextAnnotationId == nil {
      Task { @MainActor in
        state.nudgeSelectedAnnotation(dx: 0, dy: nudgeAmount)
      }
      needsDisplay = true
    }

  case 125: // Arrow Down
    if state.selectedAnnotationId != nil && state.editingTextAnnotationId == nil {
      Task { @MainActor in
        state.nudgeSelectedAnnotation(dx: 0, dy: -nudgeAmount)
      }
      needsDisplay = true
    }

  case 123: // Arrow Left
    if state.selectedAnnotationId != nil && state.editingTextAnnotationId == nil {
      Task { @MainActor in
        state.nudgeSelectedAnnotation(dx: -nudgeAmount, dy: 0)
      }
      needsDisplay = true
    }

  case 124: // Arrow Right
    if state.selectedAnnotationId != nil && state.editingTextAnnotationId == nil {
      Task { @MainActor in
        state.nudgeSelectedAnnotation(dx: nudgeAmount, dy: 0)
      }
      needsDisplay = true
    }

  case 9: // V key
    Task { @MainActor in
      state.selectedTool = .selection
    }

  default:
    super.keyDown(with: event)
  }
}
```

### Step 3: Add Cursor Management

**File**: `ZapShot/Features/Annotate/Canvas/CanvasDrawingView.swift`

Add tracking area in `setupView()`:

```swift
private func setupView() {
  wantsLayer = true
  layer?.backgroundColor = NSColor.clear.cgColor

  // Enable mouse tracking for cursor updates
  let trackingArea = NSTrackingArea(
    rect: .zero,
    options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved],
    owner: self,
    userInfo: nil
  )
  addTrackingArea(trackingArea)
}
```

Add `mouseMoved` handler:

```swift
override func mouseMoved(with event: NSEvent) {
  updateCursor(for: event)
}

private func updateCursor(for event: NSEvent) {
  let displayPoint = convert(event.locationInWindow, from: nil)
  let imagePoint = displayToImage(displayPoint)

  // Check resize handles first
  if let selectedId = state.selectedAnnotationId,
     let annotation = state.annotations.first(where: { $0.id == selectedId }) {
    let displayBounds = imageToDisplay(annotation.bounds)
    if let handle = hitTestHandle(at: displayPoint, for: displayBounds) {
      setCursorForHandle(handle)
      return
    }

    // Check if over selected annotation body
    if annotation.containsPoint(imagePoint) {
      NSCursor.openHand.set()
      return
    }
  }

  // Check if over any annotation in selection mode
  if state.selectedTool == .selection {
    if hitTestAnnotation(at: imagePoint) != nil {
      NSCursor.pointingHand.set()
      return
    }
  }

  // Default cursor
  NSCursor.arrow.set()
}

private func setCursorForHandle(_ handle: ResizeHandle) {
  switch handle {
  case .topLeft, .bottomRight:
    NSCursor(image: NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right",
                            accessibilityDescription: nil)!,
             hotSpot: NSPoint(x: 8, y: 8)).set()
  case .topRight, .bottomLeft:
    NSCursor(image: NSImage(systemSymbolName: "arrow.up.right.and.arrow.down.left",
                            accessibilityDescription: nil)!,
             hotSpot: NSPoint(x: 8, y: 8)).set()
  case .top, .bottom:
    NSCursor.resizeUpDown.set()
  case .left, .right:
    NSCursor.resizeLeftRight.set()
  }
}
```

Update `mouseDown` to change cursor while dragging:

```swift
// In mouseDown, after setting isDraggingAnnotation = true:
NSCursor.closedHand.set()
```

Update `mouseUp` to reset cursor:

```swift
// At end of mouseUp:
updateCursor(for: event)
```

### Step 4: Prevent Accidental Creation in Selection Mode

**File**: `ZapShot/Features/Annotate/Canvas/CanvasDrawingView.swift`

In `mouseDown`, add check before starting draw:

```swift
// Start drawing for other tools (in image coordinates)
// Prevent accidental creation when in selection mode clicking empty space
if state.selectedTool == .selection {
  // Clicked empty space - just deselect
  Task { @MainActor in
    state.deselectAnnotation()
  }
  needsDisplay = true
  return
}

isDrawing = true
// ... rest of drawing logic
```

## Todo List

- [ ] Add `nudgeSelectedAnnotation` method to AnnotateState
- [ ] Add `deselectAnnotation` method to AnnotateState
- [ ] Enhance `keyDown` with arrow key handling
- [ ] Add V key shortcut for selection tool
- [ ] Add tracking area for mouse movement
- [ ] Implement `mouseMoved` cursor updates
- [ ] Implement `setCursorForHandle` helper
- [ ] Update cursor during drag operations
- [ ] Prevent creation in selection mode empty-click
- [ ] Test arrow key nudging (1pt and 10pt with Shift)
- [ ] Test Escape deselects annotation
- [ ] Test cursor changes on hover
- [ ] Test no accidental creation in selection mode

## Success Criteria

1. Arrow keys move selected annotation by 1pt
2. Shift+Arrow moves by 10pt
3. Escape deselects current annotation
4. V key activates selection tool
5. Cursor shows open hand over selected annotation
6. Cursor shows closed hand while dragging
7. Cursor shows resize arrows over handles
8. Clicking empty space in selection mode deselects (no creation)

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Key codes differ across keyboards | Low | Low | Standard US layout codes used |
| Cursor image loading fails | Low | Medium | Fallback to system cursors |
| Tracking area memory | Low | Low | Single area, auto-managed |

## Security Considerations

None - input handling with no external data.

## Next Steps

After completing this phase:
1. Feature complete for Cursor Mode (Select Tool)
2. Consider future enhancements:
   - Multi-selection (Shift+click)
   - Z-index management (bring to front/send to back)
   - Copy/paste annotations
   - Duplicate annotation (Cmd+D)
