//
//  SnapzyOnboardingView.swift
//  Snapzy
//
//  Ruru-inspired interactive walkthrough view for Snapzy, compatible with macOS 13.0+.
//

import SwiftUI

struct SnapzyOnboardingView: View {
  var onDismiss: () -> Void

  @StateObject private var state = SnapzyOnboardingState()
  @State private var isShowingCompletion = false
  @EnvironmentObject private var onboardingLocalization: OnboardingLocalizationController

  var body: some View {
    ZStack(alignment: .topLeading) {
      SnapzyGlassWindowBackdrop()

      if isShowingCompletion {
        VStack(spacing: 0) {
          header
            .frame(height: SnapzyOnboardingMetrics.headerHeight)
            .padding(.top, SnapzyOnboardingMetrics.gutter)
            .padding(.horizontal, SnapzyOnboardingMetrics.gutter)

          SnapzyOnboardingCompletionCard(onFinish: finish, onBack: retreat)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.bottom, SnapzyOnboardingMetrics.gutter)
            .padding(.horizontal, SnapzyOnboardingMetrics.gutter)
        }
        .transition(
          .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.97)),
            removal: .opacity.combined(with: .scale(scale: 0.97))
          )
        )
      } else if state.currentStep.usesWideLayout {
        // Full-width layout for permissions step
        VStack(spacing: 0) {
          header
            .frame(height: SnapzyOnboardingMetrics.headerHeight)
            .padding(.top, SnapzyOnboardingMetrics.gutter)
            .padding(.horizontal, SnapzyOnboardingMetrics.gutter)

          SnapzyOnboardingPermissionsView(state: state)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .padding(.horizontal, SnapzyOnboardingMetrics.gutter)

          footer
            .frame(height: SnapzyOnboardingMetrics.footerHeight)
            .padding(.bottom, SnapzyOnboardingMetrics.gutter)
            .padding(.horizontal, SnapzyOnboardingMetrics.gutter)
        }
        .transition(
          .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 16)),
            removal: .opacity.combined(with: .offset(x: -16))
          )
        )
      } else {
        // Two-column layout: Left instruction rail + Right full-bleed mock stage
        VStack(spacing: 0) {
          header
            .frame(height: SnapzyOnboardingMetrics.headerHeight)
            .padding(.top, SnapzyOnboardingMetrics.gutter)
            .padding(.horizontal, SnapzyOnboardingMetrics.gutter)

          HStack(alignment: .top, spacing: 0) {
            // Left Column
            VStack(alignment: .leading, spacing: 0) {
              SnapzyOnboardingInstructionPanel(state: state)
                .padding(.top, 20)

              Spacer(minLength: 16)

              SnapzyOnboardingEscapeHint(text: escapeHintText)
                .frame(height: SnapzyOnboardingMetrics.footerHeight, alignment: .leading)
                .padding(.bottom, SnapzyOnboardingMetrics.gutter)
            }
            .frame(width: SnapzyOnboardingMetrics.railWidth, alignment: .leading)
            .padding(.leading, SnapzyOnboardingMetrics.gutter)
            .padding(.trailing, SnapzyOnboardingMetrics.columnGap)

            // Right Column: Mockup Stage with Floating Action Bar
            ZStack(alignment: .bottomTrailing) {
              SnapzyOnboardingMockHost(state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 14)

              floatingActionBarWithHint
                .padding(.trailing, SnapzyOnboardingMetrics.gutter)
                .padding(.bottom, SnapzyOnboardingMetrics.gutter)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .transition(
          .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 16)),
            removal: .opacity.combined(with: .offset(x: -16))
          )
        )
      }
    }
    .frame(
      minWidth: SnapzyOnboardingMetrics.minSize.width,
      maxWidth: SnapzyOnboardingMetrics.maxSize.width,
      minHeight: SnapzyOnboardingMetrics.minSize.height,
      maxHeight: SnapzyOnboardingMetrics.maxSize.height
    )
    .environment(\.colorScheme, .dark)
    .background(keyboardShortcuts)
    .animation(SnapzyMotionPreferences.shared.spec(.morph).animation, value: state.currentStep)
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 0) {
      brand

      Spacer(minLength: SnapzySpace.xxl)

      HStack(spacing: SnapzySpace.md) {
        SnapzyOnboardingLanguagePicker()
        SnapzyOnboardingCloseButton(action: finish)
      }
    }
    .overlay(SnapzyOnboardingStepRail(state: state))
  }

  private var brand: some View {
    HStack(spacing: SnapzySpace.xl) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

      Text("Snapzy")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(SnapzyGlassInk.primary)
    }
  }

  // MARK: - Actions & Footer

  private var escapeHintText: String {
    state.canGoBack ? L10n.Onboarding.goBackHint : L10n.Onboarding.closeHint
  }

  private var actionBar: some View {
    let isLastStep = !state.canGoForward
    let skipTitle: String? = isLastStep ? nil : L10n.Onboarding.actionSkip
    let skipAction: (() -> Void)? = isLastStep ? nil : { skip() }
    let canAdvance = state.isCurrentStepComplete || isLastStep

    return SnapzyOnboardingActionBar(
      skipTitle: skipTitle,
      continueTitle: isLastStep ? L10n.Onboarding.actionFinish : L10n.Onboarding.actionContinue,
      continueKey: "\u{21A9}",
      isContinueEnabled: canAdvance,
      onSkip: skipAction,
      onContinue: advance
    )
  }

  private var floatingActionBarWithHint: some View {
    VStack(alignment: .trailing, spacing: 6) {
      if state.canGoForward && state.isCurrentStepComplete {
        SnapzyCurvedHintArrow(
          text: L10n.Onboarding.continueHint,
          orientation: .curveDownToTarget,
          arrowAlignment: .trailing,
          color: .white
        )
        .padding(.trailing, 8)
        .transition(
          .asymmetric(
            insertion: .scale(scale: 0.90, anchor: .bottomTrailing).combined(with: .opacity),
            removal: .scale(scale: 0.95, anchor: .bottomTrailing).combined(with: .opacity)
          )
        )
      }

      actionBar
    }
    .animation(SnapzyMotionPreferences.shared.spec(.settle).animation, value: state.isCurrentStepComplete)
  }

  private var footer: some View {
    HStack(spacing: SnapzySpace.xxl) {
      SnapzyOnboardingEscapeHint(text: escapeHintText)
      Spacer(minLength: SnapzySpace.xxl)
      actionBar
    }
  }

  // MARK: - Keyboard Shortcuts

  private var keyboardShortcuts: some View {
    ZStack {
      Button("", action: advance)
        .keyboardShortcut(.defaultAction)

      Button("", action: retreat)
        .keyboardShortcut(.cancelAction)
    }
    .opacity(0)
    .frame(width: 0, height: 0)
    .accessibilityHidden(true)
  }

  // MARK: - Navigation

  private func advance() {
    guard state.canGoForward else {
      withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
        isShowingCompletion = true
      }
      return
    }
    state.markCurrentStepVisited()
    state.nextStep()
  }

  private func skip() {
    guard state.canGoForward else {
      withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
        isShowingCompletion = true
      }
      return
    }
    state.nextStep()
  }

  private func retreat() {
    if isShowingCompletion {
      withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
        isShowingCompletion = false
      }
    } else if state.canGoBack {
      state.previousStep()
    } else {
      finish()
    }
  }

  private func finish() {
    UserDefaults.standard.set(true, forKey: PreferencesKeys.onboardingCompleted)
    UserDefaults.standard.set(true, forKey: PreferencesKeys.splashSkipped)
    UserDefaults.standard.set(true, forKey: PreferencesKeys.sponsorPromptSeen)
    UserDefaults.standard.removeObject(forKey: PreferencesKeys.onboardingActiveStep)

    let isUnderXCTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    let requiresRelaunch = !isUnderXCTest && (ScreenCaptureManager.shared.requiresRelaunchToActivate || onboardingLocalization.requiresRelaunchOnCompletion)
    onboardingLocalization.commitLanguageSelection()

    if requiresRelaunch {
      UserDefaults.standard.set(true, forKey: PreferencesKeys.splashSkipOnceAfterOnboardingRelaunch)
      Task {
        try? await Task.sleep(for: .milliseconds(150))
        try? await onboardingLocalization.relaunchApplication()
      }
    }

    onDismiss()
  }
}
