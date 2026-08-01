//
//  SplashOnboardingRootView.swift
//  Snapzy
//
//  Unified coordinator managing splash intro, sponsor prompt, and onboarding.
//

import SwiftUI

enum SplashScreen: Equatable {
  case splash
  case language
  case sponsor
  case permissions
  case configAccess
  case shortcuts
  case diagnostics
  case completion
}

private enum NavigationDirection {
  case forward
  case backward
}

struct SplashOnboardingRootView: View {
  let needsOnboarding: Bool
  let showSponsorPrompt: Bool
  let onDismiss: () -> Void

  private let onboardingSteps: [SplashScreen]
  @State private var currentScreen: SplashScreen = .splash
  @State private var contentOpacity: Double = 1
  @State private var navigationDirection: NavigationDirection = .forward
  @State private var isCompletingOnboarding = false
  @StateObject private var onboardingLocalization = OnboardingLocalizationController()
  @ObservedObject private var screenCaptureManager = ScreenCaptureManager.shared

  private static let defaultOnboardingSteps: [SplashScreen] = [
    .language, .permissions, .configAccess, .shortcuts, .diagnostics, .completion,
  ]

  init(
    needsOnboarding: Bool,
    showSponsorPrompt: Bool,
    initialScreen: SplashScreen = .splash,
    onboardingSteps: [SplashScreen]? = nil,
    onDismiss: @escaping () -> Void
  ) {
    self.needsOnboarding = needsOnboarding
    self.showSponsorPrompt = showSponsorPrompt
    self.onboardingSteps = onboardingSteps ?? Self.defaultOnboardingSteps
    self.onDismiss = onDismiss
    _currentScreen = State(initialValue: initialScreen)
  }

  private var isOnboardingStep: Bool {
    onboardingSteps.contains(currentScreen)
  }

  private var currentStepIndex: Int {
    onboardingSteps.firstIndex(of: currentScreen) ?? 0
  }

  var body: some View {
    ZStack {
      // Stable opaque base — extends behind titlebar for seamless look
      OnboardingSurfaceBackground()
        .ignoresSafeArea()

      Group {
        switch currentScreen {
        case .splash:
          SplashContentView(onContinue: { skipSplash in handleSplashContinue(skipSplash: skipSplash) })
            .transition(.opacity)

        case .language:
          OnboardingLanguageSelectionView(
            onBack: { navigateBackward(to: .splash) },
            onContinue: handleLanguageContinue
          )
          .transition(stepTransition)

        case .sponsor:
          SponsorView(onContinue: handleSponsorContinue)
            .transition(.opacity)

        case .permissions:
          PermissionsView(
            screenCaptureManager: screenCaptureManager,
            onBack: { navigateBackward(to: showSponsorPrompt ? .sponsor : .language) },
            onNext: { navigateForward(to: .configAccess) }
          )
          .transition(stepTransition)

        case .configAccess:
          ConfigAccessView(
            onBack: needsOnboarding ? { navigateBackward(to: .permissions) } : nil,
            onComplete: handleConfigAccessContinue,
            onSkip: handleConfigAccessContinue
          )
          .transition(stepTransition)

        case .shortcuts:
          ShortcutsView(
            onBack: { navigateBackward(to: .configAccess) },
            onDecline: { navigateForward(to: .diagnostics) },
            onAccept: {
              KeyboardShortcutManager.shared.enable()
              navigateForward(to: .diagnostics)
            }
          )
          .transition(stepTransition)

        case .diagnostics:
          DiagnosticsOptInView(
            onBack: { navigateBackward(to: .shortcuts) },
            onNext: { navigateForward(to: .completion) }
          )
          .transition(stepTransition)

        case .completion:
          CompletionView(
            onBack: { navigateBackward(to: .diagnostics) },
            onComplete: handleComplete
          )
          .transition(stepTransition)
        }
      }
      .opacity(contentOpacity)
      .environmentObject(onboardingLocalization)

      if isOnboardingStep {
        VStack {
          Spacer()
          HStack(spacing: 8) {
            ForEach(0..<onboardingSteps.count, id: \.self) { index in
              Circle()
                .fill(index == currentStepIndex ? VSDesignSystem.Colors.primary : VSDesignSystem.Colors.quaternary)
                .frame(
                  width: VSDesignSystem.Metrics.pageIndicatorDot,
                  height: VSDesignSystem.Metrics.pageIndicatorDot
                )
                .animation(.easeInOut(duration: 0.3), value: currentStepIndex)
            }
          }
          // `OnboardingStepContainer` reserves `Metrics.pageIndicatorArea` for this row.
          .padding(.bottom, VSDesignSystem.Metrics.pageIndicatorBottomPadding)
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
    case .backward:
      return .asymmetric(
        insertion: .move(edge: .leading).combined(with: .opacity),
        removal: .move(edge: .trailing).combined(with: .opacity)
      )
    }
  }

  private func handleSplashContinue(skipSplash: Bool) {
    if skipSplash {
      UserDefaults.standard.set(true, forKey: PreferencesKeys.splashSkipped)
    }

    if needsOnboarding {
      navigateForward(to: .language)
    } else if showSponsorPrompt {
      navigateForward(to: .sponsor)
    } else {
      dismiss()
    }
  }

  private func handleLanguageContinue() {
    if showSponsorPrompt {
      navigateForward(to: .sponsor)
    } else {
      navigateForward(to: .permissions)
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

  private func handleConfigAccessContinue() {
    if needsOnboarding {
      navigateForward(to: .shortcuts)
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

  private func navigateBackward(to screen: SplashScreen) {
    navigationDirection = .backward
    withAnimation(.easeInOut(duration: 0.4)) {
      currentScreen = screen
    }
  }

  private func handleComplete() {
    guard !isCompletingOnboarding else { return }
    isCompletingOnboarding = true
    UserDefaults.standard.set(true, forKey: PreferencesKeys.onboardingCompleted)
    UserDefaults.standard.set(true, forKey: PreferencesKeys.sponsorPromptSeen)
    let requiresRelaunch = onboardingLocalization.requiresRelaunchOnCompletion
    onboardingLocalization.commitLanguageSelection()

    if requiresRelaunch {
      UserDefaults.standard.set(true, forKey: PreferencesKeys.splashSkipOnceAfterOnboardingRelaunch)
      fadeOut {
        Task {
          do {
            try await onboardingLocalization.relaunchApplication()
          } catch {
            self.isCompletingOnboarding = false
            self.onDismiss()
          }
        }
      }
    } else {
      dismiss()
    }
  }

  private func dismiss() {
    fadeOut {
      onDismiss()
    }
  }

  private func fadeOut(completion: @escaping () -> Void) {
    withAnimation(.easeIn(duration: 0.3)) {
      contentOpacity = 0
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
      completion()
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
}
