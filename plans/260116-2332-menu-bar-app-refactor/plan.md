# Menu Bar App Refactor Plan

**Date**: 2026-01-16
**Status**: Planning
**Priority**: High

## Overview

Refactor ZapShot from a standard windowed application to a macOS Menu Bar App (Agent Application). The app will run in the system menu bar without appearing in the Dock or Cmd+Tab switcher.

## Objectives

1. Configure app as LSUIElement (agent app) via Info.plist
2. Replace WindowGroup with MenuBarExtra for menu bar presence
3. Implement proper window management for Settings/Preferences
4. Maintain onboarding flow functionality

## Phase Summary

| Phase | Description | Status | Progress |
|-------|-------------|--------|----------|
| [Phase 01](./phase-01-info-plist-configuration.md) | Info.plist Agent Configuration | ✅ Complete | 100% |
| [Phase 02](./phase-02-menubar-extra-implementation.md) | MenuBarExtra Implementation | ✅ Complete | 100% |
| [Phase 03](./phase-03-window-management.md) | Window Management | ✅ Complete | 100% |

## Architecture Changes

**Before**: WindowGroup (main window) + Settings scene
**After**: MenuBarExtra (menu bar) + WindowGroup (onboarding) + Settings scene

## Key Files Affected

- `/ZapShot/App/ZapShotApp.swift` - Complete refactor
- `Info.plist` - Add LSUIElement key (via Xcode project settings)
- `/ZapShot/Core/ScreenCaptureViewModel.swift` - Minor adjustments for menu bar context

## Dependencies

- macOS 13.0+ (MenuBarExtra API)
- ScreenCaptureKit integration maintained
- Existing PreferencesView unchanged

## Risk Assessment

- **Low**: Info.plist change is straightforward
- **Low**: MenuBarExtra is well-documented API
- **Medium**: Onboarding flow needs special handling for agent apps

## Success Criteria

1. App icon appears in menu bar, not in Dock
2. Menu shows capture options and preferences access
3. Settings window opens correctly from menu
4. Onboarding displays on first launch
5. All existing capture functionality preserved
