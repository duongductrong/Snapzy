# Phase 5: Integration with RecordingCoordinator

- **Date**: 2026-02-09
- **Priority**: High
- **Status**: Pending

## Overview
Wire everything together in RecordingCoordinator. Manage lifecycle of annotation state, toolbar window, and overlay window. Handle transitions between recording states.

## Requirements
1. Create annotation state when recording starts
2. Show/hide annotation toolbar based on toggle
3. Show/hide overlay window based on toggle
4. Pass overlay window to ScreenRecordingManager for `exceptingWindows`
5. Clean up all annotation windows on stop/cancel/delete
6. Update overlay position when recording rect changes

## Implementation Steps

### 1. Add properties to RecordingCoordinator
```swift
private var annotationState: RecordingAnnotationState?
private var annotationToolbarWindow: RecordingAnnotationToolbarWindow?
private var annotationOverlayWindow: RecordingAnnotationOverlayWindow?
private var annotationCancellable: AnyCancellable?
```

### 2. Initialize on recording start
In `startRecording()`:
- Create `RecordingAnnotationState`
- Pass to toolbar window (for status bar toggle button)
- Observe `isAnnotationEnabled` to show/hide annotation windows

### 3. Show/hide annotation windows
```swift
annotationCancellable = annotationState?.$isAnnotationEnabled
  .sink { [weak self] enabled in
    if enabled {
      self?.showAnnotationWindows()
    } else {
      self?.hideAnnotationWindows()
    }
  }
```

### 4. Update ScreenRecordingManager
- Add `annotationOverlayWindowID: CGWindowID?` parameter to `prepareRecording()`
- Or: Add method `updateExceptedWindows(_:)` to add overlay after recording starts
- Challenge: SCStream filter can't be changed after recording starts
- **Solution**: Create overlay window BEFORE starting recording, pass windowID to prepareRecording

### 5. Handle recording rect changes
- When overlay resizes (area mode resize), update overlay window frame

### 6. Cleanup
In `cleanup()`:
- Close annotation toolbar window
- Close annotation overlay window
- Nil out annotation state
- Cancel Combine subscription

## Modified Files
- `Snapzy/Features/Recording/RecordingCoordinator.swift` (add annotation lifecycle)
- `Snapzy/Core/ScreenRecordingManager.swift` (add exceptingWindows for overlay)
- `Snapzy/Features/Recording/RecordingToolbarWindow.swift` (pass annotation state)

## Flow Diagram
```
User clicks Record
  → Create RecordingAnnotationState
  → Create annotation overlay window (hidden, positioned over rect)
  → Pass overlay windowID to ScreenRecordingManager
  → Start recording (overlay included in capture via exceptingWindows)
  → Show status bar with annotation toggle

User enables annotations
  → Show annotation toolbar (snapped to corner)
  → Set overlay ignoresMouseEvents = false
  → User draws annotations (visible in video!)

User disables annotations
  → Hide annotation toolbar
  → Set overlay ignoresMouseEvents = true (pass-through)
  → Annotations remain visible in video

User stops recording
  → Stop capture
  → Close overlay + toolbar
  → Post-capture handler
```

## Success Criteria
- Full lifecycle works: start → annotate → stop
- Annotations visible in exported video
- No crashes on rapid toggle
- Clean cleanup on all exit paths (stop/cancel/delete/restart)
- Overlay correctly included in ScreenCaptureKit capture
