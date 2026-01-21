# Phase 04: ShortcutsView and Onboarding Flow Integration

## Context

- **Parent Plan:** [plan.md](../plan.md)
- **Dependencies:** Phases 01-03, KeyboardShortcutManager
- **Related Docs:** SwiftUI navigation patterns

## Overview

| Field | Value |
|-------|-------|
| Date | 260116 |
| Description | Implement ShortcutsView and OnboardingFlowView coordinator |
| Priority | High |
| Status | Pending |

## Requirements

### ShortcutsView
1. Centered VStack with command key icon (80x80)
2. Title: "Set as default screenshot tool?"
3. Subtitle about shortcuts (Shift+Cmd+3 and Shift+Cmd+4)
4. Bottom: "No, thanks" (secondary) and "Yes!" (primary)
5. Integrate with KeyboardShortcutManager.enable()/disable()

### OnboardingFlowView
1. Coordinate navigation: Welcome -> Permissions -> Shortcuts
2. Track current step with enum
3. Callback for completion
4. Optional: persist onboarding completion to UserDefaults

## Architecture

```swift
struct ShortcutsView: View {
  let onDecline: () -> Void
  let onAccept: () -> Void
}

enum OnboardingStep { case welcome, permissions, shortcuts }

struct OnboardingFlowView: View {
  @State private var currentStep: OnboardingStep = .welcome
  let onComplete: () -> Void
}
```

## Related Files

- `ZapShot/Core/KeyboardShortcutManager.swift` - enable(), disable()
- `ZapShot/App/ZapShotApp.swift` - integration point
- `ZapShot/Features/Onboarding/DesignSystem/VSDesignSystem.swift`

## Implementation

### Step 1: Create ShortcutsView.swift

**File:** `ZapShot/Features/Onboarding/Views/ShortcutsView.swift`

```swift
//
//  ShortcutsView.swift
//  ZapShot
//
//  Shortcuts setup screen for onboarding flow
//

import SwiftUI

struct ShortcutsView: View {
  let onDecline: () -> Void
  let onAccept: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      // Icon
      Image(systemName: "command")
        .font(.system(size: 50))
        .foregroundColor(.blue)
        .frame(width: 80, height: 80)
        .background(
          RoundedRectangle(cornerRadius: 18)
            .fill(Color.blue.opacity(0.1))
        )

      // Title
      Text("Set as default screenshot tool?")
        .vsHeading()

      // Subtitle
      Text("ZapShot can replace the default macOS screenshot shortcuts. Press ⇧⌘3 for fullscreen or ⇧⌘4 for area capture.")
        .vsBody()
        .multilineTextAlignment(.center)
        .frame(maxWidth: 320)

      Spacer()

      // Actions
      HStack(spacing: 16) {
        Button("No, thanks") {
          onDecline()
        }
        .buttonStyle(VSDesignSystem.SecondaryButtonStyle())

        Button("Yes!") {
          onAccept()
        }
        .buttonStyle(VSDesignSystem.PrimaryButtonStyle())
      }

      Spacer()
        .frame(height: 40)
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

#Preview {
  ShortcutsView(onDecline: {}, onAccept: {})
    .frame(width: 500, height: 400)
}
```

### Step 2: Create OnboardingFlowView.swift

**File:** `ZapShot/Features/Onboarding/OnboardingFlowView.swift`

```swift
//
//  OnboardingFlowView.swift
//  ZapShot
//
//  Coordinates the onboarding flow between views
//

import SwiftUI

enum OnboardingStep {
  case welcome
  case permissions
  case shortcuts
}

struct OnboardingFlowView: View {
  @State private var currentStep: OnboardingStep = .welcome
  @ObservedObject private var screenCaptureManager = ScreenCaptureManager.shared

  let onComplete: () -> Void

  private static let onboardingCompletedKey = "onboardingCompleted"

  var body: some View {
    Group {
      switch currentStep {
      case .welcome:
        WelcomeView(onContinue: {
          withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = .permissions
          }
        })

      case .permissions:
        PermissionsView(
          screenCaptureManager: screenCaptureManager,
          onQuit: {
            NSApplication.shared.terminate(nil)
          },
          onNext: {
            withAnimation(.easeInOut(duration: 0.3)) {
              currentStep = .shortcuts
            }
          }
        )

      case .shortcuts:
        ShortcutsView(
          onDecline: {
            completeOnboarding(enableShortcuts: false)
          },
          onAccept: {
            completeOnboarding(enableShortcuts: true)
          }
        )
      }
    }
  }

  private func completeOnboarding(enableShortcuts: Bool) {
    if enableShortcuts {
      KeyboardShortcutManager.shared.enable()
    }
    UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
    onComplete()
  }

  static var hasCompletedOnboarding: Bool {
    UserDefaults.standard.bool(forKey: onboardingCompletedKey)
  }
}

#Preview {
  OnboardingFlowView(onComplete: {})
    .frame(width: 500, height: 450)
}
```

### Step 3: Integration Notes for ZapShotApp.swift

To integrate onboarding, modify `ZapShotApp.swift`:

```swift
@main
struct ZapShotApp: App {
  @State private var showOnboarding = !OnboardingFlowView.hasCompletedOnboarding

  var body: some Scene {
    WindowGroup {
      if showOnboarding {
        OnboardingFlowView(onComplete: {
          showOnboarding = false
        })
        .frame(width: 500, height: 450)
      } else {
        ContentView()
      }
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)

    Settings {
      PreferencesView()
    }
  }
}
```

## Todo

- [ ] Create ShortcutsView.swift with icon, title, subtitle, buttons
- [ ] Create OnboardingFlowView.swift with step navigation
- [ ] Add UserDefaults persistence for completion state
- [ ] Wire KeyboardShortcutManager.enable() on acceptance
- [ ] Add integration notes for ZapShotApp.swift
- [ ] Add previews for visual verification
- [ ] Verify compilation

## Success Criteria

- [ ] ShortcutsView displays centered content with command icon
- [ ] Subtitle shows shortcut symbols (shift+cmd+3/4)
- [ ] "Yes!" enables shortcuts via KeyboardShortcutManager
- [ ] "No, thanks" completes without enabling shortcuts
- [ ] OnboardingFlowView navigates through all three steps
- [ ] Onboarding completion persists to UserDefaults
- [ ] Flow only shows on first launch
- [ ] Code compiles without errors
