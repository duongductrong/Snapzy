# Hide Desktop Icons During Capture

**Date:** 2026-02-08
**Status:** Planning
**Priority:** Medium

## Overview

Add ability to temporarily hide desktop icons during screenshot/recording capture. Uses wallpaper overlay approach -- creates borderless windows at desktop level filled with current wallpaper image, covering icons without Finder restart.

## Approach

**Primary:** Wallpaper Overlay windows at `CGWindowLevelForKey(.desktopWindow) + 1`
- Instant show/hide, no Finder restart, sandbox-safe
- One overlay window per connected display
- Background matches current desktop wallpaper via `NSWorkspace.shared.desktopImageURL(for:)`

**Fallback (not implemented initially):** `defaults write com.apple.finder CreateDesktop -bool false` + `killall Finder`

## Phases

| # | Phase | File | Status |
|---|-------|------|--------|
| 1 | DesktopIconManager Service | [phase-01](./phase-01-desktop-icon-manager-service.md) | Pending |
| 2 | Preferences Integration | [phase-02](./phase-02-preferences-integration.md) | Pending |
| 3 | Capture Flow Integration | [phase-03](./phase-03-capture-flow-integration.md) | Pending |

## Dependencies

- Existing `SystemWallpaperManager.swift` -- reuse downsampling logic if needed
- `PreferencesKeys.swift` -- add new key
- `GeneralSettingsView.swift` -- add toggle row
- `ScreenCaptureViewModel.swift` -- hook into capture flows
- `RecordingCoordinator.swift` -- hook into recording start/stop

## Key Decisions

1. Wallpaper overlay over Finder defaults -- instant, no restart, sandbox-safe
2. Setting off by default -- opt-in feature
3. `defer`-style guaranteed restoration -- icons always restored even on error
4. 100-150ms delay after hide before capture -- ensures overlay renders

## Files Changed

- **New:** `Snapzy/Core/Services/DesktopIconManager.swift`
- **Modified:** `Snapzy/Features/Preferences/PreferencesKeys.swift`
- **Modified:** `Snapzy/Features/Preferences/Tabs/GeneralSettingsView.swift`
- **Modified:** `Snapzy/Core/ScreenCaptureViewModel.swift`
- **Modified:** `Snapzy/Features/Recording/RecordingCoordinator.swift`

## Architecture

```
User enables toggle in General Settings
        |
        v
@AppStorage("hideDesktopIcons") stored
        |
        v
Capture triggered --> check preference
        |
        v
DesktopIconManager.shared.hideIcons()
  -> creates NSWindow per screen at desktopWindow+1 level
  -> fills with current wallpaper
        |
        v
wait 100-150ms --> perform capture --> restoreIcons()
```
