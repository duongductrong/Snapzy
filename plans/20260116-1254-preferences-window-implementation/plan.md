# ZapShot Preferences Window Implementation Plan

## Overview

Implement macOS Preferences window with tabbed interface matching CleanShot X UX. Uses SwiftUI `Settings` scene with segmented TabView, `@AppStorage` for persistence, and `SMAppService` for launch-at-login.

## Research References

- [SwiftUI Preferences Patterns](./research/researcher-01-swiftui-preferences-patterns.md)
- [Keyboard Shortcuts Recording](./research/researcher-02-keyboard-shortcuts-recording.md)

## Architecture

```
ZapShot/Features/Preferences/
  PreferencesView.swift          # Root TabView container
  PreferencesManager.swift       # Centralized settings state
  Tabs/
    GeneralSettingsView.swift    # Startup, sounds, export, after-capture
    QuickAccessSettingsView.swift # Position, size, behaviors
    ShortcutsSettingsView.swift  # Keyboard shortcuts configuration
    PlaceholderSettingsView.swift # Wallpaper, Recording, Cloud, Advanced
  Components/
    AfterCaptureMatrixView.swift # Checkbox grid for post-capture actions
    LoginItemManager.swift       # SMAppService wrapper
```

## Implementation Phases

| Phase | Description | Est. Effort |
|-------|-------------|-------------|
| [Phase 1](./phases/phase-01-foundation.md) | Settings scene, PreferencesManager, tab structure | 2h |
| [Phase 2](./phases/phase-02-general-tab.md) | General tab with all controls | 2h |
| [Phase 3](./phases/phase-03-quick-access-tab.md) | Quick Access overlay settings | 1.5h |
| [Phase 4](./phases/phase-04-shortcuts-tab.md) | Shortcuts tab with recorder integration | 1.5h |
| [Phase 5](./phases/phase-05-placeholder-tabs.md) | Placeholder views for future tabs | 0.5h |
| [Phase 6](./phases/phase-06-integration.md) | App integration, cleanup, testing | 1h |

**Total Estimated Effort:** 8.5 hours

## Key Decisions

1. **Settings Scene over WindowGroup** - Auto-registers Cmd+, shortcut, single instance
2. **@AppStorage for simple prefs** - Direct UserDefaults binding
3. **Reuse existing components** - ShortcutRecorderView, KeyboardShortcutManager
4. **PreferencesManager singleton** - Centralized state for complex prefs (after-capture matrix)
5. **SMAppService for login item** - Modern API, replaces deprecated LSSharedFileList

## Dependencies

- Existing: `ShortcutRecorderView`, `KeyboardShortcutManager`, `FloatingScreenshotManager`
- Framework: `ServiceManagement` (SMAppService)
- macOS 13+ required for Settings scene and SMAppService

## Success Criteria

- Preferences opens via Cmd+, or menu
- All settings persist across app restarts
- Shortcuts tab works with existing KeyboardShortcutManager
- Launch at login toggles correctly
- ContentView settings migrated to Preferences
