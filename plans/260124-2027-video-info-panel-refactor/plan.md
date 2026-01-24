# Video Info Panel Refactor Plan

**Date:** 2026-01-24
**Status:** Planning
**Priority:** Medium

## Objective

Remove VideoInfoPanel bottom bar and redistribute content: resolution to toolbar, full metadata to new sidebar.

## Key Changes

1. Fix hardcoded `.purple` colors to use `ZoomColors.primary` for consistency
2. Add resolution display to VideoControlsView toolbar
3. Add info button (left side) to toggle video details sidebar
4. Create VideoDetailsSidebarView with comprehensive metadata
5. Remove VideoInfoPanel.swift after migration

## Phases

| # | Phase | Status | File |
|---|-------|--------|------|
| 1 | Zoom Colors Consistency | Pending | [phase-01](./phase-01-zoom-colors-consistency.md) |
| 2 | Add Resolution to Toolbar | Pending | [phase-02](./phase-02-add-resolution-to-toolbar.md) |
| 3 | Add Info Button and Sidebar State | Pending | [phase-03](./phase-03-add-info-button-and-sidebar-state.md) |
| 4 | Create Video Details Sidebar | Pending | [phase-04](./phase-04-create-video-details-sidebar.md) |
| 5 | Integrate Sidebar and Cleanup | Pending | [phase-05](./phase-05-integrate-sidebar-and-cleanup.md) |

## Files Affected

- `ClaudeShot/Features/VideoEditor/Views/VideoControlsView.swift` - add resolution, info button, fix colors
- `ClaudeShot/Features/VideoEditor/Views/ExportProgressOverlay.swift` - fix colors
- `ClaudeShot/Features/VideoEditor/State/VideoEditorState.swift` - add sidebar state
- `ClaudeShot/Features/VideoEditor/Views/VideoDetailsSidebarView.swift` - NEW
- `ClaudeShot/Features/VideoEditor/Views/VideoEditorMainView.swift` - integrate sidebar, remove info panel
- `ClaudeShot/Features/VideoEditor/Views/VideoInfoPanel.swift` - DELETE

## Dependencies

- ZoomColors enum in `ZoomBlockView.swift` (lines 12-19)
- AnnotateSidebarView pattern for sidebar styling reference
- Existing `resolutionString` computed property in VideoEditorState

## Architecture Notes

- Follow existing sidebar pattern: ScrollView + VStack + background(controlBackgroundColor)
- Use `@Published var isVideoInfoSidebarVisible: Bool` in state
- Info button toggles sidebar visibility independently of zoom settings sidebar
