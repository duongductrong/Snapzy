//
//  SplashOnboardingRootView.swift
//  Snapzy
//
//  Unified coordinator managing splash intro, sponsor prompt, and onboarding.
//

import SwiftUI

enum SplashScreen: Equatable {
  case splash
  case sponsor
  case permissions
  case shortcuts
  case diagnostics
  case completion
}

private enum NavigationDirection {
  case forward
}

struct SplashOnboardingRootView: View {
  let needsOnboarding: Bool
  let showSponsorPrompt: Bool
  let onDismiss: () -> Void

  @State private var currentScreen: SplashScreen = .splash
  @State private var contentOpacity: Double = 1
  @State private var navigationDirection: NavigationDirection = .forward
  @ObservedObject private var screenCaptureManager = ScreenCaptureManager.shared

  private static let onboardingSteps: [SplashScreen] = [
    .permissions, .shortcuts, .diagnostics, .completion,
  ]

  private var isOnboardingStep: Bool {
    Self.onboardingSteps.contains(currentScreen)
  }

  private var currentStepIndex: Int {
    Self.onboardingSteps.firstIndex(of: currentScreen) ?? 0
  }

  var body: some View {
    ZStack {
      Color.clear

      Group {
        switch currentScreen {
        case .splash:
          SplashContentView(onContinue: handleSplashContinue)
            .transition(.opacity)

        case .sponsor:
          SponsorView(onContinue: handleSponsorContinue)
            .transition(.opacity)

        case .permissions:
          PermissionsView(
            screenCaptureManager: screenCaptureManager,
            onQuit: { NSApplication.shared.terminate(nil) },
            onNext: { navigateForward(to: .shortcuts) }
          )
          .transition(stepTransition)

        case .shortcuts:
          ShortcutsView(
            onDecline: { navigateForward(to: .diagnostics) },
            onAccept: {
              KeyboardShortcutManager.shared.enable()
              navigateForward(to: .diagnostics)
            }
          )
          .transition(stepTransition)

        case .diagnostics:
          DiagnosticsOptInView(
            onNext: { navigateForward(to: .completion) }
          )
          .transition(stepTransition)

        case .completion:
          CompletionView(
            onComplete: handleComplete
          )
          .transition(stepTransition)
        }
      }
      .opacity(contentOpacity)

      if isOnboardingStep {
        VStack {
          Spacer()
          HStack(spacing: 8) {
            ForEach(0..<Self.onboardingSteps.count, id: \.self) { index in
              Circle()
                .fill(index == currentStepIndex ? VSDesignSystem.Colors.primary : VSDesignSystem.Colors.quaternary)
                .frame(width: 7, height: 7)
                .animation(.easeInOut(duration: 0.3), value: currentStepIndex)
            }
          }
          .padding(.bottom, 32)
        }
        .opacity(contentOpacity)
        .transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var stepTransition: AnyTransition {
    switch navigationDirection {
    case .forward:
      return .asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
      )
    }
  }

  private func handleSplashContinue() {
    if showSponsorPrompt {
      navigateForward(to: .sponsor)
    } else if needsOnboarding {
      navigateForward(to: .permissions)
    } else {
      dismiss()
    }
  }

  private func handleSponsorContinue() {
    UserDefaults.standard.set(true, forKey: PreferencesKeys.sponsorPromptSeen)

    if needsOnboarding {
      navigateForward(to: .permissions)
    } else {
      dismiss()
    }
  }

  private func navigateForward(to screen: SplashScreen) {
    navigationDirection = .forward
    withAnimation(.easeInOut(duration: 0.4)) {
      currentScreen = screen
    }
  }

  private func handleComplete() {
    UserDefaults.standard.set(true, forKey: PreferencesKeys.onboardingCompleted)
    UserDefaults.standard.set(true, forKey: PreferencesKeys.sponsorPromptSeen)
    dismiss()
  }

  private func dismiss() {
    withAnimation(.easeIn(duration: 0.3)) {
      contentOpacity = 0
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
      onDismiss()
    }
  }
}

#Preview {
  SplashOnboardingRootView(
    needsOnboarding: true,
    showSponsorPrompt: true,
    onDismiss: {}
  )
  .frame(width: 800, height: 600)
  .background(.black.opacity(0.5))
}
