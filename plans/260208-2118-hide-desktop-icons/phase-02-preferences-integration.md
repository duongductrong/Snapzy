# Phase 02: Preferences Integration

**Parent Plan:** [plan.md](./plan.md)
**Dependencies:** [Phase 01](./phase-01-desktop-icon-manager-service.md) (DesktopIconManager must exist)
**Docs:** [design-guidelines](../../docs/design-guidelines.md)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-02-08 |
| Description | Add `hideDesktopIcons` preference key and toggle in General Settings |
| Priority | High |
| Implementation Status | Pending |
| Review Status | Pending |

## Key Insights

- Follows existing `@AppStorage` + `PreferencesKeys` pattern exactly
- Toggle placement: new "Capture" section between "Storage" and "Post-Capture Actions"
- Uses existing `settingRow(icon:title:description:content:)` helper
- Default: `false` (opt-in feature)
- Icon suggestion: `"eye.slash"` (SF Symbols, conveys hiding)

## Requirements

1. Add `hideDesktopIcons` static key to `PreferencesKeys`
2. Add toggle row in `GeneralSettingsView` using existing `settingRow` helper
3. Default value `false`
4. No validation needed -- simple boolean toggle

## Architecture

```
PreferencesKeys
└── static let hideDesktopIcons = "hideDesktopIcons"

GeneralSettingsView
└── Section("Capture")
    └── settingRow("eye.slash", "Hide desktop icons", ...)
        └── Toggle bound to @AppStorage(PreferencesKeys.hideDesktopIcons)
```

## Related Code Files

- `Snapzy/Features/Preferences/PreferencesKeys.swift` (lines 11-46) -- add key
- `Snapzy/Features/Preferences/Tabs/GeneralSettingsView.swift` (lines 11-184) -- add toggle

## Implementation Steps

### Step 1: Add preference key

File: `Snapzy/Features/Preferences/PreferencesKeys.swift`

Add after line 18 (`static let exportLocation`), inside the `// General` section:

```swift
  // General
  static let playSounds = "playSounds"
  static let showMenuBarIcon = "showMenuBarIcon"
  static let exportLocation = "exportLocation"
  static let hideDesktopIcons = "hideDesktopIcons"
```

### Step 2: Add toggle in GeneralSettingsView

File: `Snapzy/Features/Preferences/Tabs/GeneralSettingsView.swift`

**2a.** Add `@AppStorage` binding at top of struct (after line 13):

```swift
@AppStorage(PreferencesKeys.hideDesktopIcons) private var hideDesktopIcons = false
```

**2b.** Add new "Capture" section between "Storage" and "Post-Capture Actions" sections (after line 54, before line 56):

```swift
      Section("Capture") {
        settingRow(icon: "eye.slash", title: "Hide desktop icons", description: "Temporarily hide icons during capture") {
          Toggle("", isOn: $hideDesktopIcons)
            .labelsHidden()
        }
      }
```

### Step 3: Final GeneralSettingsView body structure

After changes, section order becomes:
1. Startup
2. Appearance
3. Storage
4. **Capture** (NEW)
5. Post-Capture Actions
6. Help
7. Software Updates

## Todo List

- [ ] Add `hideDesktopIcons` key to `PreferencesKeys.swift`
- [ ] Add `@AppStorage` binding in `GeneralSettingsView`
- [ ] Add "Capture" section with toggle row
- [ ] Verify toggle persists across app restarts
- [ ] Verify UI matches existing setting rows visually

## Success Criteria

1. New "Capture" section appears in General Settings between Storage and Post-Capture
2. Toggle persists value via `UserDefaults`
3. Default is off (unchecked)
4. Visual style matches other `settingRow` entries
5. No layout breakage in preferences window

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Section ordering looks odd | Low | Place logically between Storage and Post-Capture |
| Key name collision | None | Unique key name verified against existing keys |

## Security Considerations

- Stores only a boolean in UserDefaults
- No sensitive data involved

## Next Steps

Proceed to [Phase 03: Capture Flow Integration](./phase-03-capture-flow-integration.md) to wire the preference into capture/recording flows.
