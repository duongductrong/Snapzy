//
//  OnboardingFlowView.swift
//  ClaudeShot
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

  static func resetOnboarding() {
    UserDefaults.standard.set(false, forKey: onboardingCompletedKey)
  }
}

#Preview {
  OnboardingFlowView(onComplete: {})
    .frame(width: 500, height: 450)
}
