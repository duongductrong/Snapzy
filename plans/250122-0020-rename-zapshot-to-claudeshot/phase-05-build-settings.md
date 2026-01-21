# Phase 05: Xcode Build Settings Update

**Parent Plan:** [plan.md](./plan.md)
**Dependencies:** [Phase 01](./phase-01-directory-renames.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 260122 |
| Priority | High |
| Status | Pending |
| Estimated Effort | 5 minutes |

## Description

Update Xcode build settings in `project.pbxproj` to change the display name from "Zap Shot" to "Claude Shot".

## Key Insights

- `INFOPLIST_KEY_CFBundleDisplayName` controls app name in Dock/Finder
- Currently set to "Zap Shot" (with space)
- Appears in 2 locations (Debug and Release configs)
- This is what users see in macOS UI

## Requirements

1. Update CFBundleDisplayName from "Zap Shot" to "Claude Shot"
2. Update both Debug and Release configurations

## Related Files

| File | Path |
|------|------|
| project.pbxproj | `ClaudeShot.xcodeproj/project.pbxproj` |

## Implementation Steps

### Step 1: Locate display name settings
```bash
cd /Users/duongductrong/Developer/ZapShot
grep -n "CFBundleDisplayName" ClaudeShot.xcodeproj/project.pbxproj
```

### Step 2: Update Debug configuration (Line ~274)
```
// Change
INFOPLIST_KEY_CFBundleDisplayName = "Zap Shot";
// To
INFOPLIST_KEY_CFBundleDisplayName = "Claude Shot";
```

### Step 3: Update Release configuration (Line ~313)
```
// Change
INFOPLIST_KEY_CFBundleDisplayName = "Zap Shot";
// To
INFOPLIST_KEY_CFBundleDisplayName = "Claude Shot";
```

### Step 4: Verify changes
```bash
cd /Users/duongductrong/Developer/ZapShot
grep "CFBundleDisplayName" ClaudeShot.xcodeproj/project.pbxproj
# Should show "Claude Shot" in both places
```

### Alternative: Batch update
```bash
cd /Users/duongductrong/Developer/ZapShot
sed -i '' 's/CFBundleDisplayName = "Zap Shot"/CFBundleDisplayName = "Claude Shot"/g' ClaudeShot.xcodeproj/project.pbxproj
```

## Todo List

- [ ] Update Debug config display name
- [ ] Update Release config display name
- [ ] Verify both configurations updated
- [ ] Build project to confirm settings work

## Success Criteria

1. App appears as "Claude Shot" in Dock
2. App appears as "Claude Shot" in Finder
3. App appears as "Claude Shot" in Activity Monitor
4. Both Debug and Release configs updated

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| pbxproj corruption | Very Low | High | Backup before edit |
| Xcode cache issues | Low | Low | Clean build folder |
| Inconsistent naming | Low | Low | Verify both configs |

## Notes

- Do not modify other build settings
- The product name `ClaudeShot` (no space) is already correct
- Bundle identifier `ClaudeShot` is already correct
- Only the display name needs the space: "Claude Shot"

## Rollback Plan

```bash
git checkout -- ClaudeShot.xcodeproj/project.pbxproj
```
