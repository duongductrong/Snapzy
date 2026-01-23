# Plan: Zoom UI Fixes

**Date:** 2026-01-23
**Status:** In Progress
**Issues:** 3

---

## Issues Summary

| # | Issue | Root Cause | Fix |
|---|-------|------------|-----|
| 1 | Inconsistent colors | Inline RGB, no design system | Define `ZoomColors` constants |
| 2 | Drag doesn't move block | Translation is cumulative but segment is stale | Track `@State var dragStartTime` |
| 3 | Can't resize duration | Same stale segment issue | Track `@State var initialSegment` |

---

## Implementation

### Step 1: Add Color Constants

Create consistent zoom colors in a centralized location.

### Step 2: Fix Drag Gestures

- Add `@State var dragStartTime: TimeInterval?`
- Add `@State var dragStartDuration: TimeInterval?`
- On drag start: capture initial values
- On drag change: calculate new position from initial + delta
- On drag end: clear state

### Step 3: Improve Visual Feedback

- Add visual feedback during drag (slight scale/opacity change)
- Better resize handle visibility on hover

---

## Files to Modify

1. `ZoomBlockView.swift` - Fix gestures, improve colors
2. `ZoomTimelineTrack.swift` - Update handlers if needed
