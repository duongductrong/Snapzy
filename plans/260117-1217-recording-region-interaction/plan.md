# Recording Region Interaction Improvement

## Overview
- **Date**: 2026-01-17
- **Priority**: Medium
- **Status**: Planning

Enhance `RecordingRegionOverlayWindow` to support interactive region manipulation during pre-record phase:
1. Drag-to-move selected area within viewport bounds
2. Re-select area by clicking outside current selection

## Current Architecture
```
RecordingCoordinator (singleton)
├── RecordingToolbarWindow (floating, pre-record/recording UI)
├── RecordingRegionOverlayWindow[] (per-screen dimmed overlay)
│   └── RecordingRegionOverlayView (draws highlight rect)
└── ScreenRecordingManager (actual capture)
```

## Implementation Phases

| Phase | Description | Status | File |
|-------|-------------|--------|------|
| 01 | Enable mouse interaction on overlay | ⬜ Pending | [phase-01](./phase-01-enable-mouse-interaction.md) |
| 02 | Implement drag-to-move functionality | ⬜ Pending | [phase-02](./phase-02-drag-to-move.md) |
| 03 | Implement re-selection on outside click | ⬜ Pending | [phase-03](./phase-03-reselection.md) |

## Files to Modify
- `ZapShot/Features/Recording/RecordingRegionOverlayWindow.swift`
- `ZapShot/Features/Recording/RecordingCoordinator.swift`

## Dependencies
- Existing `AreaSelectionController` for re-selection flow
- `RecordingToolbarWindow.updateAnchorRect()` for toolbar repositioning

## Success Criteria
- [ ] User can drag selected region by clicking inside and moving
- [ ] Region stays within screen bounds during drag
- [ ] Toolbar follows region during drag
- [ ] Clicking outside region triggers new area selection
- [ ] Selected format preserved during re-selection
- [ ] No interaction during active recording (only pre-record)

## Risk Assessment
- **Low**: Changes isolated to Recording feature
- **Multi-monitor**: Must handle cross-screen boundary clamping
