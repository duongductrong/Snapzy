# Phase 07: Verification and Testing

**Parent Plan:** [plan.md](./plan.md)
**Dependencies:** All previous phases (01-06)

## Overview

| Field | Value |
|-------|-------|
| Date | 260122 |
| Priority | Critical |
| Status | Pending |
| Estimated Effort | 20 minutes |

## Description

Verify all rename changes are complete, build succeeds, and app functions correctly with new branding.

## Key Insights

- Must run after all other phases complete
- Build verification is critical path
- UI testing confirms user-facing changes
- File save testing confirms functional changes

## Requirements

1. Project builds without errors
2. All UI shows "ClaudeShot" branding
3. File operations use "ClaudeShot" naming
4. No "ZapShot" references in active code

## Verification Steps

### Step 1: Code Reference Audit
```bash
cd /Users/duongductrong/Developer/ZapShot

# Find any remaining ZapShot references in source code
grep -r "ZapShot" ClaudeShot --include="*.swift" | grep -v "^.*:.*//.*ZapShot"

# Should return empty or only comments
```

### Step 2: Build Verification
```bash
cd /Users/duongductrong/Developer/ZapShot

# Clean build folder
xcodebuild clean -project ClaudeShot.xcodeproj -scheme ClaudeShot

# Build project
xcodebuild build -project ClaudeShot.xcodeproj -scheme ClaudeShot -configuration Debug

# Check for errors
echo $?  # Should be 0
```

### Step 3: Run App and UI Verification

Launch app and verify:
- [ ] Menu bar shows "ClaudeShot"
- [ ] Dock icon tooltip shows "Claude Shot"
- [ ] Welcome screen shows "Welcome to ClaudeShot"
- [ ] About dialog shows "ClaudeShot"
- [ ] Preferences window title shows app name correctly

### Step 4: Functional Verification

Test file operations:
- [ ] Take screenshot, verify filename: `ClaudeShot_*.png`
- [ ] Start recording, verify filename: `ClaudeShot_Recording_*.mov`
- [ ] Check save location: `~/Pictures/ClaudeShot/` or `~/Movies/ClaudeShot/`

### Step 5: Permission Dialog Verification

If testing fresh:
- [ ] Screen recording permission shows "ClaudeShot"

### Step 6: Documentation Verification
```bash
cd /Users/duongductrong/Developer/ZapShot

# Check root docs for ZapShot references
grep -l "ZapShot" README.md RELEASE_WORKFLOW.md TESTING.md appcast.xml 2>/dev/null
# Should return empty
```

### Step 7: Git Status Check
```bash
cd /Users/duongductrong/Developer/ZapShot
git status

# Review all changes are intentional
git diff --stat
```

## Todo List

- [ ] Run code reference audit
- [ ] Clean and build project
- [ ] Launch app and verify UI
- [ ] Test screenshot capture
- [ ] Test screen recording
- [ ] Verify save locations
- [ ] Check documentation
- [ ] Review git changes

## Success Criteria

| Criterion | Status |
|-----------|--------|
| Build succeeds | Pending |
| No build warnings related to rename | Pending |
| UI shows ClaudeShot | Pending |
| Files save with ClaudeShot prefix | Pending |
| No ZapShot in source (except comments/history) | Pending |
| Documentation updated | Pending |

## Final Checklist

### Code Quality
- [ ] No compiler errors
- [ ] No compiler warnings (rename-related)
- [ ] All file references resolve

### User Experience
- [ ] App name displays correctly everywhere
- [ ] Welcome flow shows correct branding
- [ ] About dialog accurate
- [ ] Settings show correct folder names

### Functionality
- [ ] Screenshots save correctly
- [ ] Recordings save correctly
- [ ] Annotations work
- [ ] Quick access works

### Documentation
- [ ] README accurate
- [ ] TESTING.md accurate
- [ ] RELEASE_WORKFLOW.md accurate
- [ ] appcast.xml accurate

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Build failure | Low | High | Check Phase 01 completion |
| Missed reference | Low | Low | Comprehensive grep search |
| Runtime crash | Very Low | High | Test all features |

## Post-Verification Actions

1. Stage all changes for commit
2. Create descriptive commit message
3. Consider tagging as new version if releasing

## Commit Template

```bash
git add -A
git commit -m "feat: rename app from ZapShot to ClaudeShot

- Rename source folder ZapShot/ to ClaudeShot/
- Update file headers in all Swift files
- Update user-facing strings (welcome, permissions, about)
- Update filename prefixes for screenshots and recordings
- Update save folder references
- Update display name to 'Claude Shot'
- Update documentation (README, TESTING, appcast)
"
```

## Rollback Plan

If critical issues found:
```bash
git checkout -- .
git clean -fd
```

Then investigate specific phase that failed.
