# QuickAccess Video Card Implementation Plan

**Date:** 2026-01-17
**Priority:** High
**Status:** ✅ Implementation Complete - Approved with Minor Revisions

## Overview

Extend QuickAccess feature to support video recordings with thumbnail preview, duration display, copy/save actions, and video editor placeholder integration.

## Research & Analysis

- [Research: AVFoundation Video APIs](./research/researcher-01-avfoundation-video-apis.md)
- [Scout: Codebase Analysis](./scout/scout-01-codebase-analysis.md)

## Phases

| Phase | Description | Status |
|-------|-------------|--------|
| [Phase 01](./phase-01-quickaccess-item-enhancement.md) | Extend QuickAccessItem model | ✅ Completed |
| [Phase 02](./phase-02-video-thumbnail-generator.md) | Add video thumbnail generation | ✅ Completed |
| [Phase 03](./phase-03-video-card-ui.md) | Update card UI with duration badge | ✅ Completed |
| [Phase 04](./phase-04-video-editor-placeholder.md) | Create VideoEditor placeholder | ✅ Completed |
| [Phase 05](./phase-05-recording-integration.md) | Integrate with RecordingCoordinator | ✅ Completed |

## Architecture

```
QuickAccess/
├── QuickAccessItem.swift          # MODIFY: Add itemType, duration
├── ThumbnailGenerator.swift       # MODIFY: Add video support
├── QuickAccessCardView.swift      # MODIFY: Add duration badge
├── QuickAccessManager.swift       # MODIFY: Add addVideo(), copyVideo()
└── ...

VideoEditor/                       # NEW: Placeholder feature
├── VideoEditorManager.swift       # NEW: Singleton manager
├── VideoEditorWindow.swift        # NEW: Window configuration
└── VideoEditorPlaceholderView.swift # NEW: Coming soon view

Recording/
└── RecordingCoordinator.swift     # MODIFY: Add QuickAccess integration
```

## Key Design Decisions

1. **Backward Compatible Model** - Add optional properties, keep existing initializer
2. **Unified ThumbnailGenerator** - Single entry point detects file type
3. **Consistent Card UI** - Same dimensions, hover behavior, button layout
4. **Duration Badge** - Bottom-right corner, semi-transparent background
5. **Placeholder Editor** - Simple window with "Coming Soon" message

## Dependencies

- AVFoundation framework (already imported in ScreenRecordingManager)
- No external dependencies required

## Success Criteria

- [x] Video recordings appear in QuickAccess stack after recording stops
- [x] Video thumbnail shows first frame
- [x] Duration badge displays correctly (MM:SSs format)
- [x] Copy action copies video file URL to clipboard
- [x] Save action reveals video in Finder
- [x] Double-click opens video editor placeholder
- [x] Visual consistency with screenshot cards maintained

## Code Review

- [Code Review Report](./reports/260117-code-reviewer-to-dev-team-quickaccess-video-implementation.md) - 2026-01-17

**Build Status:** ✅ BUILD SUCCEEDED
**Approval:** ✅ APPROVED WITH MINOR REVISIONS

### High Priority Fixes Required
1. Replace print statements with proper logging in ThumbnailGenerator
2. Fix duration fallback ambiguity (0 vs nil) in QuickAccessManager.addVideo()
3. Add NotificationCenter observer cleanup in VideoEditorManager.closeAll()

### Medium Priority Improvements
- Add duration format localization
- Refactor duplicated scaling logic in ThumbnailGenerator
- Use UTType for video detection instead of hardcoded extensions
- Rename removeScreenshot() to removeItem() for clarity

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| AVFoundation thumbnail fails for some codecs | Low | Fallback to generic video icon |
| Performance impact from async thumbnail generation | Low | Already async pattern established |
| Model changes break existing screenshot flow | Low | Backward-compatible design |

## Estimated Effort

- Phase 01: Small (model changes)
- Phase 02: Medium (AVFoundation integration)
- Phase 03: Small (UI modifications)
- Phase 04: Small (placeholder creation)
- Phase 05: Small (integration)

**Total:** Medium complexity, well-scoped changes
