# Splash/Intro Screen Overlay - Implementation Plan

**Date:** 260210
**Status:** Draft
**Feature:** Fullscreen splash overlay with animated logo, welcome text, blur background

## Summary

Fullscreen NSPanel overlay shown on every app launch. Starts transparent, animates logo + welcome text + button in sequence, applies background blur via NSVisualEffectView. "Continue" dismisses splash with fade, then opens onboarding (if not completed) or proceeds silently.

## Architecture

```
SplashWindowController (@MainActor, singleton)
  -> SplashWindow (NSPanel subclass, fullscreen, transparent)
       -> NSVisualEffectView (blur, animated alpha)
       -> NSHostingView -> SplashContentView (SwiftUI, animation phases)

AppDelegate.applicationDidFinishLaunching
  -> SplashWindowController.shared.show()
       -> on continue: fade out -> showOnboardingWindow() if needed
```

## Files

| Action | File | Lines (est.) |
|--------|------|-------------|
| CREATE | `Snapzy/Features/Splash/SplashWindow.swift` | ~120 |
| CREATE | `Snapzy/Features/Splash/SplashContentView.swift` | ~150 |
| MODIFY | `Snapzy/App/SnapzyApp.swift` | ~10 changed |

## Phases

| # | Phase | Status | Doc |
|---|-------|--------|-----|
| 1 | Splash Window + Blur | Pending | [phase-01](./phase-01-splash-window.md) |
| 2 | Splash Content View (SwiftUI animations) | Pending | [phase-02](./phase-02-splash-content-view.md) |
| 3 | App Integration (launch flow) | Pending | [phase-03](./phase-03-app-integration.md) |

## Key Decisions

- **NSPanel over WindowGroup**: Matches existing overlay patterns (AreaSelectionWindow, RecordingRegionOverlayWindow). Full control over transparency, level, blur.
- **Singleton controller**: Consistent with AreaSelectionController, AnnotateManager, etc.
- **Blur via NSVisualEffectView**: Native macOS blur, animated alpha for fade-in effect. Placed behind SwiftUI content in the same NSPanel.
- **Every-launch trigger**: Not gated by `onboardingCompleted`. Splash always shows; onboarding only opens if not completed.
- **Sequential dismiss**: Splash fades out first, THEN onboarding opens. Prevents visual overlap.

## Risks

- **Window level conflicts**: Splash uses `.floating`; area selection uses `.screenSaver`. No conflict since they don't coexist at launch.
- **Multi-monitor**: Only show splash on main screen (`NSScreen.main`), not all screens.
- **Animation timing**: Keep total sequence under 3s to avoid user frustration.

## Unresolved Questions

None at this time.
