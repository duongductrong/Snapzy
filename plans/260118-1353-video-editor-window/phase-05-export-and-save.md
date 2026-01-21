# Phase 5: Export and Save

## Context

- [Plan](./plan.md)
- [Phase 4](./phase-04-controls-and-info-panel.md)
- [AVFoundation Research](./research/researcher-01-avfoundation-video-editing.md)
- [AnnotateWindowController Reference](../../ZapShot/Features/Annotate/Window/AnnotateWindowController.swift)

## Overview

Implement video export with trim, save confirmation dialog (Replace Original / Save as Copy / Cancel), and unsaved changes confirmation on window close. Follow patterns established in AnnotateWindowController.

## Requirements

1. Export trimmed video using AVAssetExportSession
2. Save confirmation with three options: Replace / Copy / Cancel
3. Unsaved changes alert when closing with modifications
4. Progress indicator during export
5. Keyboard shortcut: Cmd+S for save

## Architecture Decisions

- **Export Quality**: AVAssetExportPresetHighestQuality to preserve original
- **Temp File**: Export to temp directory, then move/replace
- **File Naming**: Copy uses `{original}_trimmed.{ext}` pattern
- **Modal Dialogs**: NSAlert.beginSheetModal (matches Annotate pattern)
- **Progress**: Use exportSession.progress with timer for UI updates

## Related Files

| File | Action |
|------|--------|
| `ZapShot/Features/VideoEditor/Export/VideoEditorExporter.swift` | Create |
| `ZapShot/Features/VideoEditor/VideoEditorWindowController.swift` | Modify |
| `ZapShot/Features/VideoEditor/State/VideoEditorState.swift` | Modify |

## Implementation Details

- [Exporter Class](./phase-05-exporter.md) - VideoEditorExporter implementation
- [Save Dialogs](./phase-05-save-dialogs.md) - Confirmation and unsaved changes alerts
- [Controller Changes](./phase-05-controller-changes.md) - WindowController modifications

## Todo List

- [ ] Create Export/ directory structure
- [ ] Implement VideoEditorExporter with trim export
- [ ] Implement replaceOriginal with temp file dance
- [ ] Implement saveAsCopy with filename generation
- [ ] Add NSWindowDelegate to controller
- [ ] Implement windowShouldClose with unsaved check
- [ ] Implement showUnsavedChangesAlert
- [ ] Implement showSaveConfirmation dialog
- [ ] Add replaceOriginal and saveAsCopy actions
- [ ] Add forceClose method
- [ ] Add Cmd+S keyboard shortcut
- [ ] Add export progress overlay
- [ ] Test complete save flow
- [ ] Test unsaved changes on close
- [ ] Test export quality preservation

## Success Criteria

- Closing with changes shows unsaved alert
- Save dialog offers Replace/Copy/Cancel
- Replace overwrites original file
- Copy creates `_trimmed` version
- Export preserves video quality
- Cmd+S triggers save flow
- Progress shown during export

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Original file corrupted on failed replace | Export to temp first, only delete original on success |
| Export takes too long | Show progress, run in Task |
| Copy filename collision | Could add timestamp if file exists |
| Audio lost during export | AVAssetExportSession preserves audio by default |
