# Recording Region Overlay Plan

## Overview
- **Created**: 2026-01-17
- **Status**: Planning
- **Priority**: High (UX improvement)

## Problem Statement
When user selects area for screen recording, the selection overlay disappears immediately after selection completes. User loses visual reference of what region they're recording.

## Solution
Create a persistent `RecordingRegionOverlayWindow` that shows the dimmed overlay with highlighted selection rectangle throughout the recording session.

## Implementation Phases

| Phase | Description | Status | Progress |
|-------|-------------|--------|----------|
| [Phase 01](./phase-01-recording-region-overlay-window.md) | Create RecordingRegionOverlayWindow | Completed | 100% |

## Key Files

### To Create
- `ZapShot/Features/Recording/RecordingRegionOverlayWindow.swift`

### To Modify
- `ZapShot/Features/Recording/RecordingCoordinator.swift`

### Reference Files
- `ZapShot/Core/AreaSelectionWindow.swift` - Existing overlay pattern
- `ZapShot/Features/Recording/RecordingToolbarWindow.swift` - Window management pattern

## Architecture

```
User selects area
       ↓
AreaSelectionController closes (existing behavior)
       ↓
RecordingCoordinator.showToolbar(for: rect)
       ↓
┌─────────────────────────────────────────┐
│  NEW: Create RecordingRegionOverlayWindow│
│  - Shows dimmed overlay                  │
│  - Highlights selected rect              │
│  - ignoresMouseEvents = true             │
└─────────────────────────────────────────┘
       ↓
RecordingToolbarWindow shows (existing)
       ↓
Recording starts → overlay stays visible
       ↓
Recording stops → cleanup() closes overlay
```

## Success Criteria
1. Selected region remains visually highlighted during recording
2. Overlay does not interfere with mouse/keyboard input
3. Overlay does not appear in the recording itself
4. Multi-monitor support works correctly
5. Overlay closes when recording stops or cancels

## Estimated Complexity
- Single phase implementation
- ~150 lines new code
- ~10 lines modified code
