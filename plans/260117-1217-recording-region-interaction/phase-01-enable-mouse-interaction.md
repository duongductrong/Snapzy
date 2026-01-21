# Phase 01: Enable Mouse Interaction on Overlay

## Context
- **Parent Plan**: [plan.md](./plan.md)
- **Dependencies**: None (first phase)

## Overview
- **Date**: 2026-01-17
- **Description**: Enable mouse event handling on `RecordingRegionOverlayWindow` during pre-record phase
- **Priority**: High (blocking for Phase 02 & 03)
- **Implementation Status**: ⬜ Pending
- **Review Status**: ⬜ Pending

## Key Insights
- Currently `ignoresMouseEvents = true` (line 37) blocks all interaction
- Need conditional mouse handling: enabled during pre-record, disabled during recording
- Must add delegate protocol to communicate events to `RecordingCoordinator`

## Requirements
1. Toggle `ignoresMouseEvents` based on recording state
2. Add mouse event handlers to `RecordingRegionOverlayView`
3. Define delegate protocol for overlay-to-coordinator communication
4. Detect if click is inside or outside `highlightRect`

## Architecture
```
RecordingRegionOverlayWindow
├── ignoresMouseEvents = false (pre-record) / true (recording)
└── RecordingRegionOverlayView
    ├── mouseDown → detect inside/outside highlightRect
    ├── mouseDragged → delegate?.didDragRegion()
    └── mouseUp → delegate?.didFinishDrag()

RecordingRegionOverlayDelegate (new protocol)
├── overlayDidRequestReselection()
├── overlay(_:didMoveRegionTo:)
└── overlayDidFinishMoving()
```

## Related Code Files
| File | Lines | Purpose |
|------|-------|---------|
| `RecordingRegionOverlayWindow.swift` | 1-117 | Overlay window + view |
| `RecordingCoordinator.swift` | 1-177 | Coordinator (will adopt delegate) |

## Implementation Steps

### Step 1: Add delegate protocol (RecordingRegionOverlayWindow.swift)
```swift
protocol RecordingRegionOverlayDelegate: AnyObject {
  func overlayDidRequestReselection(_ overlay: RecordingRegionOverlayWindow)
  func overlay(_ overlay: RecordingRegionOverlayWindow, didMoveRegionTo rect: CGRect)
  func overlayDidFinishMoving(_ overlay: RecordingRegionOverlayWindow)
}
```

### Step 2: Add delegate property to window
```swift
weak var interactionDelegate: RecordingRegionOverlayDelegate?
```

### Step 3: Add method to toggle mouse events
```swift
func setInteractionEnabled(_ enabled: Bool) {
  ignoresMouseEvents = !enabled
  overlayView.isInteractionEnabled = enabled
}
```

### Step 4: Add mouse handling to RecordingRegionOverlayView
- Add `isInteractionEnabled` property
- Override `mouseDown(with:)`, `mouseDragged(with:)`, `mouseUp(with:)`
- Add tracking area for cursor changes

### Step 5: Wire delegate in RecordingCoordinator
- Set delegate when creating overlay windows
- Call `setInteractionEnabled(true)` in pre-record, `false` when recording starts

## Todo List
- [ ] Define `RecordingRegionOverlayDelegate` protocol
- [ ] Add delegate property to `RecordingRegionOverlayWindow`
- [ ] Add `setInteractionEnabled(_:)` method
- [ ] Add `isInteractionEnabled` to `RecordingRegionOverlayView`
- [ ] Add mouse event overrides to view
- [ ] Add tracking area for cursor feedback
- [ ] Wire delegate in `RecordingCoordinator`
- [ ] Call `setInteractionEnabled(false)` when recording starts

## Success Criteria
- [ ] Mouse events received by overlay view during pre-record
- [ ] Mouse events ignored during active recording
- [ ] Delegate methods called correctly
- [ ] No compilation errors

## Risk Assessment
- **Low**: Standard AppKit mouse handling
- **Mitigation**: Test on multi-monitor setup

## Security Considerations
- None (UI-only changes)

## Next Steps
→ [Phase 02: Drag-to-Move](./phase-02-drag-to-move.md)
