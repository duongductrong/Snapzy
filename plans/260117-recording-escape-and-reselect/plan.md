# Plan: Recording Escape & Immediate Reselection

**Date:** 260117
**Status:** Planning

## Overview

Two improvements to the screen recording preparation phase:

1. **Escape to Cancel**: Allow users to press Escape key to cancel recording during the prepare phase (after area selection, before recording starts)
2. **Immediate Reselection**: When clicking outside the selected area, immediately start new selection on mouseDown+drag instead of requiring 2 clicks

## Current Behavior Analysis

### Escape Key
- `AreaSelectionController` already handles Escape during area selection (lines 60-75)
- `RecordingCoordinator` has no Escape key handling during prepare phase
- `RecordingRegionOverlayWindow` does not monitor keyboard events

### Click Outside Reselection
- `RecordingRegionOverlayView.mouseDown()` (line 160-177): When clicking outside highlight rect, calls `overlayDidRequestReselection`
- `RecordingCoordinator.restartAreaSelection()` (line 194-226): Closes overlays, starts new `AreaSelectionController`
- **Issue**: User clicks outside → closes current overlay → opens new selection overlay → user must click+drag again
- **Goal**: Click outside should immediately start drag selection without releasing mouse

## Implementation Plan

### Task 1: Escape Key to Cancel Recording Preparation

**File:** `RecordingCoordinator.swift`

Add escape key monitoring when toolbar is shown, remove when cleanup.

**Changes:**
1. Add properties for escape monitors
2. In `showToolbar()`: Add local and global escape key monitors that call `cancel()`
3. In `cleanup()`: Remove escape monitors

### Task 2: Immediate Reselection on Click Outside

**File:** `RecordingRegionOverlayView.swift`

When user clicks outside the selected area, instead of just notifying delegate, capture the click position and start a new selection drag immediately.

**Changes:**
1. Add new delegate method: `overlayDidStartNewSelection(_ overlay:, startPoint:)`
2. In `mouseDown()`: When clicking outside, store start point and enter "new selection" mode
3. In `mouseDragged()`: If in new selection mode, update selection rect
4. In `mouseUp()`: Complete new selection, notify delegate with new rect

**File:** `RecordingCoordinator.swift`

Handle the new selection flow without closing/reopening windows.

**Changes:**
1. Add delegate method implementation for `overlayDidStartNewSelection`
2. Update overlays in-place with new rect during drag
3. Update toolbar position when selection completes

## Files to Modify

1. `ZapShot/Features/Recording/RecordingCoordinator.swift`
2. `ZapShot/Features/Recording/RecordingRegionOverlayWindow.swift`

## Acceptance Criteria

- [ ] Pressing Escape during recording preparation phase cancels and closes all windows
- [ ] Clicking outside selected area and dragging immediately creates new selection
- [ ] No double-click required for reselection
- [ ] Existing drag-to-move functionality preserved when clicking inside selection
- [ ] Format selection preserved during reselection
