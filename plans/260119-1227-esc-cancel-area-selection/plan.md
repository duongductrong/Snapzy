# ESC Key Cancel During Area Selection Overlay

## Overview
| Field | Value |
|-------|-------|
| Created | 2026-01-19 |
| Status | Completed |
| Priority | Medium |
| Complexity | Low |

## Problem Statement
User cannot cancel area selection with ESC key before starting a mouse drag. Currently ESC only works after initiating selection. Expected: ESC cancels immediately when overlay appears.

## Root Cause
`AreaSelectionOverlayView` lacks proper keyboard event handling:
1. Missing `acceptsFirstResponder` override (view can't receive key events)
2. Missing `keyDown(with:)` handler as fallback to event monitors
3. Event monitors at controller level may miss events due to window focus timing

## Solution
Add keyboard event handling directly to `AreaSelectionOverlayView` class.

## Implementation Phases

| Phase | Description | Status | Progress |
|-------|-------------|--------|----------|
| [Phase 01](./phase-01-keyboard-handling.md) | Add keyboard event handling to AreaSelectionOverlayView | Completed | 100% |

## Files Affected
- `ZapShot/Core/AreaSelectionWindow.swift`

## Testing Checklist
- [ ] ESC works immediately when overlay appears (no mouse interaction)
- [ ] ESC works during selection drag
- [ ] Right-click cancel still works
- [ ] Normal capture flow works (select area, release mouse, capture completes)
- [ ] Recording area selection also supports ESC cancel

## Risk Assessment
- **Low Risk**: Changes isolated to single view class
- **No Breaking Changes**: Existing functionality preserved (event monitors remain as backup)
