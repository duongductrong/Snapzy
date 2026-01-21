# Phase 04: Update Xcode Project

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
Update Xcode project file (`project.pbxproj`) to reflect renamed folder and files.

## Key Insights
- `project.pbxproj` contains file references with paths and names
- Using `git mv` doesn't automatically update Xcode project
- Must update both file paths and group names in project file

## Related Code Files
- `ZapShot.xcodeproj/project.pbxproj`

## Implementation Steps

### Step 1: Open project in Xcode
The simplest and safest way is to:
1. Open `ZapShot.xcodeproj` in Xcode
2. Xcode will detect missing files and show them in red
3. Right-click the red files and select "Delete" (remove reference only)
4. Add the new QuickAccess folder to the project

### Alternative: Manual update via sed
If automating, replace in `project.pbxproj`:
```bash
# Replace folder path references
sed -i '' 's/FloatingScreenshot/QuickAccess/g' ZapShot.xcodeproj/project.pbxproj

# Replace file name references
sed -i '' 's/FloatingScreenshotManager\.swift/QuickAccessManager.swift/g' ZapShot.xcodeproj/project.pbxproj
sed -i '' 's/FloatingCardView\.swift/QuickAccessCardView.swift/g' ZapShot.xcodeproj/project.pbxproj
sed -i '' 's/FloatingStackView\.swift/QuickAccessStackView.swift/g' ZapShot.xcodeproj/project.pbxproj
sed -i '' 's/FloatingPanel\.swift/QuickAccessPanel.swift/g' ZapShot.xcodeproj/project.pbxproj
sed -i '' 's/FloatingPanelController\.swift/QuickAccessPanelController.swift/g' ZapShot.xcodeproj/project.pbxproj
sed -i '' 's/FloatingPosition\.swift/QuickAccessPosition.swift/g' ZapShot.xcodeproj/project.pbxproj
sed -i '' 's/ScreenshotItem\.swift/QuickAccessItem.swift/g' ZapShot.xcodeproj/project.pbxproj
sed -i '' 's/CardActionButton\.swift/QuickAccessActionButton.swift/g' ZapShot.xcodeproj/project.pbxproj
sed -i '' 's/CardTextButton\.swift/QuickAccessTextButton.swift/g' ZapShot.xcodeproj/project.pbxproj
```

## Todo List
- [ ] Update folder path references in project.pbxproj
- [ ] Update all file name references in project.pbxproj
- [ ] Verify project opens correctly in Xcode

## Success Criteria
- [ ] Project opens in Xcode without errors
- [ ] All QuickAccess files appear in project navigator
- [ ] No red (missing) file references

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Corrupted project file | Low | Critical | Backup before changes |
| Missing file reference | Medium | High | Verify all files in Xcode |

## Security Considerations
None - project configuration change only.

## Next Steps
→ Proceed to [Phase 05: Update Documentation](./phase-05-update-documentation.md)
