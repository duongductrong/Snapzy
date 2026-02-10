# Onboarding Premium Migration Plan

**Date:** 2026-02-10
**Goal:** Migrate onboarding flow into the splash overlay window with premium dark/blur styling. Eliminate the jarring window-switch between splash dismiss and onboarding open.

## Problem

Current flow: `SplashWindow` dismisses (fade out) -> 300ms delay -> separate `WindowGroup(id: "onboarding")` opens. This creates a visible gap — blur disappears, new window pops up, breaking immersion.

## Solution

Host onboarding steps **inside** the existing `SplashWindow` NSPanel. The blur background persists throughout the entire flow. Splash content cross-fades into onboarding content within the same window.

## Architecture

```
SplashWindowController.show()
  -> SplashWindow (NSPanel, stays open through entire flow)
     -> SplashOnboardingRootView (SwiftUI, manages all screen transitions)
        -> .splash       => SplashContentView (intro animation)
        -> .permissions  => PermissionsView (dark theme)
        -> .shortcuts    => ShortcutsView (dark theme)
        -> .completion   => CompletionView (dark theme)
     -> on complete: fade out entire window
```

## Phases

| Phase | Summary | Files | Risk |
|-------|---------|-------|------|
| [Phase 1](./phase-01-unified-root-view.md) | Create `SplashOnboardingRootView` as unified screen coordinator | 1 new file | Low |
| [Phase 2](./phase-02-dark-theme-onboarding.md) | Restyle all onboarding views to dark/frosted theme | 6 modified files | Medium |
| [Phase 3](./phase-03-integration.md) | Wire controller + remove `WindowGroup(id: "onboarding")` | 2 modified files | Medium |

## Key Decisions

1. **WelcomeView eliminated** — SplashContentView already serves as welcome screen (logo, title, subtitle, CTA). No duplication needed.
2. **VSDesignSystem updated in-place** — button styles switch to frosted capsule style matching splash. `.vsHeading()` / `.vsBody()` updated to white text.
3. **SplashWindowController.show() signature changes** — no longer takes `onContinue` callback; the root view handles all flow internally and calls dismiss when done.
4. **Onboarding skip path preserved** — if `hasCompletedOnboarding == true`, splash shows intro then dismisses directly (no onboarding steps).

## File Inventory

| Action | File |
|--------|------|
| CREATE | `Snapzy/Features/Splash/SplashOnboardingRootView.swift` |
| MODIFY | `Snapzy/Features/Onboarding/OnboardingFlowView.swift` |
| MODIFY | `Snapzy/Features/Onboarding/Views/PermissionsView.swift` |
| MODIFY | `Snapzy/Features/Onboarding/Views/ShortcutsView.swift` |
| MODIFY | `Snapzy/Features/Onboarding/Views/CompletionView.swift` |
| MODIFY | `Snapzy/Features/Onboarding/Views/PermissionRow.swift` |
| MODIFY | `Snapzy/Features/Onboarding/DesignSystem/VSDesignSystem.swift` |
| MODIFY | `Snapzy/Features/Splash/SplashWindow.swift` |
| MODIFY | `Snapzy/App/SnapzyApp.swift` |
| DELETE | `Snapzy/Features/Onboarding/Views/WelcomeView.swift` (or keep as dead code, remove later) |

## Transition Spec

| Transition | Animation | Duration |
|------------|-----------|----------|
| Splash -> First onboarding step | Cross-fade (opacity) with slight upward offset | 0.4s easeOut |
| Between onboarding steps | Asymmetric slide+fade (out left, in from right) | 0.4s easeInOut |
| Final completion -> Window dismiss | Content fade out, then window alpha -> 0 | 0.4s easeIn |

## Success Criteria

- No visible window switch during splash -> onboarding transition
- Blur background persists from launch until onboarding completes
- All onboarding views readable with white-on-blur styling
- Permission checking/granting still works correctly
- "Restart Onboarding" from preferences triggers splash with full onboarding
- Existing users (onboarding completed) see splash intro then dismiss only
