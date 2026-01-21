# Phase 01: Directory and File Renames

**Parent Plan:** [plan.md](./plan.md)
**Dependencies:** None (critical path)

## Overview

| Field | Value |
|-------|-------|
| Date | 260122 |
| Priority | Critical |
| Status | Pending |
| Estimated Effort | 15 minutes |

## Description

Rename source folder and icon directory to match Xcode project configuration. Delete duplicate entitlements file.

## Key Insights

- `project.pbxproj` already references `ClaudeShot/` as source folder path
- Build will fail until folder is renamed
- Use `git mv` to preserve git history
- Close Xcode before renaming to avoid conflicts

## Requirements

1. Rename `ZapShot/` to `ClaudeShot/`
2. Rename `ZapShotIcon.icon/` to `ClaudeShotIcon.icon/`
3. Delete duplicate `ZapShot.entitlements`

## Related Files

```
ZapShot/                          → ClaudeShot/
ZapShot/ZapShotIcon.icon/         → ClaudeShot/ClaudeShotIcon.icon/
ZapShot/ZapShot.entitlements      → DELETE
```

## Implementation Steps

### Step 1: Verify Xcode is closed
```bash
pgrep -x Xcode && echo "Close Xcode first!" || echo "OK to proceed"
```

### Step 2: Rename source folder
```bash
cd /Users/duongductrong/Developer/ZapShot
git mv ZapShot ClaudeShot
```

### Step 3: Rename icon folder
```bash
cd /Users/duongductrong/Developer/ZapShot
git mv ClaudeShot/ZapShotIcon.icon ClaudeShot/ClaudeShotIcon.icon
```

### Step 4: Delete duplicate entitlements
```bash
cd /Users/duongductrong/Developer/ZapShot
git rm ClaudeShot/ZapShot.entitlements
```

### Step 5: Verify structure
```bash
ls -la /Users/duongductrong/Developer/ZapShot/ClaudeShot/
ls -la /Users/duongductrong/Developer/ZapShot/ClaudeShot/ClaudeShotIcon.icon/
```

### Step 6: Open Xcode and verify project loads
```bash
open /Users/duongductrong/Developer/ZapShot/ClaudeShot.xcodeproj
```

## Todo List

- [ ] Close Xcode
- [ ] Rename ZapShot/ to ClaudeShot/
- [ ] Rename ZapShotIcon.icon/ to ClaudeShotIcon.icon/
- [ ] Delete ZapShot.entitlements
- [ ] Verify Xcode project loads
- [ ] Verify file references resolve correctly

## Success Criteria

1. `ClaudeShot/` folder exists with all source files
2. `ClaudeShot/ClaudeShotIcon.icon/` folder exists
3. No `ZapShot.entitlements` file exists
4. Xcode project opens without errors
5. File navigator shows all files correctly

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Xcode project corruption | Low | High | Backup .xcodeproj before changes |
| Git history loss | Low | Medium | Use `git mv` instead of `mv` |
| Build failure after rename | Medium | Medium | Verify paths match pbxproj |
| FileSystemSync issues | Low | Medium | Clean build folder if needed |

## Rollback Plan

```bash
git checkout -- .
git clean -fd
```
