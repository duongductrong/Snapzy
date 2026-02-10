# Phase 3: Integration

**Parent:** [plan.md](./plan.md)

## Context

- `SplashWindowController` (L76-134 of `SplashWindow.swift`) — singleton, `show(onContinue:)` creates window, attaches `SplashContentView`, dismiss fades out
- `SnapzyApp.swift` (L17-97) — has `WindowGroup(id: "onboarding")` for separate onboarding window, `AppDelegate` calls splash then opens onboarding window after dismiss
- `SplashOnboardingRootView` (created in Phase 1) — unified view managing splash + onboarding steps

## Overview

Rewire `SplashWindowController` to host `SplashOnboardingRootView` instead of just `SplashContentView`. Remove the separate `WindowGroup(id: "onboarding")` from `SnapzyApp`. The splash window now owns the entire first-run experience.

## Key Insights

1. **`show()` signature simplifies** — no more `onContinue` callback. The root view handles all flow internally; it calls `dismiss()` when done.
2. **Two show modes**: `show()` for normal launch (checks `hasCompletedOnboarding`), and `show(forceOnboarding: true)` for "Restart Onboarding" from preferences.
3. **`WindowGroup(id: "onboarding")` removal** eliminates the SwiftUI-managed window entirely. This is safe because onboarding now lives inside the NSPanel.
4. **Notification handler** `.showOnboarding` now calls `SplashWindowController.shared.show(forceOnboarding: true)` instead of `showOnboardingWindow()`.

## Related Code Files

| File | Path | Lines | Changes |
|------|------|-------|---------|
| SplashWindow | `Snapzy/Features/Splash/SplashWindow.swift` | 135 | Controller `show()` rewired, `dismiss()` simplified |
| SnapzyApp | `Snapzy/App/SnapzyApp.swift` | 97 | Remove `WindowGroup(id: "onboarding")`, simplify AppDelegate |

## Requirements

1. `SplashWindowController.show()` must create `SplashOnboardingRootView` with `needsOnboarding` flag
2. `needsOnboarding` derived from `!OnboardingFlowView.hasCompletedOnboarding`
3. `show(forceOnboarding: true)` must reset onboarding state and show full flow
4. `dismiss()` remains the same (fade out window alpha, close, nil reference)
5. Remove `WindowGroup(id: "onboarding")` from `SnapzyApp.body`
6. Remove `showOnboardingWindow()` method from `AppDelegate`
7. Remove `@AppStorage(PreferencesKeys.onboardingCompleted)` from `SnapzyApp` (no longer needed at Scene level)
8. Notification `.showOnboarding` handler calls splash controller directly

## Implementation Steps

### SplashWindow.swift — SplashWindowController

- [ ] Change `show(onContinue:)` to `show(forceOnboarding: Bool = false)`
- [ ] Inside `show()`: compute `needsOnboarding = forceOnboarding || !OnboardingFlowView.hasCompletedOnboarding`
- [ ] If `forceOnboarding`, call `OnboardingFlowView.resetOnboarding()` before showing
- [ ] Create `SplashOnboardingRootView(needsOnboarding: needsOnboarding, onDismiss: { [weak self] in self?.dismiss() })`
- [ ] Attach root view via `window.attachContent(rootView)` (replaces `SplashContentView`)
- [ ] Remove the `onContinue` callback pattern entirely
- [ ] Simplify `dismiss()` — remove `completion` parameter, just fade out and clean up
- [ ] Add `dismiss()` as a no-arg method (the root view triggers it when flow completes)
- [ ] Guard against double-show: if `splashWindow != nil`, return early
- [ ] Keep `animateBlurIn()` unchanged

**Updated `show()` signature:**
```swift
func show(forceOnboarding: Bool = false) {
    guard splashWindow == nil, let screen = NSScreen.main else { return }

    let needsOnboarding = forceOnboarding || !OnboardingFlowView.hasCompletedOnboarding
    if forceOnboarding {
        OnboardingFlowView.resetOnboarding()
    }

    let window = SplashWindow(screen: screen)
    self.splashWindow = window

    let rootView = SplashOnboardingRootView(
        needsOnboarding: needsOnboarding,
        onDismiss: { [weak self] in
            self?.dismiss()
        }
    )
    window.attachContent(rootView)

    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
        self?.animateBlurIn()
    }
}
```

