# Phase 1: Unified Root View

**Parent:** [plan.md](./plan.md)

## Context

- `SplashContentView` (L18-138 of `SplashContentView.swift`) — handles splash intro animation with phased states
- `OnboardingFlowView` (L17-85 of `OnboardingFlowView.swift`) — coordinates onboarding steps via `OnboardingStep` enum
- `SplashWindowController.show()` (L84-105 of `SplashWindow.swift`) — currently creates window, attaches `SplashContentView`, passes `onContinue` callback

## Overview

Create a single SwiftUI view that manages the entire lifecycle within the splash window: splash intro -> onboarding steps -> dismiss. This view replaces the current pattern where `SplashContentView` triggers a callback that dismisses the splash and opens a separate window.

## Key Insight

The root view owns a `@State var currentScreen` enum. When splash "Continue" is tapped, instead of calling `onContinue` (which dismisses the window), it transitions `currentScreen` from `.splash` to `.permissions`. The blur NSPanel stays open. The SwiftUI content cross-fades.

## Architecture

```swift
// SplashOnboardingRootView.swift

enum SplashScreen {
    case splash
    case permissions
    case shortcuts
    case completion
}

struct SplashOnboardingRootView: View {
    @State private var currentScreen: SplashScreen = .splash
    @ObservedObject private var screenCaptureManager = ScreenCaptureManager.shared
    let needsOnboarding: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.clear

            Group {
                switch currentScreen {
                case .splash:
                    SplashContentView(onContinue: { handleSplashContinue() })
                case .permissions:
                    PermissionsView(...)
                case .shortcuts:
                    ShortcutsView(...)
                case .completion:
                    CompletionView(...)
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.easeInOut(duration: 0.4), value: currentScreen)
        }
    }

    private func handleSplashContinue() {
        if needsOnboarding {
            withAnimation { currentScreen = .permissions }
        } else {
            onDismiss()
        }
    }
}
```

## Related Code Files

| File | Path | Relevance |
|------|------|-----------|
| SplashContentView | `Snapzy/Features/Splash/SplashContentView.swift` | Splash intro view, reused as-is |
| OnboardingFlowView | `Snapzy/Features/Onboarding/OnboardingFlowView.swift` | Step coordination logic to absorb |
| SplashWindow | `Snapzy/Features/Splash/SplashWindow.swift` | Will attach this new root view |

## Requirements

1. `SplashScreen` enum must be `Hashable` / `Equatable` for SwiftUI animation
2. Must accept `needsOnboarding: Bool` to skip onboarding for returning users
3. Must accept `onDismiss: () -> Void` to trigger window fade-out
4. Cross-fade from splash to first onboarding step (no window close/open)
5. Step transitions: slide+fade asymmetric (out left, in from right)
6. Must pass `screenCaptureManager` to `PermissionsView`
7. Must call `KeyboardShortcutManager.shared.enable()` when user accepts shortcuts
8. Must call `UserDefaults.standard.set(true, forKey: PreferencesKeys.onboardingCompleted)` on completion

## Implementation Steps

- [ ] Create file `Snapzy/Features/Splash/SplashOnboardingRootView.swift`
- [ ] Define `SplashScreen` enum with cases: `.splash`, `.permissions`, `.shortcuts`, `.completion`
- [ ] Implement `SplashOnboardingRootView` with `@State var currentScreen: SplashScreen`
- [ ] Wire `SplashContentView.onContinue` to transition to `.permissions` (or dismiss if no onboarding needed)
- [ ] Wire `PermissionsView.onNext` to transition to `.shortcuts`
- [ ] Wire `PermissionsView.onQuit` to `NSApplication.shared.terminate(nil)`
- [ ] Wire `ShortcutsView.onAccept` to enable shortcuts + transition to `.completion`
- [ ] Wire `ShortcutsView.onDecline` to transition to `.completion`
- [ ] Wire `CompletionView.onComplete` to set `onboardingCompleted = true` then call `onDismiss`
- [ ] Add `.animation(.easeInOut(duration: 0.4), value: currentScreen)` on container
- [ ] Add asymmetric transition: insertion `.move(edge: .trailing).combined(with: .opacity)`, removal `.move(edge: .leading).combined(with: .opacity)`
- [ ] Special case: splash -> permissions uses pure `.opacity` transition (no slide) for a softer cross-fade
- [ ] Keep file under 100 lines (coordinator only, no UI duplication)
- [ ] Add `#Preview` with both `needsOnboarding: true` and `false` variants

## Todo List

```
- [ ] Create SplashOnboardingRootView.swift
- [ ] Define SplashScreen enum
- [ ] Implement screen switching with transitions
- [ ] Wire all onboarding step callbacks
- [ ] Add animation modifiers
- [ ] Verify compile
```

## Success Criteria

- File compiles with no errors
- Enum covers all screens without duplication of `OnboardingStep`
- `needsOnboarding: false` path goes directly from splash to dismiss
- `needsOnboarding: true` path flows through all onboarding steps
- Transitions are smooth cross-fades / slides (no jarring cuts)

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| SwiftUI `Group` + `switch` may not animate transitions | Medium | High | Use `ZStack` with `if` checks + explicit `.id()` keying, or use `.transition()` on each case |
| `SplashScreen` conflicts with existing `OnboardingStep` enum | Low | Low | They serve different purposes; `SplashScreen` is the unified superset |

## Next Steps

After this phase, proceed to [Phase 2](./phase-02-dark-theme-onboarding.md) to restyle onboarding views for dark/blur background.
