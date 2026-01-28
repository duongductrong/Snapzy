# Video Wallpaper/Background Implementation Plan

**Created:** 2026-01-28
**Status:** Pending
**Priority:** Medium

## Overview

Add wallpaper/background support to VideoEditor by reusing existing `SystemWallpaperManager` and extending `BackgroundStyle` enum integration. VideoEditor already uses `BackgroundStyle` but lacks wallpaper UI section.

## Current State

- `BackgroundStyle` enum already supports `.wallpaper(URL)` case
- `VideoEditorState` uses `BackgroundStyle` for `backgroundStyle` property
- `VideoBackgroundSidebarView` has gradients and colors sections, NO wallpaper section
- `SystemWallpaperManager` singleton exists and works in Annotate feature

## Gap Analysis

| Component | Annotate | VideoEditor | Action |
|-----------|----------|-------------|--------|
| BackgroundStyle enum | Full support | Full support | None needed |
| SystemWallpaperManager | Integrated | Missing | Add integration |
| WallpaperSection UI | Present | Missing | Create VideoWallpaperSection |
| Custom wallpaper picker | Present | Missing | Add picker button |

## Implementation Phases

| Phase | Description | Status | File |
|-------|-------------|--------|------|
| 1 | State Model Verification | Pending | [phase-01-state-model-updates.md](./phase-01-state-model-updates.md) |
| 2 | Wallpaper Sidebar Section | Pending | [phase-02-wallpaper-sidebar-section.md](./phase-02-wallpaper-sidebar-section.md) |
| 3 | Integration & Testing | Pending | [phase-03-integration-testing.md](./phase-03-integration-testing.md) |

## Architecture Decisions

1. **REUSE** `SystemWallpaperManager.shared` - no duplication
2. **REUSE** existing `BackgroundStyle` enum - already has `.wallpaper(URL)`
3. **CREATE** `VideoWallpaperSection` component following `VideoGradientPresetButton` pattern
4. **FOLLOW** existing grid layout (4 columns) matching gradient section

## Files to Modify

- `ClaudeShot/Features/VideoEditor/Views/VideoBackgroundSidebarView.swift`
- `ClaudeShot/Features/VideoEditor/Views/VideoEditorSidebarComponents.swift`

## Success Criteria

- [ ] System wallpapers display in video background sidebar
- [ ] Custom wallpaper picker works
- [ ] Wallpaper selection updates video preview
- [ ] Undo/redo works for wallpaper changes
- [ ] No performance regression during playback

## Estimated Effort

~2-3 hours implementation + testing
