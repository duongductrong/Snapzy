# Phase 01: Add Keyboard Event Handling to AreaSelectionOverlayView

## Context
- **Parent Plan**: [plan.md](./plan.md)
- **Dependencies**: None
- **Related Docs**: macOS AppKit NSView keyboard handling

## Overview
| Field | Value |
|-------|-------|
| Date | 2026-01-19 |
| Description | Enable ESC key cancellation in area selection overlay before mouse interaction |
| Priority | Medium |
| Implementation Status | Pending |
| Review Status | Pending |

## Key Insights
1. `AreaSelectionOverlayView` currently handles mouse events but not keyboard events
2. View must override `acceptsFirstResponder` to receive keyboard focus
3. Controller already sets up event monitors (lines 60-75) but these may fail due to focus timing
4. Adding direct `keyDown` handling provides reliable fallback

## Requirements
- ESC key (keyCode 53) cancels selection at any point during overlay display
- Must work before any mouse interaction occurs
- Must not interfere with existing mouse-based selection flow
- Must not break right-click cancel functionality

## Architecture
```
AreaSelectionController
    ├── localEscapeMonitor (existing - backup)
    ├── globalEscapeMonitor (existing - backup)
    └── AreaSelectionWindow[]
            └── AreaSelectionOverlayView
                    ├── acceptsFirstResponder → true (NEW)
                    └── keyDown(with:) → check ESC (NEW)
```

## Related Code Files
| File | Purpose |
|------|---------|
| `ZapShot/Core/AreaSelectionWindow.swift` | Contains AreaSelectionOverlayView class (lines 229-418) |

## Implementation Steps

### Step 1: Add `acceptsFirstResponder` override
**Location**: `AreaSelectionOverlayView` class, after line 276 (after `acceptsFirstMouse`)

```swift
override var acceptsFirstResponder: Bool {
  return true
}
```

### Step 2: Add `keyDown(with:)` handler
**Location**: `AreaSelectionOverlayView` class, after the new `acceptsFirstResponder` (in Mouse Events section or nearby)

```swift
override func keyDown(with event: NSEvent) {
  if event.keyCode == 53 {  // Escape key
    delegate?.overlayViewDidCancel(self)
  } else {
    super.keyDown(with: event)
  }
}
```

## Todo List
- [ ] Add `acceptsFirstResponder` property override returning `true`
- [ ] Add `keyDown(with:)` method to handle ESC key
- [ ] Build and verify no compiler errors
- [ ] Test ESC before mouse interaction
- [ ] Test ESC during drag
- [ ] Test normal capture flow still works
- [ ] Test right-click cancel still works

## Success Criteria
1. Pressing ESC immediately after overlay appears cancels selection
2. Pressing ESC during mouse drag cancels selection
3. Existing capture workflow unchanged
4. No regressions in right-click cancel

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Key events not received | Low | Medium | Event monitors at controller level remain as backup |
| Interferes with other key handling | Very Low | Low | Only handle ESC, pass others to super |

## Security Considerations
- None - no user input validation, no external data, no network calls

## Next Steps
After implementation:
1. Manual testing per success criteria
2. Mark phase complete in plan.md
