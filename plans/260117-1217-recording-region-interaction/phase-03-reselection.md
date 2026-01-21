# Phase 03: Implement Re-selection on Outside Click

## Context
- **Parent Plan**: [plan.md](./plan.md)
- **Dependencies**: [Phase 01](./phase-01-enable-mouse-interaction.md), [Phase 02](./phase-02-drag-to-move.md)

## Overview
- **Date**: 2026-01-17
- **Description**: When user clicks outside the selected region, dismiss current overlays and restart area selection
- **Priority**: Medium
- **Implementation Status**: ⬜ Pending
- **Review Status**: ⬜ Pending

## Key Insights
- Clicking outside should behave like pressing Cmd+Shift+5 again
- Must preserve user's selected video format from toolbar
- Reuse existing `AreaSelectionController` for new selection
- After new selection, show toolbar for new rect

## Requirements
1. Detect mouseDown outside `highlightRect`
2. Close current overlay windows and toolbar
3. Start new area selection via `AreaSelectionController`
4. On completion, show toolbar with preserved format
5. Handle cancellation (Escape key) gracefully

## Architecture
```
User clicks outside rect
  ↓
RecordingRegionOverlayView.mouseDown
  └── delegate?.overlayDidRequestReselection()
  ↓
RecordingCoordinator.overlayDidRequestReselection()
  ├── Save currentFormat = toolbarWindow?.selectedFormat
  ├── Close all regionOverlayWindows
  ├── Close toolbarWindow
  ├── Clear selectedRect
  └── Call restartAreaSelection()
  ↓
restartAreaSelection()
  ├── Create new AreaSelectionController
  └── startSelection(mode: .recording) { rect, _ in
        if let rect = rect {
          showToolbar(for: rect)
          toolbarWindow?.selectedFormat = savedFormat
        } else {
          cleanup() // User cancelled
        }
      }
```

## Related Code Files
| File | Lines | Purpose |
|------|-------|---------|
| `AreaSelectionController.swift` | 47-76 | `startSelection(mode:completion:)` |
| `RecordingCoordinator.swift` | 29-54 | `showToolbar(for:)` |
| `RecordingCoordinator.swift` | 56-61 | `cancel()` |
| `RecordingCoordinator.swift` | 165-176 | `cleanup()` |

## Implementation Steps

### Step 1: Handle outside click in mouseDown (already in Phase 02)
```swift
// In RecordingRegionOverlayView.mouseDown
if !localHighlight.contains(point) {
  delegate?.overlayDidRequestReselection(window as! RecordingRegionOverlayWindow)
}
```

### Step 2: Add areaSelectionController property to RecordingCoordinator
```swift
private var areaSelectionController: AreaSelectionController?
```

### Step 3: Implement delegate method in RecordingCoordinator
```swift
extension RecordingCoordinator: RecordingRegionOverlayDelegate {
  func overlayDidRequestReselection(_ overlay: RecordingRegionOverlayWindow) {
    restartAreaSelection()
  }

  // ... other delegate methods
}
```

### Step 4: Implement restartAreaSelection()
```swift
private func restartAreaSelection() {
  // Save current format before cleanup
  let savedFormat = toolbarWindow?.selectedFormat ?? .mov

  // Close current overlays (but don't reset isActive)
  for overlay in regionOverlayWindows {
    overlay.close()
  }
  regionOverlayWindows.removeAll()

  toolbarWindow?.close()
  toolbarWindow = nil
  selectedRect = nil

  // Start new selection
  areaSelectionController = AreaSelectionController()
  areaSelectionController?.startSelection(mode: .recording) { [weak self] rect, _ in
    guard let self = self else { return }
    self.areaSelectionController = nil

    if let rect = rect {
      // Show toolbar for new rect
      self.selectedRect = rect
      self.toolbarWindow = RecordingToolbarWindow(anchorRect: rect)
      self.toolbarWindow?.selectedFormat = savedFormat
      self.toolbarWindow?.onRecord = { [weak self] in self?.startRecording() }
      self.toolbarWindow?.onCancel = { [weak self] in self?.cancel() }
      self.toolbarWindow?.onStop = { [weak self] in self?.stopRecording() }
      self.showRegionOverlay(for: rect)
    } else {
      // User cancelled (Escape)
      self.cleanup()
    }
  }
}
```

### Step 5: Set delegate when creating overlay windows
```swift
private func showRegionOverlay(for rect: CGRect) {
  for screen in NSScreen.screens {
    let overlay = RecordingRegionOverlayWindow(screen: screen, highlightRect: rect)
    overlay.interactionDelegate = self
    overlay.setInteractionEnabled(true)
    overlay.orderFrontRegardless()
    regionOverlayWindows.append(overlay)
  }
}
```

### Step 6: Disable interaction when recording starts
```swift
// In startRecording(), after recorder.startRecording()
for overlay in regionOverlayWindows {
  overlay.hideBorder()
  overlay.setInteractionEnabled(false) // Add this
}
```

## Todo List
- [ ] Add `areaSelectionController` property
- [ ] Implement `overlayDidRequestReselection()` delegate method
- [ ] Implement `restartAreaSelection()` method
- [ ] Update `showRegionOverlay()` to set delegate
- [ ] Update `showRegionOverlay()` to enable interaction
- [ ] Update `startRecording()` to disable interaction
- [ ] Test re-selection flow
- [ ] Test format preservation
- [ ] Test cancellation with Escape

## Success Criteria
- [ ] Clicking outside rect dismisses current selection
- [ ] New area selection starts immediately
- [ ] Previously selected format is preserved
- [ ] New selection shows toolbar correctly
- [ ] Escape during re-selection cancels entire flow
- [ ] Multiple re-selections work correctly

## Risk Assessment
- **Medium**: State management during transition
- **Mitigation**: Clear state before starting new selection, save format first

## Security Considerations
- None

## Next Steps
- Implementation complete after this phase
- Proceed to testing and code review
