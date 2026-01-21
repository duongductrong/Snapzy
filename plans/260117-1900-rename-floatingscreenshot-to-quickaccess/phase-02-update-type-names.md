# Phase 02: Update Type Names

## Context
- **Parent Plan:** [plan.md](./plan.md)
- **Dependencies:** [Phase 01](./phase-01-rename-folder-and-files.md)

## Overview
| Field | Value |
|-------|-------|
| Date | 2026-01-17 |
| Priority | High |
| Implementation Status | ⬜ Pending |
| Review Status | ⬜ Pending |

## Description
Update all class, struct, and enum names within the QuickAccess module files to use QuickAccess naming convention. Also update file header comments.

## Key Insights
- Each file has a header comment with the old filename - must update
- Internal references between files need updating
- UserDefaults keys should remain unchanged for backward compatibility

## Type Renames

| Old Type | New Type | File |
|----------|----------|------|
| `FloatingScreenshotManager` | `QuickAccessManager` | QuickAccessManager.swift |
| `FloatingCardView` | `QuickAccessCardView` | QuickAccessCardView.swift |
| `FloatingStackView` | `QuickAccessStackView` | QuickAccessStackView.swift |
| `FloatingPanel` | `QuickAccessPanel` | QuickAccessPanel.swift |
| `FloatingPanelController` | `QuickAccessPanelController` | QuickAccessPanelController.swift |
| `FloatingPosition` | `QuickAccessPosition` | QuickAccessPosition.swift |
| `ScreenshotItem` | `QuickAccessItem` | QuickAccessItem.swift |
| `CardActionButton` | `QuickAccessActionButton` | QuickAccessActionButton.swift |
| `CardTextButton` | `QuickAccessTextButton` | QuickAccessTextButton.swift |

## Implementation Steps

### Step 1: QuickAccessManager.swift
- Update header comment: `FloatingScreenshotManager.swift` → `QuickAccessManager.swift`
- Update class name: `FloatingScreenshotManager` → `QuickAccessManager`
- Update internal refs: `FloatingPanelController` → `QuickAccessPanelController`
- Update internal refs: `FloatingPosition` → `QuickAccessPosition`
- Update internal refs: `ScreenshotItem` → `QuickAccessItem`
- Update internal refs: `FloatingStackView` → `QuickAccessStackView`
- **Keep UserDefaults keys unchanged** (e.g., `floatingScreenshot.enabled`)

### Step 2: QuickAccessCardView.swift
- Update header comment
- Update struct name: `FloatingCardView` → `QuickAccessCardView`
- Update refs: `ScreenshotItem` → `QuickAccessItem`
- Update refs: `FloatingScreenshotManager` → `QuickAccessManager`
- Update refs: `CardTextButton` → `QuickAccessTextButton`

### Step 3: QuickAccessStackView.swift
- Update header comment
- Update struct name: `FloatingStackView` → `QuickAccessStackView`
- Update refs: `FloatingScreenshotManager` → `QuickAccessManager`
- Update refs: `FloatingCardView` → `QuickAccessCardView`

### Step 4: QuickAccessPanel.swift
- Update header comment
- Update class name: `FloatingPanel` → `QuickAccessPanel`

### Step 5: QuickAccessPanelController.swift
- Update header comment
- Update class name: `FloatingPanelController` → `QuickAccessPanelController`
- Update refs: `FloatingPanel` → `QuickAccessPanel`
- Update refs: `FloatingPosition` → `QuickAccessPosition`

### Step 6: QuickAccessPosition.swift
- Update header comment
- Update enum name: `FloatingPosition` → `QuickAccessPosition`

### Step 7: QuickAccessItem.swift
- Update header comment
- Update struct name: `ScreenshotItem` → `QuickAccessItem`

### Step 8: QuickAccessActionButton.swift
- Update header comment
- Update struct name: `CardActionButton` → `QuickAccessActionButton`

### Step 9: QuickAccessTextButton.swift
- Update header comment
- Update struct name: `CardTextButton` → `QuickAccessTextButton`

## Todo List
- [ ] Update QuickAccessManager.swift (header + type names)
- [ ] Update QuickAccessCardView.swift (header + type names)
- [ ] Update QuickAccessStackView.swift (header + type names)
- [ ] Update QuickAccessPanel.swift (header + type names)
- [ ] Update QuickAccessPanelController.swift (header + type names)
- [ ] Update QuickAccessPosition.swift (header + type names)
- [ ] Update QuickAccessItem.swift (header + type names)
- [ ] Update QuickAccessActionButton.swift (header + type names)
- [ ] Update QuickAccessTextButton.swift (header + type names)

## Success Criteria
- [ ] All type names updated to QuickAccess convention
- [ ] All file headers updated
- [ ] UserDefaults keys remain unchanged
- [ ] No syntax errors in updated files

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Missing internal reference | Medium | High | Use find-replace carefully |
| Breaking UserDefaults | Low | High | Explicitly preserve key names |

## Security Considerations
None - pure rename operation.

## Next Steps
→ Proceed to [Phase 03: Update External References](./phase-03-update-external-references.md)
