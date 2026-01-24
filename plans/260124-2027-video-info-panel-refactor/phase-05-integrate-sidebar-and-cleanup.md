# Phase 05: Integrate Sidebar and Cleanup

## Context

- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** Phase 04 (sidebar created)
- **Docs:** VideoEditorMainView.swift

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-24 |
| Description | Integrate VideoDetailsSidebarView into main view, remove VideoInfoPanel |
| Priority | High |
| Implementation Status | Pending |
| Review Status | Not Started |

## Key Insights

- VideoEditorMainView has existing sidebar pattern for ZoomSettingsPopover (lines 67-78)
- Video details sidebar should appear on LEFT side (info button is left)
- Zoom settings sidebar on RIGHT side (current behavior)
- VideoInfoPanel usage at lines 55-59 needs removal

## Requirements

1. Add VideoDetailsSidebarView to left side of content area
2. Show/hide based on isVideoInfoSidebarVisible state
3. Remove VideoInfoPanel from layout
4. Delete VideoInfoPanel.swift file
5. Maintain proper dividers between sections

## Architecture

```
VideoEditorMainView
  VStack
    VideoEditorToolbarView
    Divider
    HStack
      [IF isVideoInfoSidebarVisible] VideoDetailsSidebarView + Divider  // NEW LEFT
      VStack (main content)
        ZoomableVideoPlayerSection
        VideoControlsView
        VideoTimelineView
        // VideoInfoPanel REMOVED
        Spacer
      [IF selectedZoomId] Divider + ZoomSettingsPopover  // EXISTING RIGHT
```

## Related Code Files

| File | Purpose |
|------|---------|
| `ClaudeShot/Features/VideoEditor/Views/VideoEditorMainView.swift` | Integrate sidebar, remove panel |
| `ClaudeShot/Features/VideoEditor/Views/VideoInfoPanel.swift` | DELETE |
| `ClaudeShot/Features/VideoEditor/Views/VideoDetailsSidebarView.swift` | Already created |

## Implementation Steps

### VideoEditorMainView.swift

1. Remove VideoInfoPanel usage (lines 55-59):

```swift
// DELETE these lines:
// Info panel
VideoInfoPanel(state: state)
  .padding(.horizontal, 16)
  .padding(.top, 12)
  .padding(.bottom, 12)
```

2. Modify HStack content area (starting line 38). Add left sidebar before main VStack:

```swift
HStack(spacing: 0) {
  // Video details sidebar (left side)
  if state.isVideoInfoSidebarVisible {
    VideoDetailsSidebarView(state: state)
      .frame(width: 280)
      .frame(maxHeight: .infinity, alignment: .top)

    Divider()
  }

  // Main editor content
  VStack(spacing: 0) {
    // ... existing content minus VideoInfoPanel
  }
  .frame(maxWidth: .infinity, maxHeight: .infinity)

  // Zoom settings sidebar (right side) - existing
  if state.selectedZoomId != nil {
    // ... existing code
  }
}
```

3. Add animation for sidebar transitions (optional but nice):

```swift
.animation(.easeInOut(duration: 0.2), value: state.isVideoInfoSidebarVisible)
```

### Delete VideoInfoPanel.swift

Remove file from project.

## Todo

- [ ] Remove VideoInfoPanel from VideoEditorMainView
- [ ] Add VideoDetailsSidebarView to left of content HStack
- [ ] Add conditional rendering based on state
- [ ] Add Divider between sidebar and content
- [ ] Add transition animation
- [ ] Delete VideoInfoPanel.swift
- [ ] Remove from Xcode project
- [ ] Build and test

## Success Criteria

- VideoInfoPanel removed completely
- Left sidebar appears/hides with info button
- Right sidebar (zoom settings) still works
- No build errors
- Smooth transition animation

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Build errors from missing import | Low | Low | Check all references |
| Layout issues with both sidebars | Medium | Medium | Test narrow window |

## Security Considerations

None - UI restructuring only.

## Next Steps

Plan complete. Ready for implementation.

---

## Unresolved Questions

1. Should video details sidebar close when zoom settings opens? (Current plan: independent)
2. Maximum combined sidebar width for narrow windows?
3. Frame rate and bitrate - worth adding async AVAsset loading? (Deferred for simplicity)
