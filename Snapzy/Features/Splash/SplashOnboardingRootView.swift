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
  case diagnostics
  case shortcuts
  case completion
}

// MARK: - Navigation Direction

private enum NavigationDirection {
  case forward, backward
}

// MARK: - SplashOnboardingRootView

struct SplashOnboardingRootView: View {
  let needsOnboarding: Bool
  let onDismiss: () -> Void

  @State private var currentScreen: SplashScreen = .splash
  @State private var contentOpacity: Double = 1
  @State private var navigationDirection: NavigationDirection = .forward
  @ObservedObject private var screenCaptureManager = ScreenCaptureManager.shared

  // Onboarding steps (excluding splash)
  private static let onboardingSteps: [SplashScreen] = [.permissions, .diagnostics, .shortcuts, .completion]

  private var isOnboardingStep: Bool {
    currentScreen != .splash
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

        case .permissions:
          PermissionsView(
            screenCaptureManager: screenCaptureManager,
            onQuit: { NSApplication.shared.terminate(nil) },
            onNext: { navigateForward(to: .diagnostics) }
          )
          .transition(stepTransition)

        case .diagnostics:
          DiagnosticsOptInView(
            onNext: { navigateForward(to: .shortcuts) }
          )
          .transition(stepTransition)

        case .shortcuts:
          ShortcutsView(
            onDecline: { navigateForward(to: .completion) },
            onAccept: {
              KeyboardShortcutManager.shared.enable()
              navigateForward(to: .completion)
            }
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


      // Page dots — bottom center, only during onboarding steps
      if isOnboardingStep {
        VStack {
          Spacer()
          HStack(spacing: 8) {
            ForEach(0..<Self.onboardingSteps.count, id: \.self) { index in
              Circle()
                .fill(index == currentStepIndex ? Color.white : Color.white.opacity(0.3))
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

  // MARK: - Transitions

  private var stepTransition: AnyTransition {
    switch navigationDirection {
    case .forward:
      return .asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
      )
    case .backward:
      return .asymmetric(
        insertion: .move(edge: .leading).combined(with: .opacity),
        removal: .move(edge: .trailing).combined(with: .opacity)
      )
    }
  }

  // MARK: - Navigation

  private func handleSplashContinue() {
    if needsOnboarding {
      navigateForward(to: .permissions)
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

  private func navigateForward(to screen: SplashScreen) {
    navigationDirection = .forward
    withAnimation(.easeInOut(duration: 0.4)) {
      currentScreen = screen
    }
  }

  private func navigateBack(to screen: SplashScreen) {
    navigationDirection = .backward
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
