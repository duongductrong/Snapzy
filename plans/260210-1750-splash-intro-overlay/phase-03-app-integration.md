# Phase 3: App Integration (Launch Flow)

**Status:** Pending
**Plan:** [plan.md](./plan.md)
**Depends on:** [Phase 1](./phase-01-splash-window.md), [Phase 2](./phase-02-splash-content-view.md)

## Context Links

- [SnapzyApp.swift](/Users/duongductrong/Developer/ZapShot/Snapzy/App/SnapzyApp.swift) - App entry point, AppDelegate

## Overview

Modify `AppDelegate.applicationDidFinishLaunching` to show splash on every launch. Splash dismiss triggers onboarding (if not completed) or does nothing (if already completed). Replace the current direct onboarding call.

## Key Insights

- Current flow: `applicationDidFinishLaunching` -> check `hasCompletedOnboarding` -> `showOnboardingWindow()` with 0.5s delay
- New flow: always show splash -> on continue -> check onboarding -> conditionally show onboarding
- The 0.5s delay for onboarding is no longer needed; splash provides the natural delay
- `showOnboardingWindow()` method stays unchanged; it is reused after splash dismisses

## Requirements

1. Splash shows on EVERY launch (not gated by onboarding state)
2. Splash shown from `applicationDidFinishLaunching` via `SplashWindowController.shared.show()`
3. Continue button callback: dismiss splash, then conditionally open onboarding
4. Remove existing direct onboarding call (replaced by splash flow)
5. "Restart Onboarding" notification handler stays unchanged

## Architecture

```
applicationDidFinishLaunching
  |-- StatusBarController.shared.setup(...)
  |-- SplashWindowController.shared.show(onContinue: {
  |       if !OnboardingFlowView.hasCompletedOnboarding {
  |           showOnboardingWindow()
  |       }
  |   })
  |-- NotificationCenter observer for .showOnboarding (unchanged)
```

## Related Code Files

| File | Relevance |
|------|-----------|
| `Snapzy/App/SnapzyApp.swift` | Lines 52-96, AppDelegate class |
| `Snapzy/Features/Onboarding/OnboardingFlowView.swift` | `hasCompletedOnboarding` static property |

## Implementation Steps

### Step 1: Modify AppDelegate.applicationDidFinishLaunching

Replace lines 63-67 in `SnapzyApp.swift`:

**Before:**
```swift
// Show onboarding on first launch
if !OnboardingFlowView.hasCompletedOnboarding {
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    self.showOnboardingWindow()
  }
}
```

**After:**
```swift
// Show splash on every launch
DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
  SplashWindowController.shared.show(onContinue: { [weak self] in
    // After splash dismisses, show onboarding if not completed
    if !OnboardingFlowView.hasCompletedOnboarding {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        self?.showOnboardingWindow()
      }
    }
  })
}
```

Key changes:
- Removed `if !hasCompletedOnboarding` guard -- splash always shows
- Splash `onContinue` callback replaces direct onboarding call
- 0.3s delay after splash dismiss before onboarding opens (smooth transition)
- 0.3s initial delay gives app time to set up status bar

### Step 2: Add Splash import (if needed)

No explicit import needed since all files are in the same Xcode target. Swift automatically resolves types within the same module.

## Todo List

- [ ] Replace onboarding launch code in AppDelegate with splash flow
- [ ] Test launch with onboarding NOT completed (splash -> continue -> onboarding)
- [ ] Test launch with onboarding completed (splash -> continue -> nothing)
- [ ] Test "Restart Onboarding" from preferences still works
- [ ] Verify no visual overlap between splash fade-out and onboarding window

## Success Criteria

- [x] Splash appears on every app launch
- [x] Continue button dismisses splash with fade animation
- [x] Onboarding opens after splash only when not previously completed
- [x] "Restart Onboarding" notification still works independently
- [x] No visual glitch between splash dismiss and onboarding appear
- [x] Changes to SnapzyApp.swift are minimal (~10 lines)

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Splash blocks status bar setup | Low | Status bar setup runs before splash `show()` |
| Double onboarding window | Low | `showOnboardingWindow()` checks for existing window |
| User quits during splash | Low | No state corruption; splash is purely visual |

## Next Steps

After all three phases are implemented:
1. Build and run to verify compile
2. Test full launch flow on both fresh install and returning user
3. Test light/dark mode appearance
4. Code review via `code-reviewer` agent
