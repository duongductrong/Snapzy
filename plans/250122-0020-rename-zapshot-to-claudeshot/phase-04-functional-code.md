# Phase 04: Functional Code Updates

**Parent Plan:** [plan.md](./plan.md)
**Dependencies:** [Phase 01](./phase-01-directory-renames.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 260122 |
| Priority | Critical |
| Status | Pending |
| Estimated Effort | 20 minutes |

## Description

Update code that uses "ZapShot" in functional contexts: filename prefixes for screenshots/recordings, save directory names, and folder path references.

## Key Insights

- 5 files contain functional ZapShot references
- These affect actual app behavior (file naming, save locations)
- Users will see "ClaudeShot_" prefixes on saved files
- Default save folder will be "ClaudeShot" in Pictures/Movies

## Requirements

1. Update screenshot filename prefix from `ZapShot_` to `ClaudeShot_`
2. Update recording filename prefix from `ZapShot_Recording_` to `ClaudeShot_Recording_`
3. Update default save folder from `ZapShot` to `ClaudeShot`
4. Update all folder path references in settings

## Related Files

| File | Path | Line(s) | Reference |
|------|------|---------|-----------|
| ScreenCaptureManager.swift | `ClaudeShot/Core/ScreenCaptureManager.swift` | 351 | `"ZapShot_"` prefix |
| ScreenRecordingManager.swift | `ClaudeShot/Core/ScreenRecordingManager.swift` | 483 | `"ZapShot_Recording_"` |
| ScreenCaptureViewModel.swift | `ClaudeShot/Features/*/ScreenCaptureViewModel.swift` | 63 | `"ZapShot"` folder |
| GeneralSettingsView.swift | `ClaudeShot/Features/Preferences/Views/GeneralSettingsView.swift` | 105,115,118 | `"ZapShot"` folder |
| RecordingCoordinator.swift | `ClaudeShot/Features/*/RecordingCoordinator.swift` | 140 | `"ZapShot"` folder |

## Implementation Steps

### Step 1: ScreenCaptureManager.swift (Line ~351)
```swift
// Change
let filename = "ZapShot_\(timestamp).png"
// To
let filename = "ClaudeShot_\(timestamp).png"
```

### Step 2: ScreenRecordingManager.swift (Line ~483)
```swift
// Change
let filename = "ZapShot_Recording_\(timestamp).mov"
// To
let filename = "ClaudeShot_Recording_\(timestamp).mov"
```

### Step 3: ScreenCaptureViewModel.swift (Line ~63)
```swift
// Change default folder
"ZapShot"
// To
"ClaudeShot"
```

### Step 4: GeneralSettingsView.swift (Lines ~105, 115, 118)
```swift
// Change all occurrences
"ZapShot"
// To
"ClaudeShot"
```

### Step 5: RecordingCoordinator.swift (Line ~140)
```swift
// Change folder name
"ZapShot"
// To
"ClaudeShot"
```

### Step 6: Search for any missed functional references
```bash
cd /Users/duongductrong/Developer/ZapShot
grep -rn "ZapShot" ClaudeShot/Core --include="*.swift"
grep -rn "ZapShot" ClaudeShot/Features --include="*.swift" | grep -v "//"
```

## Todo List

- [ ] Update ScreenCaptureManager.swift filename prefix
- [ ] Update ScreenRecordingManager.swift filename prefix
- [ ] Update ScreenCaptureViewModel.swift folder name
- [ ] Update GeneralSettingsView.swift folder references (3 places)
- [ ] Update RecordingCoordinator.swift folder name
- [ ] Search for any missed functional references
- [ ] Test screenshot save with new prefix
- [ ] Test recording save with new prefix

## Success Criteria

1. Screenshots save as `ClaudeShot_YYYYMMDD_HHMMSS.png`
2. Recordings save as `ClaudeShot_Recording_YYYYMMDD_HHMMSS.mov`
3. Default save folder is `~/Pictures/ClaudeShot/`
4. Settings display shows "ClaudeShot" folder
5. No functional "ZapShot" references remain

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Existing files in ZapShot folder | N/A | None | User's old folder untouched |
| Hardcoded path issues | Low | Medium | Test save functionality |
| Settings migration | Low | Low | App uses UserDefaults |

## Testing Checklist

- [ ] Take a screenshot, verify filename starts with `ClaudeShot_`
- [ ] Start a recording, verify filename starts with `ClaudeShot_Recording_`
- [ ] Check default save location is `ClaudeShot` folder
- [ ] Open settings, verify folder name displays correctly

## Rollback Plan

```bash
git checkout -- ClaudeShot/Core/ScreenCaptureManager.swift
git checkout -- ClaudeShot/Core/ScreenRecordingManager.swift
git checkout -- ClaudeShot/Features/
```
