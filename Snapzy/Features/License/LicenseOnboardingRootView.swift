//
//  LicenseOnboardingRootView.swift
//  Snapzy
//
//  Updated coordinator managing splash → license → onboarding flow
//

import SwiftUI

// MARK: - Screen Enum

enum OnboardingScreen: Equatable {
    case splash
    case license
    case permissions
    case shortcuts
    case skipConfirmation
    case completion
}

// MARK: - Navigation Direction

private enum NavigationDirection {
    case forward, backward
}

// MARK: - LicenseOnboardingRootView

struct LicenseOnboardingRootView: View {
    let needsOnboarding: Bool
    let onDismiss: () -> Void

    @State private var currentScreen: OnboardingScreen = .splash
    @State private var contentOpacity: Double = 1
    @State private var navigationDirection: NavigationDirection = .forward
    @ObservedObject private var screenCaptureManager = ScreenCaptureManager.shared

    // Onboarding steps (excluding splash and license)
    private static let onboardingSteps: [OnboardingScreen] = [.permissions, .shortcuts, .completion]

    private var isOnboardingStep: Bool {
        currentScreen != .splash && currentScreen != .license
    }

    private var currentStepIndex: Int {
        Self.onboardingSteps.firstIndex(of: currentScreen) ?? 0
    }

    private var showSkipButton: Bool {
        currentScreen == .shortcuts
    }

    var body: some View {
        ZStack {
            Color.clear

            Group {
                switch currentScreen {
                case .splash:
                    SplashContentView(onContinue: handleSplashContinue)
                        .transition(.opacity)

                case .license:
                    LicenseActivationView(onContinue: {
                        navigateForward(to: .permissions)
                    })
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
                        onBack: { navigateBack(to: .permissions) },
                        onDecline: { navigateForward(to: .completion) },
                        onAccept: {
                            KeyboardShortcutManager.shared.enable()
                            navigateForward(to: .completion)
                        }
                    )
                    .transition(stepTransition)

                case .skipConfirmation:
                    SkipConfirmationView(
                        onGoBack: { navigateBack(to: .shortcuts) },
                        onConfirmSkip: { handleComplete() }
                    )
                    .transition(stepTransition)

                case .completion:
                    CompletionView(
                        onBack: { navigateBack(to: .shortcuts) },
                        onComplete: handleComplete
                    )
                    .transition(stepTransition)
                }
            }
            .opacity(contentOpacity)

            // Skip button — top-right, only on shortcuts step
            if showSkipButton {
                VStack {
                    HStack {
                        Spacer()
                        Button("Skip") {
                            navigateForward(to: .skipConfirmation)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(Color.white.opacity(0.1))
                        )
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .contentShape(Capsule())
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                    .padding(.top, 20)
                    .padding(.trailing, 32)
                    Spacer()
                }
                .opacity(contentOpacity)
                .transition(.opacity)
            }

            // Page dots — bottom center, only during onboarding steps
            if isOnboardingStep && currentScreen != .skipConfirmation {
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
        .padding(.top, 28)
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
        // Check if license screen is needed
        if needsLicenseScreen {
            navigateForward(to: .license)
        } else if needsOnboarding {
            navigateForward(to: .permissions)
        } else {
            withAnimation(.easeIn(duration: 0.3)) {
                contentOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onDismiss()
            }
        }
    }

    private var needsLicenseScreen: Bool {
        // Show license screen if Organization ID is not configured
        // or if no valid license/trial exists
        guard LicenseManager.shared.getOrganizationId() != nil else {
            return true
        }

        // Check if user has a valid trial or license
        switch LicenseManager.shared.state {
        case .trial, .licensed:
            return false
        default:
            return true
        }
    }

    private func navigateForward(to screen: OnboardingScreen) {
        navigationDirection = .forward
        withAnimation(.easeInOut(duration: 0.4)) {
            currentScreen = screen
        }
    }

    private func navigateBack(to screen: OnboardingScreen) {
        navigationDirection = .backward
        withAnimation(.easeInOut(duration: 0.4)) {
            currentScreen = screen
        }
    }

    private func handleComplete() {
        UserDefaults.standard.set(true, forKey: PreferencesKeys.onboardingCompleted)

        withAnimation(.easeIn(duration: 0.3)) {
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onDismiss()
        }
    }
}

#Preview {
    LicenseOnboardingRootView(needsOnboarding: true, onDismiss: {})
        .frame(width: 800, height: 600)
        .background(.black.opacity(0.5))
}
