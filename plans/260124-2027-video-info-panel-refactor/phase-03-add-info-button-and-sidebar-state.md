# Phase 03: Add Info Button and Sidebar State

## Context

- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** Phase 02 (resolution in toolbar)
- **Docs:** VideoEditorState.swift, VideoControlsView.swift

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-24 |
| Description | Add state property and info button to toggle video details sidebar |
| Priority | High |
| Implementation Status | Pending |
| Review Status | Not Started |

## Key Insights

- State already has pattern for toggles: `isZoomTrackVisible`, `toggleZoomTrackVisibility()`
- Info button should be LEFT side of toolbar (before play button)
- Use SF Symbol "info.circle" or "info.circle.fill" when active
- Sidebar visibility independent of zoom settings sidebar

## Requirements

1. Add `isVideoInfoSidebarVisible: Bool` to VideoEditorState
2. Add `toggleVideoInfoSidebar()` method
3. Add info button at LEFT of VideoControlsView
4. Button shows filled icon when sidebar visible

## Architecture

```
VideoEditorState
  + @Published var isVideoInfoSidebarVisible: Bool = false
  + func toggleVideoInfoSidebar()
```

## Related Code Files

| File | Purpose |
|------|---------|
| `ClaudeShot/Features/VideoEditor/State/VideoEditorState.swift` | Add state property |
| `ClaudeShot/Features/VideoEditor/Views/VideoControlsView.swift` | Add info button |

## Implementation Steps

### VideoEditorState.swift

1. After line 67 (`isZoomTrackVisible`), add:

```swift
@Published var isVideoInfoSidebarVisible: Bool = false
```

2. After `toggleZoomTrackVisibility()` (line 536-538), add:

```swift
/// Toggle video info sidebar visibility
func toggleVideoInfoSidebar() {
  isVideoInfoSidebarVisible.toggle()
}
```

### VideoControlsView.swift

1. At start of HStack (line 16), before play button, add:

```swift
// Info button
Button(action: { state.toggleVideoInfoSidebar() }) {
  Image(systemName: state.isVideoInfoSidebarVisible ? "info.circle.fill" : "info.circle")
    .font(.system(size: 16))
    .foregroundColor(state.isVideoInfoSidebarVisible ? ZoomColors.primary : .primary)
    .frame(width: 32, height: 32)
    .background(state.isVideoInfoSidebarVisible ? ZoomColors.primary.opacity(0.15) : Color.white.opacity(0.1))
    .clipShape(Circle())
}
.buttonStyle(.plain)
.keyboardShortcut("i", modifiers: [])
.help(state.isVideoInfoSidebarVisible ? "Hide Video Info (I)" : "Show Video Info (I)")
```

## Todo

- [ ] Add isVideoInfoSidebarVisible property to state
- [ ] Add toggleVideoInfoSidebar method
- [ ] Add info button to VideoControlsView
- [ ] Add keyboard shortcut "I"
- [ ] Test toggle behavior

## Success Criteria

- State property toggles correctly
- Info button appears left of play button
- Visual feedback (filled icon, accent background) when active
- Keyboard shortcut works

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Keyboard conflict | Low | Low | "I" not commonly used |
| State not persisted | Low | Low | Acceptable - resets on window close |

## Security Considerations

None - UI state toggle only.

## Next Steps

Proceed to Phase 04: Create Video Details Sidebar
