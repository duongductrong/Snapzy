# Phase 01: Rename Folder and Files

## Context
- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** None (first phase)

## Overview
| Field | Value |
|-------|-------|
| Date | 2026-01-17 |
| Priority | High |
| Implementation Status | ⬜ Pending |
| Review Status | ⬜ Pending |

## Description
Rename the `FloatingScreenshot` folder to `QuickAccess` and rename all files within to use QuickAccess naming convention.

## Key Insights
- Using `git mv` preserves git history for renamed files
- Must rename folder first, then individual files
- `ThumbnailGenerator.swift` stays unchanged (generic utility name)

## Requirements
- Rename folder from `FloatingScreenshot` to `QuickAccess`
- Rename 9 files to use QuickAccess prefix
- Preserve git history

## File Renames

| Current Path | New Path |
|-------------|----------|
| `ZapShot/Features/FloatingScreenshot/` | `ZapShot/Features/QuickAccess/` |
| `FloatingScreenshotManager.swift` | `QuickAccessManager.swift` |
| `FloatingCardView.swift` | `QuickAccessCardView.swift` |
| `FloatingStackView.swift` | `QuickAccessStackView.swift` |
| `FloatingPanel.swift` | `QuickAccessPanel.swift` |
| `FloatingPanelController.swift` | `QuickAccessPanelController.swift` |
| `FloatingPosition.swift` | `QuickAccessPosition.swift` |
| `ScreenshotItem.swift` | `QuickAccessItem.swift` |
| `CardActionButton.swift` | `QuickAccessActionButton.swift` |
| `CardTextButton.swift` | `QuickAccessTextButton.swift` |

## Implementation Steps

### Step 1: Rename folder
```bash
git mv ZapShot/Features/FloatingScreenshot ZapShot/Features/QuickAccess
```

### Step 2: Rename files
```bash
cd ZapShot/Features/QuickAccess
git mv FloatingScreenshotManager.swift QuickAccessManager.swift
git mv FloatingCardView.swift QuickAccessCardView.swift
git mv FloatingStackView.swift QuickAccessStackView.swift
git mv FloatingPanel.swift QuickAccessPanel.swift
git mv FloatingPanelController.swift QuickAccessPanelController.swift
git mv FloatingPosition.swift QuickAccessPosition.swift
git mv ScreenshotItem.swift QuickAccessItem.swift
git mv CardActionButton.swift QuickAccessActionButton.swift
git mv CardTextButton.swift QuickAccessTextButton.swift
```

## Todo List
- [ ] Rename folder FloatingScreenshot → QuickAccess
- [ ] Rename FloatingScreenshotManager.swift → QuickAccessManager.swift
- [ ] Rename FloatingCardView.swift → QuickAccessCardView.swift
- [ ] Rename FloatingStackView.swift → QuickAccessStackView.swift
- [ ] Rename FloatingPanel.swift → QuickAccessPanel.swift
- [ ] Rename FloatingPanelController.swift → QuickAccessPanelController.swift
- [ ] Rename FloatingPosition.swift → QuickAccessPosition.swift
- [ ] Rename ScreenshotItem.swift → QuickAccessItem.swift
- [ ] Rename CardActionButton.swift → QuickAccessActionButton.swift
- [ ] Rename CardTextButton.swift → QuickAccessTextButton.swift

## Success Criteria
- [ ] All files exist in new QuickAccess folder
- [ ] Git history preserved for renamed files
- [ ] No files left in old FloatingScreenshot folder

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Git history loss | Low | Medium | Use `git mv` instead of manual rename |
| Xcode project out of sync | High | High | Update project.pbxproj in Phase 04 |

## Security Considerations
None - pure file rename operation.

## Next Steps
→ Proceed to [Phase 02: Update Type Names](./phase-02-update-type-names.md)
