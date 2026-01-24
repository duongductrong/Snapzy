# Phase 02: Add Resolution to Toolbar

## Context

- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** Phase 01 (color consistency)
- **Docs:** VideoControlsView.swift, VideoEditorState.swift

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-24 |
| Description | Add resolution display to VideoControlsView toolbar |
| Priority | High |
| Implementation Status | Pending |
| Review Status | Not Started |

## Key Insights

- `state.resolutionString` already exists (line 127-130 in VideoEditorState)
- Format: "1920 x 1080" (with multiplication sign)
- Current toolbar layout: Play -> Mute -> Divider -> ZoomControls -> Time -> Spacer -> ZoomCount -> TrimIndicator
- Resolution should be compact, non-intrusive

## Requirements

1. Display resolution string in toolbar
2. Position after time display, before Spacer
3. Use secondary styling (not prominent)
4. Handle loading state (shows "-" when naturalSize not loaded)

## Architecture

Simple UI addition. No state changes needed.

## Related Code Files

| File | Purpose |
|------|---------|
| `ClaudeShot/Features/VideoEditor/Views/VideoControlsView.swift` | Add resolution display |
| `ClaudeShot/Features/VideoEditor/State/VideoEditorState.swift` | resolutionString source |

## Implementation Steps

1. Open VideoControlsView.swift
2. After time display HStack (line 61), before Spacer (line 63)
3. Add resolution display:

```swift
// Resolution indicator
Text(state.resolutionString)
  .font(.system(size: 11))
  .foregroundColor(.secondary)
  .padding(.horizontal, 6)
  .padding(.vertical, 2)
  .background(Color.white.opacity(0.05))
  .cornerRadius(4)
```

## Todo

- [ ] Add resolution Text view after time display
- [ ] Style with secondary color
- [ ] Add subtle background
- [ ] Test with various resolutions
- [ ] Verify layout on narrow windows

## Success Criteria

- Resolution visible in toolbar
- Matches existing UI styling
- Handles "-" state gracefully
- No layout overflow issues

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Toolbar overflow | Low | Medium | Use compact font size (11pt) |
| Layout shift on load | Low | Low | Fixed width or min-width |

## Security Considerations

None - display only.

## Next Steps

Proceed to Phase 03: Add Info Button and Sidebar State
