# Phase 02: Implement Drag-to-Move Functionality

## Context
- **Parent Plan**: [plan.md](./plan.md)
- **Dependencies**: [Phase 01](./phase-01-enable-mouse-interaction.md)

## Overview
- **Date**: 2026-01-17
- **Description**: Allow user to drag selected region by clicking inside and moving mouse
- **Priority**: High
- **Implementation Status**: ⬜ Pending
- **Review Status**: ⬜ Pending

## Key Insights
- Click inside `highlightRect` initiates drag mode
- Track offset between click point and rect origin for smooth dragging
- Clamp rect position to screen bounds (current screen, not all screens)
- Update both overlay view and toolbar position in real-time

## Requirements
1. Detect mouseDown inside `highlightRect`
2. Calculate drag offset for smooth movement
3. Update `highlightRect` on `mouseDragged`
4. Clamp to current screen bounds
5. Notify coordinator to update `selectedRect` and toolbar position
6. Show move cursor when hovering inside rect

## Architecture
```
User clicks inside rect
  ↓
RecordingRegionOverlayView.mouseDown
  ├── Calculate dragOffset = clickPoint - highlightRect.origin
  └── Set isDragging = true
  ↓
User drags mouse
  ↓
RecordingRegionOverlayView.mouseDragged
  ├── newOrigin = currentPoint - dragOffset
  ├── Clamp newOrigin to screen bounds
  ├── Update local highlightRect
  └── Call delegate?.overlay(_:didMoveRegionTo:)
  ↓
RecordingCoordinator receives callback
  ├── Update selectedRect
  ├── Update all overlay windows' highlightRect
  └── Call toolbarWindow?.updateAnchorRect()
  ↓
User releases mouse
  ↓
RecordingRegionOverlayView.mouseUp
  └── Call delegate?.overlayDidFinishMoving()
```

## Related Code Files
| File | Lines | Purpose |
|------|-------|---------|
| `RecordingRegionOverlayWindow.swift` | 43-46 | `updateHighlightRect()` already exists |
| `RecordingToolbarWindow.swift` | 123-126 | `updateAnchorRect()` already exists |
| `RecordingCoordinator.swift` | 21, 65-71 | `selectedRect`, `showRegionOverlay()` |

## Implementation Steps

### Step 1: Add drag state to RecordingRegionOverlayView
```swift
private var isDragging = false
private var dragOffset: CGPoint = .zero
private var screenBounds: CGRect = .zero // Set from window init
```

### Step 2: Implement mouseDown for drag detection
```swift
override func mouseDown(with event: NSEvent) {
  guard isInteractionEnabled else { return }
  let point = convert(event.locationInWindow, from: nil)
  let localHighlight = convertHighlightToLocal()

  if localHighlight.contains(point) {
    isDragging = true
    dragOffset = CGPoint(x: point.x - localHighlight.origin.x,
                         y: point.y - localHighlight.origin.y)
  } else {
    // Outside click → Phase 03
    delegate?.overlayDidRequestReselection()
  }
}
```

### Step 3: Implement mouseDragged
```swift
override func mouseDragged(with event: NSEvent) {
  guard isDragging, isInteractionEnabled else { return }
  let point = convert(event.locationInWindow, from: nil)

  var newOrigin = CGPoint(x: point.x - dragOffset.x,
                          y: point.y - dragOffset.y)

  // Clamp to screen bounds
  newOrigin.x = max(0, min(newOrigin.x, bounds.width - highlightRect.width))
  newOrigin.y = max(0, min(newOrigin.y, bounds.height - highlightRect.height))

  // Convert back to screen coordinates and notify
  let screenOrigin = convertToScreen(newOrigin)
  let newRect = CGRect(origin: screenOrigin, size: highlightRect.size)

  delegate?.overlay(window as! RecordingRegionOverlayWindow, didMoveRegionTo: newRect)
}
```

### Step 4: Implement mouseUp
```swift
override func mouseUp(with event: NSEvent) {
  guard isDragging else { return }
  isDragging = false
  delegate?.overlayDidFinishMoving(window as! RecordingRegionOverlayWindow)
}
```

### Step 5: Add cursor feedback
```swift
override func mouseMoved(with event: NSEvent) {
  guard isInteractionEnabled else { return }
  let point = convert(event.locationInWindow, from: nil)
  let localHighlight = convertHighlightToLocal()

  if localHighlight.contains(point) {
    NSCursor.openHand.set()
  } else {
    NSCursor.crosshair.set()
  }
}
```

### Step 6: Update RecordingCoordinator
```swift
func updateSelectedRect(_ rect: CGRect) {
  selectedRect = rect
  for overlay in regionOverlayWindows {
    overlay.updateHighlightRect(rect)
  }
  toolbarWindow?.updateAnchorRect(rect)
}
```

## Todo List
- [ ] Add drag state properties to view
- [ ] Add `convertHighlightToLocal()` helper
- [ ] Implement `mouseDown` with inside/outside detection
- [ ] Implement `mouseDragged` with clamping
- [ ] Implement `mouseUp` to end drag
- [ ] Add cursor feedback on `mouseMoved`
- [ ] Add `updateSelectedRect()` to coordinator
- [ ] Implement delegate callback handling
- [ ] Test drag on single monitor
- [ ] Test drag boundary clamping

## Success Criteria
- [ ] Clicking inside rect initiates drag
- [ ] Rect follows mouse smoothly during drag
- [ ] Rect cannot be dragged outside screen bounds
- [ ] Toolbar moves with rect
- [ ] All overlay windows update simultaneously
- [ ] Move cursor shows when hovering inside rect

## Risk Assessment
- **Medium**: Coordinate conversion between view/screen coords
- **Mitigation**: Use existing `convertToScreenCoordinates` pattern from AreaSelectionWindow

## Security Considerations
- None

## Next Steps
→ [Phase 03: Re-selection](./phase-03-reselection.md)
