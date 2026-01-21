# Custom Keyboard Shortcuts Plan

**Date:** 2026-01-15
**Priority:** Medium
**Status:** ✅ Completed

## Overview

Enable users to customize keyboard shortcuts for fullscreen and area capture, with updated default shortcuts matching macOS conventions (⌘⇧3 / ⌘⇧4).

## Phases

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | [Update defaults & add persistence](./phase-01-defaults-and-persistence.md) | ✅ Completed |
| 2 | [Create shortcut recorder UI](./phase-02-shortcut-recorder-ui.md) | ✅ Completed |

## Key Changes

1. Update `ShortcutConfig` defaults to ⌘⇧3 / ⌘⇧4
2. Add UserDefaults persistence for custom shortcuts
3. Create `ShortcutRecorderView` for capturing key combinations
4. Update ContentView settings section with editable shortcuts

## Success Criteria

- [x] Default shortcuts are ⌘⇧3 (fullscreen) and ⌘⇧4 (area)
- [x] Users can click to record custom shortcuts
- [x] Shortcuts persist across app restarts
- [x] Build compiles without errors
