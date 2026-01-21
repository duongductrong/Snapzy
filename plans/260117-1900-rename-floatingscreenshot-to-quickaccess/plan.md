# Plan: Rename FloatingScreenshot to QuickAccess

## Overview
Rename `FloatingScreenshot` folder and all related types/views to `QuickAccess` for naming consistency with existing `QuickAccessSettingsView`.

**Created:** 2026-01-17
**Status:** 🔵 Planning
**Complexity:** Medium (mechanical refactoring, ~15 files affected)

## Rationale
- `QuickAccessSettingsView` already uses "QuickAccess" terminology
- "QuickAccess" better describes the feature's purpose (quick access to recent screenshots)
- Improves codebase consistency and readability

## Implementation Phases

| Phase | Name | Status | Files |
|-------|------|--------|-------|
| 01 | [Rename Folder & Files](./phase-01-rename-folder-and-files.md) | ⬜ Pending | 10 |
| 02 | [Update Type Names](./phase-02-update-type-names.md) | ⬜ Pending | 10 |
| 03 | [Update External References](./phase-03-update-external-references.md) | ⬜ Pending | 4 |
| 04 | [Update Xcode Project](./phase-04-update-xcode-project.md) | ⬜ Pending | 1 |
| 05 | [Update Documentation](./phase-05-update-documentation.md) | ⬜ Pending | 1 |
| 06 | [Verification](./phase-06-verification.md) | ⬜ Pending | - |

## Files Affected

### QuickAccess Module (10 files)
- `FloatingScreenshotManager.swift` → `QuickAccessManager.swift`
- `FloatingCardView.swift` → `QuickAccessCardView.swift`
- `FloatingStackView.swift` → `QuickAccessStackView.swift`
- `FloatingPanel.swift` → `QuickAccessPanel.swift`
- `FloatingPanelController.swift` → `QuickAccessPanelController.swift`
- `FloatingPosition.swift` → `QuickAccessPosition.swift`
- `ScreenshotItem.swift` → `QuickAccessItem.swift`
- `CardActionButton.swift` → `QuickAccessActionButton.swift`
- `CardTextButton.swift` → `QuickAccessTextButton.swift`
- `ThumbnailGenerator.swift` → (no rename - generic utility)

### External Files (4 files)
- `Core/ScreenCaptureViewModel.swift`
- `Features/Preferences/Tabs/QuickAccessSettingsView.swift`
- `Features/Annotate/AnnotateManager.swift`
- `Features/Annotate/Window/AnnotateWindowController.swift`

### Project Files (1 file)
- `ZapShot.xcodeproj/project.pbxproj`

### Documentation (1 file)
- `README.md`

## Constraints
- Preserve all functionality - pure rename refactoring
- Keep `ThumbnailGenerator` name (generic utility)
- Maintain backward compatibility for UserDefaults keys (keep old key names)

## Success Criteria
- [ ] All files renamed and moved to QuickAccess folder
- [ ] All type references updated
- [ ] Project builds without errors
- [ ] All features work as before rename