**Updated `dismiss()`:**
```swift
func dismiss() {
    guard let window = splashWindow else { return }

    NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.4
        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
        window.animator().alphaValue = 0
    }, completionHandler: { [weak self] in
        window.orderOut(nil)
        window.close()
        self?.splashWindow = nil
    })
}
```

### SnapzyApp.swift

- [ ] Remove entire `WindowGroup(id: "onboarding") { ... }` block (lines 25-40)
- [ ] Remove `@AppStorage(PreferencesKeys.onboardingCompleted) private var onboardingCompleted = false` (line 21)
- [ ] Remove `Notification.Name.showOnboarding` extension (move to a shared location if needed, or keep if used elsewhere)
- [ ] Simplify `AppDelegate.applicationDidFinishLaunching`:
  - Remove the `onContinue` closure that checks `hasCompletedOnboarding` and calls `showOnboardingWindow()`
  - Replace with: `SplashWindowController.shared.show()`
- [ ] Update `handleShowOnboarding()`: replace `showOnboardingWindow()` with `SplashWindowController.shared.show(forceOnboarding: true)`
- [ ] Remove `showOnboardingWindow()` method entirely
- [ ] Keep `StatusBarController.shared.setup(...)` call unchanged

**Updated AppDelegate:**
```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = ScreenCaptureViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        StatusBarController.shared.setup(
            viewModel: viewModel,
            updater: UpdaterManager.shared.updater
        )

        // Show splash (handles onboarding internally if needed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            SplashWindowController.shared.show()
        }

        // Listen for restart onboarding notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowOnboarding),
            name: .showOnboarding,
            object: nil
        )
    }

    @objc private func handleShowOnboarding() {
        SplashWindowController.shared.show(forceOnboarding: true)
    }
}
```

### Post-Integration Cleanup

- [ ] Verify `WelcomeView.swift` is no longer referenced anywhere; mark for deletion or delete
- [ ] Verify `OnboardingFlowView` static methods (`hasCompletedOnboarding`, `resetOnboarding`) still accessible from `SplashOnboardingRootView` and `SplashWindowController`
- [ ] Check if any other file references `WindowGroup(id: "onboarding")` or `showOnboardingWindow()`
- [ ] Check if `.showOnboarding` notification name is used in Preferences — keep the notification extension if so

## Todo List

```
- [ ] Update SplashWindowController.show() to host SplashOnboardingRootView
- [ ] Simplify SplashWindowController.dismiss() (remove completion param)
- [ ] Add forceOnboarding parameter and reset logic
- [ ] Add double-show guard
- [ ] Remove WindowGroup(id: "onboarding") from SnapzyApp
- [ ] Remove @AppStorage onboardingCompleted from SnapzyApp
- [ ] Simplify AppDelegate — remove showOnboardingWindow()
- [ ] Update handleShowOnboarding to use forceOnboarding
- [ ] Verify compile
- [ ] End-to-end test: fresh launch, returning user, restart onboarding
```

## Success Criteria

- Fresh launch: splash animates in -> "Continue" -> permissions -> shortcuts -> completion -> window fades out. Single window throughout.
- Returning user (onboarding completed): splash animates in -> "Continue" -> window fades out immediately. No onboarding steps shown.
- Restart onboarding from preferences: splash opens with full onboarding flow, regardless of previous completion state.
- No `WindowGroup(id: "onboarding")` in the app. No separate onboarding window ever appears.
- No orphaned references to removed code.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Removing WindowGroup breaks SnapzyApp Scene body (needs at least one Scene) | Medium | High | `Settings { ... }` scene remains, satisfying SwiftUI's requirement for at least one scene in the body. Verify the app launches without a primary window. Add `.commands { }` or `MenuBarExtra` if needed. |
| `SettingsLink` in CompletionView requires a Settings scene to exist | Medium | High | Keep `Settings { PreferencesView() }` scene in SnapzyApp — it already exists and is unaffected |
| Double-tap "Restart Onboarding" while splash is visible | Low | Low | Guard in `show()`: `guard splashWindow == nil` prevents double creation |
| NSPanel not receiving key events after removing WindowGroup | Low | Medium | `SplashWindow.canBecomeKey` already returns `true`; `makeKeyAndOrderFront` is called in `show()` |

## Next Steps

After all three phases are complete:
1. Build and verify compile (`Cmd+B`)
2. Run full end-to-end test (fresh install, returning user, restart onboarding)
3. Visual polish pass — adjust opacity values, animation timings if needed
4. Delete `WelcomeView.swift` if confirmed unused
5. Update `docs/codebase-summary.md` if the onboarding architecture section changes
