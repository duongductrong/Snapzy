# Research Report: ZapShot References Analysis

**Date:** 2025-01-22
**Researcher:** Agent 01
**Task:** Identify all ZapShot references requiring rename to ClaudeShot

## Summary

Found **244+ files** containing "ZapShot" references. Analysis shows partial rename already completed for Xcode project and main app file.

## Already Renamed (ClaudeShot)

| File/Location | Status |
|---------------|--------|
| `ClaudeShot.xcodeproj/` | Renamed |
| `ClaudeShot.xcodeproj/project.pbxproj` | Updated (target, product, bundle ID) |
| `ZapShot/App/ClaudeShotApp.swift` | Renamed & updated |
| `ZapShot/ClaudeShot.plist` | Created |
| `ZapShot/ClaudeShot.entitlements` | Created |
| Bundle identifier | `ClaudeShot` |
| Product name | `ClaudeShot` |

## Still Requiring Changes

### 1. Directory/File Renames (Critical)

| Current Path | Target Path |
|--------------|-------------|
| `ZapShot/` (source folder) | `ClaudeShot/` |
| `ZapShot/ZapShot.entitlements` | DELETE (duplicate) |
| `ZapShot/ZapShotIcon.icon/` | `ClaudeShot/ClaudeShotIcon.icon/` |

### 2. Swift Files - File Header Comments (~70 files)

Pattern: `//  ZapShot` at line 3 in all `.swift` files

### 3. User-Facing Strings (High Priority)

| File | Line | Reference |
|------|------|-----------|
| `ContentView.swift` | 17 | `Text("ZapShot")` |
| `WelcomeView.swift` | 28 | `"Welcome to ZapShot"` |
| `PermissionsView.swift` | 30 | `"ZapShot needs access..."` |
| `ShortcutsView.swift` | 33 | `"...to ZapShot?"` |
| `AboutSettingsView.swift` | 38, 58 | App name, GitHub URL |

### 4. Functional Code References (Critical)

| File | Line | Reference | Impact |
|------|------|-----------|--------|
| `ScreenCaptureManager.swift` | 351 | `"ZapShot_"` prefix | Screenshot filenames |
| `ScreenRecordingManager.swift` | 483 | `"ZapShot_Recording_"` | Recording filenames |
| `ScreenCaptureViewModel.swift` | 63 | `"ZapShot"` folder | Save directory |
| `GeneralSettingsView.swift` | 105,115,118 | `"ZapShot"` folder | Settings display |
| `RecordingCoordinator.swift` | 140 | `"ZapShot"` folder | Recording save path |

### 5. External Configuration Files

| File | References |
|------|------------|
| `appcast.xml` | Title, links, download URLs |
| `RELEASE_WORKFLOW.md` | Multiple ZapShot references |
| `README.md` | App name, project file reference |
| `TESTING.md` | App references |

### 6. Xcode Build Settings (project.pbxproj)

- `INFOPLIST_KEY_CFBundleDisplayName = "Zap Shot"` (lines 274, 313) - needs update to "Claude Shot"
- `INFOPLIST_FILE = ClaudeShot/Info.plist` - path references `ClaudeShot` but folder is still `ZapShot`

## File Count by Category

| Category | Count |
|----------|-------|
| Swift file headers | ~70 |
| User-facing strings | 8 |
| Functional code | 5 |
| Config/docs | 4 |
| Plans/historical docs | 170+ |

## Recommendations

1. **Phase 1:** Rename `ZapShot/` folder to `ClaudeShot/`
2. **Phase 2:** Delete duplicate files (`ZapShot.entitlements`)
3. **Phase 3:** Update all Swift code references
4. **Phase 4:** Update documentation and config files
5. **Phase 5:** Update Xcode display name setting
6. **Phase 6:** Verify build succeeds

## Unresolved Questions

1. Should historical plan files in `plans/` be updated? (170+ files reference ZapShot)
2. GitHub repository URL - will it change from `duongductrong/ZapShot`?
