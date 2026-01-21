# Annotate Theme Consistency Plan

## Overview
**Date:** 2026-01-21
**Priority:** Medium
**Status:** Planning

Unify Annotate feature toolbar/sidebar/bottom bar colors with Preferences styling pattern for consistent theme appearance across the app.

## Problem Statement
Annotate views use hardcoded NSColor semantic colors without SwiftUI color scheme context. Preferences uses ThemeManager with `.preferredColorScheme()` for proper theme integration. Result: inconsistent colors between features.

## Solution
Add ThemeManager integration to AnnotateMainView with `.preferredColorScheme(themeManager.systemAppearance)` modifier. This propagates theme context to all child views, making semantic NSColor values resolve correctly.

## Implementation Phases

| Phase | Description | Status | Progress |
|-------|-------------|--------|----------|
| [Phase 01](./phase-01-thememanager-integration.md) | Add ThemeManager to AnnotateMainView | ✅ Completed | 100% |

## Key Files
- `ZapShot/Features/Annotate/Views/AnnotateMainView.swift` - Main change location
- `ZapShot/Core/Theme/ThemeManager.swift` - Theme state provider
- `ZapShot/Features/Preferences/Tabs/GeneralSettingsView.swift` - Reference implementation

## Success Criteria
- [ ] Annotate toolbar matches Preferences window appearance
- [ ] Theme switching (light/dark/system) reflects immediately in Annotate
- [ ] No visual inconsistencies between app features
- [ ] Build succeeds without warnings

## Risk Assessment
**Low Risk** - Single file modification, pattern already established in codebase.

## Notes
- AnnotateWindow.swift already has AppKit-level theme integration
- SwiftUI views just need color scheme context propagation
- Semantic NSColor values (.controlBackgroundColor, etc.) are correct choices
