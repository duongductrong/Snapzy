# Phase 6: Integration & Cleanup

## Context

- [Main Plan](../plan.md)
- [Phase 5: Placeholder Tabs](./phase-05-placeholder-tabs.md)

## Overview

Integrate Preferences with existing codebase, migrate settings from ContentView, ensure data flows correctly.

## Key Insights

- ContentView currently has settings UI that duplicates Preferences functionality
- ScreenCaptureViewModel needs to read from shared settings sources
- FloatingScreenshotManager already uses UserDefaults (compatible with @AppStorage)
- Need to sync export location between Preferences and ScreenCaptureViewModel

## Requirements

1. Remove duplicate settings UI from ContentView (keep capture controls)
2. Wire PreferencesManager settings to ScreenCaptureManager
3. Ensure KeyboardShortcutManager reads from same source
4. Add "Open Preferences" button to ContentView
5. Test full integration flow

## Architecture

```
Settings Flow:
  PreferencesView (@AppStorage, PreferencesManager)
       │
       ▼
  UserDefaults (shared storage)
       │
       ├──▶ ScreenCaptureViewModel (reads export location, playSound)
       ├──▶ KeyboardShortcutManager (reads shortcuts)
       └──▶ FloatingScreenshotManager (reads overlay settings)
```

## Related Code Files

| File | Purpose |
|------|---------|
| `ZapShot/ContentView.swift` | Remove settings, add Preferences button |
| `ZapShot/ContentView+ViewModel.swift` | Extract ViewModel (optional refactor) |
| `ZapShot/Features/Preferences/PreferencesManager.swift` | Add shared keys |

## Implementation Steps

### Step 1: Define shared UserDefaults keys

```swift
// ZapShot/Features/Preferences/PreferencesKeys.swift
import Foundation

enum PreferencesKeys {
    static let playSounds = "playSounds"
    static let showMenuBarIcon = "showMenuBarIcon"
    static let exportLocation = "exportLocation"
    static let shortcutsEnabled = "shortcutsEnabled"
}
```

### Step 2: Update ScreenCaptureViewModel

```swift
// In ScreenCaptureViewModel, use @AppStorage or read from UserDefaults
@AppStorage(PreferencesKeys.playSounds) var playSound = true
@AppStorage(PreferencesKeys.exportLocation) private var exportLocationPath = ""

var saveDirectory: URL {
    if exportLocationPath.isEmpty {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        return desktop.appendingPathComponent("ZapShot")
    }
    return URL(fileURLWithPath: exportLocationPath)
}
```

### Step 3: Simplify ContentView

Remove settings sections, keep only:
- Permission status
- Capture buttons
- Status display
- "Open Preferences" button

```swift
// Simplified ContentView body
var body: some View {
    VStack(spacing: 24) {
        Text("ZapShot").font(.largeTitle).fontWeight(.bold)

        permissionSection
        Divider()
        captureSection
        Spacer()
        statusSection

        Button("Open Preferences...") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        .keyboardShortcut(",", modifiers: .command)
    }
    .padding(24)
    .frame(minWidth: 350, minHeight: 300)
}
```

### Step 4: Test integration

1. Open Preferences, change export location
2. Take screenshot, verify saves to new location
3. Toggle Play Sounds, verify sound plays/doesn't play
4. Change shortcuts, verify new shortcuts work
5. Toggle Launch at Login, verify in System Settings

## Todo List

- [ ] Create PreferencesKeys for shared constants
- [ ] Update ScreenCaptureViewModel to use @AppStorage
- [ ] Simplify ContentView, remove settings sections
- [ ] Add "Open Preferences" button to ContentView
- [ ] Test export location sync
- [ ] Test sound toggle sync
- [ ] Test shortcuts integration
- [ ] Verify launch at login works
- [ ] Clean up unused code

## Success Criteria

- [x] ContentView simplified to capture controls only
- [x] All settings in Preferences affect app behavior
- [x] No duplicate settings UI
- [x] Preferences opens via menu and Cmd+,
- [x] All settings persist correctly

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Breaking existing functionality | Test each integration point |
| UserDefaults key mismatches | Use PreferencesKeys constants |

## Security Considerations

- No new security concerns
- Existing sandboxed UserDefaults storage

## Final Checklist

- [ ] All 6 phases complete
- [ ] Preferences window functional
- [ ] Settings persist across restarts
- [ ] No console errors or warnings
- [ ] Code follows YAGNI/KISS/DRY principles
