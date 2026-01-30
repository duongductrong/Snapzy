//
//  OnboardingFlowView.swift
//  Snapzy
//
//  Coordinates the onboarding flow between views
//

import SwiftUI

enum OnboardingStep {
  case welcome
  case permissions
  case shortcuts
  case completion
}

struct OnboardingFlowView: View {
  @State private var currentStep: OnboardingStep = .welcome
  @ObservedObject private var screenCaptureManager = ScreenCaptureManager.shared

  let onComplete: () -> Void

  private static let onboardingCompletedKey = PreferencesKeys.onboardingCompleted

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
            withAnimation(.easeInOut(duration: 0.3)) {
              currentStep = .completion
            }
          },
          onAccept: {
            KeyboardShortcutManager.shared.enable()
            withAnimation(.easeInOut(duration: 0.3)) {
              currentStep = .completion
            }
          }
        )

      case .completion:
        CompletionView(
          onComplete: {
            completeOnboarding()
          }
        )
      }
    }
  }

  private func completeOnboarding() {
    UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
    onComplete()
  }

  static var hasCompletedOnboarding: Bool {
    UserDefaults.standard.bool(forKey: onboardingCompletedKey)
  }

  static func resetOnboarding() {
    UserDefaults.standard.set(false, forKey: onboardingCompletedKey)
  }
}

#Preview {
  OnboardingFlowView(onComplete: {})
    .frame(width: 500, height: 500)
}
