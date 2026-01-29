# Phase 04: Build and Verification

**Status**: Pending
**Estimated Effort**: Low
**Files**: All modified files

---

## Objective

Ensure all changes compile without errors/warnings and verify functionality through manual testing.

## Build Steps

### Task 1: Compile Project

```bash
cd /Users/duongductrong/Developer/ZapShot
xcodebuild -project ClaudeShot.xcodeproj -scheme ClaudeShot -configuration Debug build 2>&1 | head -100
```

**Expected**: Build Succeeded with no errors

### Task 2: Check for Warnings

```bash
xcodebuild -project ClaudeShot.xcodeproj -scheme ClaudeShot -configuration Debug build 2>&1 | grep -i "warning:"
```

**Expected**: No new warnings related to modified files

## Verification Checklist

### Dimension Application Verification

| Test Case | Steps | Expected Result |
|-----------|-------|-----------------|
| Standard export with 720p | 1. Load 1080p video 2. Set 720p preset 3. Export (no zoom/bg) | Output is 1280x720 |
| Video-only export with 50% | 1. Load 1080p video 2. Set 50% preset 3. Mute audio 4. Export | Output is 960x540 |
| Composition export with 25% | 1. Load video 2. Set 25% preset 3. Add zoom 4. Export | Output respects 25% size |

### Percentage Presets Verification

| Test Case | Steps | Expected Result |
|-----------|-------|-----------------|
| 75% preset calculation | Select 75% on 1920x1080 | Shows 1440x810 |
| 50% preset calculation | Select 50% on 1920x1080 | Shows 960x540 |
| 25% preset calculation | Select 25% on 1920x1080 | Shows 480x270 |
| Even dimension enforcement | Select 50% on odd-dimension video | Dimensions are even |

### UI Display Verification

| Test Case | Steps | Expected Result |
|-----------|-------|-----------------|
| Picker shows dimensions | Open dimension picker | Each option shows calculated size |
| File size hint | Select 50% preset | Shows "~75% smaller file size" |
| Custom mode | Select Custom | Shows width/height input fields |

## Manual Test Script

1. **Open ClaudeShot**
2. **Record or open a 1080p video**
3. **Open video editor**
4. **Navigate to Export Settings panel**
5. **Test dimension picker**:
   - Verify Original shows "(1920x1080)"
   - Verify 50% shows "(960x540)"
   - Verify 720p shows "(1280x720)"
6. **Test export with 50% preset**:
   - No zoom, no background
   - Verify exported file dimensions
7. **Test export with 720p preset, audio muted**:
   - Verify exported file dimensions
8. **Test export with zoom and 25% preset**:
   - Verify exported file dimensions

## File Verification Commands

After export, verify dimensions:

```bash
# Check video dimensions with ffprobe
ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 /path/to/exported.mp4
```

## Rollback Plan

If issues found:

1. Revert changes to `VideoEditorExporter.swift`
2. Revert changes to `ExportSettings.swift`
3. Revert changes to `VideoExportSettingsPanel.swift`
4. Git: `git checkout -- ClaudeShot/Features/VideoEditor/`

## Success Criteria

- [ ] Build succeeds with no errors
- [ ] No new warnings in modified files
- [ ] Standard export applies custom dimensions
- [ ] Video-only export applies custom dimensions
- [ ] Percentage presets calculate correctly
- [ ] UI displays dimensions in picker
- [ ] File size hint shows for reduction presets
- [ ] Exported files have correct dimensions

---

## Code References

- All files modified in phases 01-03
- Build configuration: `ClaudeShot.xcodeproj`
