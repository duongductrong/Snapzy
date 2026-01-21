# Phase 01: Double-Click & Edit Mode

**Parent Plan:** [plan.md](./plan.md)
**Date:** 2026-01-16
**Priority:** High
**Status:** Pending
**Review Status:** Pending

## Overview

Add double-click detection to enter text edit mode. Single-click selects text annotation, double-click triggers inline editing.

## Dependencies

- None (first phase)

## Key Insights

- `event.clickCount` provides click count in NSView
- State already has `editingTextAnnotationId: UUID?` for tracking
- Must distinguish text annotations from other types for double-click behavior

## Requirements

1. Detect double-click on text annotations
2. Set `editingTextAnnotationId` when double-clicking text
3. Clear `editingTextAnnotationId` when clicking elsewhere
4. Single-click still selects (existing behavior)

## Architecture

```
mouseDown(event)
  └── clickCount == 2?
        ├── Yes: Check if hit text annotation
        │         └── Set editingTextAnnotationId
        └── No: Existing selection logic
```

## Related Code Files

| File | Purpose |
|------|---------|
| `CanvasDrawingView.swift:139-185` | mouseDown handler |
| `AnnotateState.swift:120` | editingTextAnnotationId property |

## Implementation Steps

### Step 1: Add double-click detection in mouseDown

```swift
// CanvasDrawingView.swift - modify mouseDown
override func mouseDown(with event: NSEvent) {
  let displayPoint = convert(event.locationInWindow, from: nil)
  let imagePoint = displayToImage(displayPoint)

  // Handle double-click on text annotations
  if event.clickCount == 2 {
    if let annotation = hitTestAnnotation(at: imagePoint),
       case .text = annotation.type {
      Task { @MainActor in
        state.editingTextAnnotationId = annotation.id
        state.selectedAnnotationId = annotation.id
      }
      return
    }
  }

  // Clear editing mode when clicking elsewhere
  if state.editingTextAnnotationId != nil {
    Task { @MainActor in
      state.editingTextAnnotationId = nil
    }
  }

  // ... existing mouseDown logic
}
```

### Step 2: Add hitTestAnnotation helper

```swift
// CanvasDrawingView.swift - add helper method
private func hitTestAnnotation(at point: CGPoint) -> AnnotationItem? {
  for annotation in state.annotations.reversed() {
    if annotation.bounds.contains(point) {
      return annotation
    }
  }
  return nil
}
```

### Step 3: Update text tool click behavior

Current `createTextAnnotation` enters edit mode immediately. Keep this for new text, but ensure it works with overlay system (Phase 02).

## Todo List

- [ ] Add double-click detection in mouseDown
- [ ] Add hitTestAnnotation helper method
- [ ] Clear editingTextAnnotationId on outside click
- [ ] Test single-click still selects properly
- [ ] Test double-click enters edit mode

## Success Criteria

- [ ] Double-click on text annotation sets `editingTextAnnotationId`
- [ ] Single-click on text annotation only selects (no edit mode)
- [ ] Click outside text clears `editingTextAnnotationId`
- [ ] Creating new text annotation enters edit mode

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Double-click timing conflicts with drag | Medium | Check clickCount before drag logic |
| Edit mode state not cleared properly | Low | Clear on any non-text click |

## Security Considerations

None - UI interaction only.

## Next Steps

After completing this phase, proceed to [Phase 02: Text Editing Overlay](./phase-02-text-editing-overlay.md) to add the actual TextField for editing.
