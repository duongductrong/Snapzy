//
//  SplashOnboardingRootView.swift
//  Snapzy
//
//  Unified coordinator managing splash intro → onboarding flow within the same window
//

import SwiftUI

// MARK: - Screen Enum

enum SplashScreen: Equatable {
  case splash
  case permissions
  case shortcuts
  case completion
}

// MARK: - SplashOnboardingRootView

struct SplashOnboardingRootView: View {
  let needsOnboarding: Bool
  let onDismiss: () -> Void

  @State private var currentScreen: SplashScreen = .splash
  @State private var contentOpacity: Double = 1
  @ObservedObject private var screenCaptureManager = ScreenCaptureManager.shared

  var body: some View {
    ZStack {
      Color.clear

      Group {
        switch currentScreen {
        case .splash:
          SplashContentView(onContinue: handleSplashContinue)
            .transition(.opacity)

        case .permissions:
          PermissionsView(
            screenCaptureManager: screenCaptureManager,
            onQuit: { NSApplication.shared.terminate(nil) },
            onNext: { navigateTo(.shortcuts) }
          )
          .transition(stepTransition)

        case .shortcuts:
          ShortcutsView(
            onDecline: { navigateTo(.completion) },
            onAccept: {
              KeyboardShortcutManager.shared.enable()
              navigateTo(.completion)
            }
          )
          .transition(stepTransition)

        case .completion:
          CompletionView(onComplete: handleComplete)
            .transition(stepTransition)
        }
      }
      .opacity(contentOpacity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Transitions

  private var stepTransition: AnyTransition {
    .asymmetric(
      insertion: .move(edge: .trailing).combined(with: .opacity),
      removal: .move(edge: .leading).combined(with: .opacity)
    )
  }

  // MARK: - Navigation

  private func handleSplashContinue() {
    if needsOnboarding {
      navigateTo(.permissions)
    } else {
      // No onboarding needed — fade out and dismiss
      withAnimation(.easeIn(duration: 0.3)) {
        contentOpacity = 0
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        onDismiss()
      }
    }
  }

  private func navigateTo(_ screen: SplashScreen) {
    withAnimation(.easeInOut(duration: 0.4)) {
      currentScreen = screen
    }
  }

  private func handleComplete() {
    // Mark onboarding as completed
    UserDefaults.standard.set(true, forKey: PreferencesKeys.onboardingCompleted)

    // Fade out content, then dismiss window
    withAnimation(.easeIn(duration: 0.3)) {
      contentOpacity = 0
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
      onDismiss()
    }
  }
}

#Preview {
  SplashOnboardingRootView(needsOnboarding: true, onDismiss: {})
    .frame(width: 800, height: 600)
    .background(.black.opacity(0.5))
}
