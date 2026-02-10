# Phase 01: Remove Cloud Swift Code

## Context

- **Parent plan:** [plan.md](./plan.md)
- **Dependencies:** None
- **Related docs:** N/A (no Cloud architecture docs exist)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-02-10 |
| Description | Remove all vestigial Cloud Upload code from Swift source files |
| Priority | Low |
| Implementation Status | NOT STARTED |
| Review Status | PENDING |

## Key Insights

1. `showCloudUpload` property on `QuickAccessManager` is never read by any view or logic outside the settings toggle -- it is completely dead code
2. No Cloud upload action, API call, or upload button implementation exists anywhere in the codebase
3. The `PreferencesKeys.floatingShowCloudUpload` constant is also unused -- `QuickAccessManager` uses its own internal `Keys` enum instead
4. All 3 removals are independent and cannot cause cascading failures

## Requirements

- Remove all Cloud-related declarations, UI elements, and persistence code
- Ensure clean build after removal
- No functional regression (feature was non-functional)

## Architecture

```
PreferencesKeys.swift          QuickAccessManager.swift          QuickAccessSettingsView.swift
  floatingShowCloudUpload ─x     showCloudUpload (@Published) ←── Toggle binding ($manager.showCloudUpload)
  (unused constant)              Keys.showCloudUpload             SettingRow (cloud.fill icon)
                                 loadSettings() loader
```

All arrows are one-directional. `QuickAccessSettingsView` binds to the manager property. `PreferencesKeys` constant is entirely orphaned. Removing all three is safe.

## Related Code Files

| File | Path |
|------|------|
| QuickAccessManager | `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/QuickAccess/QuickAccessManager.swift` |
| QuickAccessSettingsView | `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Preferences/Tabs/QuickAccessSettingsView.swift` |
| PreferencesKeys | `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Preferences/PreferencesKeys.swift` |

## Implementation Steps

### Step 1: QuickAccessManager.swift

**Remove `showCloudUpload` @Published property (lines 59-63)**

Delete:
```swift
  @Published var showCloudUpload: Bool = true {
    didSet {
      UserDefaults.standard.set(showCloudUpload, forKey: Keys.showCloudUpload)
    }
  }
```

**Remove `Keys.showCloudUpload` constant (line 83)**

Delete:
```swift
    static let showCloudUpload = "floatingScreenshot.showCloudUpload"
```

**Remove settings loader (lines 109-110)**

Delete:
```swift
    showCloudUpload =
      UserDefaults.standard.object(forKey: Keys.showCloudUpload) as? Bool ?? true
```

### Step 2: QuickAccessSettingsView.swift

**Remove "Cloud Upload" SettingRow (lines 86-89)**

Delete:
```swift
        SettingRow(icon: "cloud.fill", title: "Cloud Upload", description: "Show upload button on overlay") {
          Toggle("", isOn: $manager.showCloudUpload)
            .labelsHidden()
        }
```

Ensure the preceding "Drag & Drop" SettingRow (lines 81-84) remains the last item in the "Behaviors" section. No trailing comma or formatting adjustment needed (SwiftUI ViewBuilder).

### Step 3: PreferencesKeys.swift

**Remove `floatingShowCloudUpload` constant (line 37)**

Delete:
```swift
  static let floatingShowCloudUpload = "floatingScreenshot.showCloudUpload"
```

Ensure blank line between `floatingDragDropEnabled` (line 36) and the `// Recording` comment (line 39) is preserved for readability.

## Todo List

- [ ] Remove `showCloudUpload` @Published property from `QuickAccessManager`
- [ ] Remove `Keys.showCloudUpload` from `QuickAccessManager.Keys` enum
- [ ] Remove `showCloudUpload` loader from `QuickAccessManager.loadSettings()`
- [ ] Remove "Cloud Upload" `SettingRow` from `QuickAccessSettingsView`
- [ ] Remove `floatingShowCloudUpload` from `PreferencesKeys`
- [ ] Build project (`Cmd+B`) -- verify zero errors
- [ ] Run grep for `showCloudUpload` in `Snapzy/` -- verify zero hits
- [ ] Visual check: open Quick Access settings tab, confirm no Cloud row

## Success Criteria

1. **Build succeeds** with zero errors and zero new warnings
2. **No references** to `showCloudUpload`, `floatingShowCloudUpload`, or `"Cloud Upload"` remain in `Snapzy/` source directory
3. **Quick Access settings** renders correctly with "Drag & Drop" as the last item in Behaviors section
4. **No functional regression** -- all other Quick Access settings (position, overlay size, auto-close, drag & drop) continue working

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Build failure from missed reference | Very Low | Low | Grep confirmed only 3 files reference the property |
| UI layout shift after row removal | Very Low | Low | SwiftUI Form auto-adjusts; visual verification in todo |
| UserDefaults orphan key on existing installs | Certain | None | Key is inert, ~20 bytes; not worth a migration |

## Security Considerations

- No secrets, API keys, or credentials involved
- No entitlement changes required
- Removal reduces attack surface (removes dead toggle that could theoretically be wired to unintended behavior in future)

## Next Steps

After implementation and verification:
1. Commit with message: `fix: remove vestigial Cloud Upload toggle from Quick Access settings`
2. No follow-up phases needed -- this completes the Cloud feature removal
