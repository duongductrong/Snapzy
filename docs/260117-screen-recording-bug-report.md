# Screen Recording Bug Report

**Date:** 2026-01-17
**Severity:** Critical
**Status:** Root Cause Identified

## Executive Summary

Screen recording flow (⌘⇧5) fails at area selection completion. Area selection starts but never completes - toolbar never appears. Root cause: `AreaSelectionController` instance deallocated immediately after creation in recording flow.

## Issue Description

**Expected Flow:**
1. User presses ⌘⇧5
2. Area selection overlay appears
3. User drags to select area
4. Selection completes, toolbar appears below selected area
5. User clicks Record button

**Actual Behavior:**
- Area selection starts correctly
- User can drag selection
- Selection NEVER completes on mouseUp
- Toolbar NEVER appears
- Flow stuck in selection mode

## Root Cause Analysis

### Critical Bug Location

**File:** `ZapShot/Core/ScreenCaptureViewModel.swift`
**Lines:** 260-272

```swift
func startRecordingFlow() {
    // ... permission checks ...

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      let controller = AreaSelectionController()  // ⚠️ BUG HERE
      controller.startSelection(mode: .recording) { rect, mode in
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        guard let rect = rect else { return }

        Task { @MainActor in
          RecordingCoordinator.shared.showToolbar(for: rect)
        }
      }
    }
}
```

### Why It Fails

1. **Local Variable Scope Issue:**
   - `controller` created as local variable inside closure
   - After closure returns, `controller` goes out of scope
   - Swift ARC immediately deallocates `AreaSelectionController`
   - Selection windows close, delegates invalidated
   - Completion callback never fires

2. **Contrast with Working Screenshot Flow:**

**File:** `ZapShot/Core/ScreenCaptureViewModel.swift`
**Lines:** 179-230 (captureArea method)

```swift
func captureArea() {
    // Prevent multiple area captures
    if areaSelectionController != nil {
      return
    }

    // ... window hiding ...

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      guard let self = self else { return }

      // ✅ CORRECT: Store as instance variable
      self.areaSelectionController = AreaSelectionController()
      self.areaSelectionController?.startSelection { [weak self] rect in
        guard let self = self else { return }

        // Show main window again
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        // ... rest of flow ...

        self.areaSelectionController = nil  // Cleanup after completion
      }
    }
}
```

### Key Difference

| Screenshot Flow | Recording Flow |
|----------------|----------------|
| `self.areaSelectionController = AreaSelectionController()` | `let controller = AreaSelectionController()` |
| Stored as instance variable | Local variable |
| Retained until completion | Deallocated immediately |
| ✅ Works | ❌ Broken |

## Evidence Chain

1. **Line 52:** `private var areaSelectionController: AreaSelectionController?` exists for screenshot flow
2. **Line 195:** Screenshot flow assigns to instance var: `self.areaSelectionController = AreaSelectionController()`
3. **Line 261:** Recording flow creates local var: `let controller = AreaSelectionController()`
4. **No instance variable storage for recording flow controller**

## Fix Required

### Option 1: Reuse Existing Instance Variable (Recommended)

Store recording controller in same instance var used by screenshot flow:

```swift
func startRecordingFlow() {
    guard hasPermission else {
      requestPermission()
      return
    }

    // Check if already recording
    guard !RecordingCoordinator.shared.isActive else { return }

    // Prevent multiple selections
    guard areaSelectionController == nil else { return }

    // Hide main window
    NSApp.hide(nil)

    // Small delay to ensure window is hidden
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      guard let self = self else { return }

      // ✅ FIX: Store as instance variable
      self.areaSelectionController = AreaSelectionController()
      self.areaSelectionController?.startSelection(mode: .recording) { [weak self] rect, mode in
        guard let self = self else { return }

        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        guard let rect = rect else {
          // Cleanup on cancel
          self.areaSelectionController = nil
          return
        }

        Task { @MainActor in
          RecordingCoordinator.shared.showToolbar(for: rect)
        }

        // Cleanup after completion
        self.areaSelectionController = nil
      }
    }
}
```

### Option 2: Separate Instance Variable

Create dedicated variable for recording selection:

```swift
// Add to class properties
private var recordingSelectionController: AreaSelectionController?

func startRecordingFlow() {
    // ... existing checks ...

    guard recordingSelectionController == nil else { return }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      guard let self = self else { return }

      self.recordingSelectionController = AreaSelectionController()
      self.recordingSelectionController?.startSelection(mode: .recording) { [weak self] rect, mode in
        guard let self = self else { return }

        // ... rest of flow ...

        self.recordingSelectionController = nil
      }
    }
}
```

## Recommendation

**Use Option 1** - reuse existing `areaSelectionController` variable because:
- Prevents simultaneous screenshot/recording selections
- Follows existing pattern
- No new properties needed
- Consistent with screenshot flow

## Implementation Priority

**Priority:** P0 - Critical
**Effort:** 5 minutes
**Risk:** Low - direct fix, pattern already proven

## Testing Checklist

After fix:
- [ ] ⌘⇧5 triggers area selection
- [ ] Selection completes on mouseUp
- [ ] Toolbar appears below selected area
- [ ] Record button starts recording
- [ ] Escape cancels selection properly
- [ ] Cannot start multiple selections simultaneously
- [ ] Screenshot flow (⌘⇧4) still works
- [ ] No conflicts between screenshot/recording flows

## Additional Notes

**Memory Management Pattern:**
- Screenshot flow correctly manages controller lifecycle
- Recording flow missed this pattern during implementation
- Both flows should follow identical memory management

**No Other Issues Found:**
- `RecordingCoordinator.showToolbar()` implementation correct
- `RecordingToolbarWindow` positioning logic correct
- `AreaSelectionController` delegate callbacks work correctly
- `SelectionMode.recording` properly defined and used

## Unresolved Questions

None - root cause clearly identified, fix straightforward.
