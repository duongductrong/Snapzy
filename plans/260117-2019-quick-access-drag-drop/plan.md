# Quick Access Drag & Drop Implementation Plan

**Date**: 2026-01-17
**Status**: Completed
**Priority**: High
**Author**: Antigravity

## Overview

Implement drag & drop functionality for QuickAccessCardView enabling users to drag screenshots/videos from quick access cards to external applications (Facebook, Slack, Discord, Finder) and internal targets.

## Current State

- `QuickAccessCardView.swift`: SwiftUI view with thumbnail + hover actions (Copy, Save, Dismiss)
- `QuickAccessItem`: Contains `url: URL`, `thumbnail: NSImage`, `itemType` (.screenshot/.video)
- `QuickAccessManager`: Has `dragDropEnabled` setting (already persisted via UserDefaults)
- Panel uses `NSHostingView` for SwiftUI integration in `NSPanel`

## Technical Approach

Use SwiftUI `.draggable()` modifier with `NSItemProvider` to provide file URLs. Screenshots provide file URL + image data. Videos provide file URL only. Drag preview shows card thumbnail.

## Key Constraints

1. Must respect existing `dragDropEnabled` setting from QuickAccessManager
2. Must work with NSPanel/NSHostingView architecture
3. Must support both image and video file types
4. External apps require proper UTType declarations

## Phases

| Phase | Title | Status | Description |
|-------|-------|--------|-------------|
| 01 | Core Drag Implementation | Completed | Add `.onDrag()` modifier with NSItemProvider |

## Success Criteria

- [ ] Drag screenshots to Finder, Slack, Discord, Facebook Messenger
- [ ] Drag videos to Finder and compatible apps
- [ ] Visual drag preview shows thumbnail
- [ ] Drag disabled when `dragDropEnabled` is false
- [ ] No regressions in existing hover/click functionality

## Files to Modify

| File | Change |
|------|--------|
| `ZapShot/Features/QuickAccess/QuickAccessCardView.swift` | Add draggable modifier |

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| NSPanel drag compatibility | Low | Medium | Test with NSHostingView early |
| External app UTType mismatch | Medium | Medium | Provide multiple representations |

## Related Documentation

- [Apple: Dragging and Dropping in SwiftUI](https://developer.apple.com/documentation/swiftui/dragging-and-dropping)
- [NSItemProvider Documentation](https://developer.apple.com/documentation/foundation/nsitemprovider)
