# Theme Switching Implementation Plan

## Overview

Add theme switching (auto/light/dark) to ZapShot macOS app. Implementation spans SwiftUI scenes and AppKit NSWindow subclasses.

## Status: COMPLETE ✅

## Phases

| Phase | Description | Status | File |
|-------|-------------|--------|------|
| 1 | Core Theme Infrastructure | COMPLETE | [phase-01-core-theme-infrastructure.md](./phase-01-core-theme-infrastructure.md) |
| 2 | SwiftUI Integration | COMPLETE | [phase-02-swiftui-integration.md](./phase-02-swiftui-integration.md) |
| 3 | AppKit Window Integration | COMPLETE | [phase-03-appkit-window-integration.md](./phase-03-appkit-window-integration.md) |
| 4 | Settings UI | COMPLETE | [phase-04-settings-ui.md](./phase-04-settings-ui.md) |
| 5 | Testing & Validation | COMPLETE | [phase-05-testing-validation.md](./phase-05-testing-validation.md) |

## Architecture Summary

```
ThemeManager (ObservableObject)
    |
    +-- @AppStorage("appearanceMode") -> persists user choice
    |
    +-- @Published currentSystemIsDark -> tracks system appearance changes
    |
    +-- systemAppearance: ColorScheme? -> for SwiftUI (returns nil for .system)
    |
    +-- effectiveColorScheme: ColorScheme -> never nil, resolves to .light/.dark
    |
    +-- nsAppearance: NSAppearance? -> for NSWindow.appearance
    |
    +-- DistributedNotificationCenter -> listens to system theme changes
    |
    +-- NotificationCenter.themeDidChange -> notifies AppKit windows
```

## Implementation Approach

**Solution:** Option E (effectiveColorScheme with system appearance tracking)

Avoids SwiftUI's `preferredColorScheme(nil)` bug by:
1. Never passing nil to `.preferredColorScheme()`
2. Tracking system appearance via DistributedNotificationCenter
3. Computing concrete `.light` or `.dark` value for `.system` mode
4. Notifying AppKit windows when theme changes

## Key Files to Modify

1. `ZapShot/Features/Preferences/PreferencesKeys.swift` - add theme key
2. `ZapShot/Core/Theme/ThemeManager.swift` - NEW file
3. `ZapShot/Core/Theme/AppearanceMode.swift` - NEW file
4. `ZapShot/App/ZapShotApp.swift` - apply theme at app level
5. `ZapShot/Features/Annotate/Window/AnnotateWindow.swift` - respect theme
6. `ZapShot/Features/VideoEditor/VideoEditorWindow.swift` - respect theme
7. `ZapShot/Features/Preferences/Tabs/GeneralSettingsView.swift` - add picker

## Dependencies

- No external dependencies required
- Uses native SwiftUI/AppKit APIs

## Estimated Effort

- Phase 1: 30 min
- Phase 2: 20 min
- Phase 3: 30 min
- Phase 4: 20 min
- Phase 5: 30 min
- **Total: ~2.5 hours**

## Research References

- [researcher-01-swiftui-theming.md](./research/researcher-01-swiftui-theming.md)
- [researcher-02-macos-theming.md](./research/researcher-02-macos-theming.md)
- [scout-01-codebase-structure.md](./scout/scout-01-codebase-structure.md)

## Code Review Results

**Date:** 2026-01-20  
**Status:** APPROVED ✅  
**Score:** 9/10

### Files Modified
1. `ZapShot/Core/Theme/ThemeManager.swift` (NEW)
2. `ZapShot/Core/Theme/AppearanceMode.swift` (NEW)
3. `ZapShot/Features/Preferences/PreferencesView.swift`
4. `ZapShot/App/ZapShotApp.swift`
5. `ZapShot/Features/Recording/RecordingToolbarWindow.swift`
6. `ZapShot/Features/Annotate/Window/AnnotateWindow.swift`
7. `ZapShot/Features/VideoEditor/VideoEditorWindow.swift`

### Issues Resolved
- ✅ H1: Updated all SwiftUI views to use `effectiveColorScheme`
- ✅ H2: Added system appearance change listeners to AppKit windows
- ✅ M3: Removed unnecessary Task wrapper in Combine sink
- ✅ Extracted notification names to constants (.themeDidChange, .appleInterfaceThemeChanged)

### Build Status
- ✅ Clean build successful
- ✅ No compiler errors
- ✅ No warnings (except Info.plist in Copy Bundle Resources)

### Testing Status
- ✅ All SwiftUI windows use effectiveColorScheme
- ✅ AppKit windows observe theme changes
- ✅ System appearance changes trigger updates
- ✅ User theme preference persists
- ✅ Theme updates propagate immediately

**Full Report:** `./reports/260120-code-reviewer-theme-switching-fix-report.md`
