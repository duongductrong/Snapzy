# Annotate: Unsaved Changes Confirmation & Keyboard Shortcuts

**Plan ID:** 260118-1430-annotate-unsaved-changes-keyboard-shortcuts
**Created:** 2026-01-18
**Status:** Completed

## Overview

Add unsaved changes tracking and close confirmation dialog to the Annotate feature, plus keyboard shortcuts for save operations.

## Features

1. **Close Confirmation for Unsaved Changes** - Track canvas modifications and prompt user before closing with unsaved work
2. **Keyboard Shortcuts** - Cmd+S for Save, Cmd+Shift+S for Save As

## Implementation Phases

| Phase | File | Status | Description |
|-------|------|--------|-------------|
| 01 | [phase-01-state-tracking.md](./phase-01-state-tracking.md) | Completed | Add `hasUnsavedChanges` to AnnotateState |
| 02 | [phase-02-window-delegate.md](./phase-02-window-delegate.md) | Completed | NSWindowDelegate + close confirmation |
| 03 | [phase-03-keyboard-shortcuts.md](./phase-03-keyboard-shortcuts.md) | Completed | Cmd+S, Cmd+Shift+S handling |
| 04 | [phase-04-integration.md](./phase-04-integration.md) | Completed | Wire notifications, mark saved after export |

## Files Modified

| File | Changes |
|------|---------|
| `ZapShot/Features/Annotate/State/AnnotateState.swift` | Add `hasUnsavedChanges`, `markAsSaved()` |
| `ZapShot/Features/Annotate/Window/AnnotateWindowController.swift` | NSWindowDelegate, close confirmation |
| `ZapShot/Features/Annotate/Window/AnnotateWindow.swift` | Override `performKeyEquivalent` |
| `ZapShot/Features/Annotate/Export/AnnotateExporter.swift` | Accept callback for post-save cleanup |
| `ZapShot/Features/Annotate/Views/AnnotateToolbarView.swift` | Use notifications for save actions |

## Architecture Notes

- Use `NSWindowDelegate.windowShouldClose(_:)` for close interception
- Keyboard shortcuts handled in `AnnotateWindow.performKeyEquivalent(with:)`
- NotificationCenter for decoupled save action triggering
- State tracks dirty flag, reset on successful save

## Dependencies

- Existing `AnnotateState.saveState()` already called on modifications
- `AnnotateExporter` handles actual file saving
- `AnnotateManager` tracks window lifecycle via `NSWindow.willCloseNotification`

## Risks

- **Low**: Need to ensure all modification paths set `hasUnsavedChanges = true`
- **Low**: Close confirmation must work for both QuickAccessItem and empty window flows

## Testing Checklist

- [ ] Add annotation, close window -> shows confirmation
- [ ] Apply crop, close window -> shows confirmation
- [ ] Save via Done, close window -> no confirmation
- [ ] Save As, close window -> no confirmation
- [ ] Cmd+S triggers Done action
- [ ] Cmd+Shift+S triggers Save As action
- [ ] Cancel in confirmation keeps window open
- [ ] Don't Save closes without saving
