# QuickAccess Card Drag Direction Implementation Plan

**Date:** 2026-01-18
**Status:** Completed
**Priority:** Medium

## Description

Improve QuickAccess card drag behavior with directional intent detection. Swipe right dismisses card, other directions trigger external drag-drop to apps.

## Current State

- `QuickAccessCardView.swift` uses `.onDrag` modifier for external drag-drop
- Dismiss requires clicking X button on hover overlay
- No gesture-based dismissal exists
- `dragDropEnabled` setting controls drag-drop feature globally

## Goal

- Swipe RIGHT (>50pt, within +/-45 degrees) dismisses card with animation
- Drag OTHER directions initiates external drag-drop to apps
- Visual feedback during swipe (offset, opacity, red tint)
- Maintain existing double-tap and hover behaviors

## Phases

| # | Phase | Status | Link |
|---|-------|--------|------|
| 1 | Drag Gesture Implementation | Completed | [phase-01](./phase-01-drag-gesture-implementation.md) |

## Success Criteria

- [x] Swipe right >50pt within 45 degree angle dismisses card
- [x] Non-right drags trigger external drag-drop
- [x] Visual feedback shows dismiss intent (offset, opacity, red tint)
- [x] Spring animation on release
- [x] Existing hover overlay and double-tap behaviors preserved
- [x] No regression in drag-drop to external apps

## Files Affected

- `ZapShot/Features/QuickAccess/QuickAccessCardView.swift` (modified)
- `ZapShot/Features/QuickAccess/QuickAccessItemDragSupport.swift` (new - extracted)
- `ZapShot/Features/QuickAccess/ViewConditionalExtension.swift` (new - extracted)
- `ZapShot/Features/QuickAccess/QuickAccessManager.swift` (use existing `removeScreenshot`)

## Technical Approach

Replace `.onDrag` with `DragGesture` that detects direction:
1. Track drag offset in state
2. Calculate angle to determine intent
3. Swipe right triggers dismiss via `removeScreenshot`
4. Other directions programmatically trigger `NSDraggingSession`

## Dependencies

- None - self-contained UI enhancement

## Risks

- Conflict between gesture and existing `.onDrag` behavior
- Programmatic drag session may require AppKit bridging
