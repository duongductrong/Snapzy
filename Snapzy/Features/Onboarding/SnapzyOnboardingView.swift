//
//  SnapzyOnboardingView.swift
//  Snapzy
//
//  Root onboarding view: header with the progress spine, a two-column step layout, the wide
//  permissions layout, and the completion screen, over a shared footer.
//

import AppKit
import SwiftUI

struct SnapzyOnboardingView: View {
  /// Called when onboarding finishes. When `launchIconWindowFrame` is non-nil (user completed via
  /// "Start Using Snapzy"), the window controller performs the celebratory desktop ascent straight
  /// into the live macOS menu bar icon.
  var onDismiss: (_ launchIconWindowFrame: CGRect?) -> Void

  @StateObject private var state = SnapzyOnboardingState()
  @State private var isShowingCompletion = false
  @State private var isLaunchingFinale = false
  @State private var completionLaunchTrigger = 0
  /// The welcome bloom plays once for fresh starts; resuming a saved step skips straight into it.
  @State private var isShowingWelcome: Bool
  /// Mounted as soon as the user initiates entry from Welcome so the Liquid Glass workspace
  /// rises synchronously behind the parting aurora aperture.
  @State private var isFlowMounted: Bool
  @State private var isFlowSettled: Bool
  /// Stays `false` while the Welcome screen is flying into the top-left app icon, then flips to
  /// `true` on the exact landing frame so the real brand icon locks in seamlessly with zero jump.
  @State private var isBrandIconDocked: Bool
  @State private var brandIconFrame: CGRect = CGRect(
    x: SnapzyOnboardingMetrics.gutter,
    y: (SnapzyOnboardingMetrics.gutter - 10) + (SnapzyOnboardingMetrics.headerHeight - 26) * 0.5,
    width: 26,
    height: 26
  )
  @State private var welcomeStartTrigger = 0
  @Environment(\.accessibilityReduceMotion) private var envReduceMotion
  @EnvironmentObject private var onboardingLocalization: OnboardingLocalizationController

  init(onDismiss: @escaping (_ launchIconWindowFrame: CGRect?) -> Void) {
    self.onDismiss = onDismiss
    let freshStart = UserDefaults.standard.string(forKey: PreferencesKeys.onboardingActiveStep) == nil
    _isShowingWelcome = State(initialValue: freshStart)
    _isFlowMounted = State(initialValue: !freshStart)
    _isFlowSettled = State(initialValue: !freshStart)
    _isBrandIconDocked = State(initialValue: !freshStart)
  }

  private var reduceMotion: Bool {
    SnapzyMotionPreferences.shared.reduceMotion || envReduceMotion
  }

  var body: some View {
    ZStack {
      SnapzyGlassWindowBackdrop()

      if isFlowMounted {
        VStack(spacing: 0) {
          header
            .opacity(isLaunchingFinale ? 0 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: isLaunchingFinale)

          content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(SnapzyMotionPreferences.shared.spec(.morph).animation, value: state.currentStep)
            .animation(SnapzyMotionPreferences.shared.spec(.settle).animation, value: isShowingCompletion)

          // Liquid Glass Golden Rule: never animate `.opacity` on a view containing `.glassEffect`
          // (`SnapzyOnboardingActionBar`). Keep it cleanly tucked beneath the window's bottom clip
          // during prewarm and slide smoothly into place as the aurora contracts to the logo.
          footer
            .offset(y: reduceMotion ? 0 : (isFlowSettled ? 0 : 64))
            .animation(
              reduceMotion ? nil : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.84).delay(0.10),
              value: isFlowSettled
            )
        }
        .padding(.horizontal, SnapzyOnboardingMetrics.gutter)
        .padding(.top, SnapzyOnboardingMetrics.gutter - 10)
        .padding(.bottom, SnapzyOnboardingMetrics.gutter - 12)
      }

      if isShowingWelcome {
        SnapzyOnboardingWelcome(
          externalStartTrigger: welcomeStartTrigger,
          targetLogoFrame: brandIconFrame,
          onReadyForPrewarm: prewarmFlow,
          onBeginTransition: beginFlowReveal,
          onDockLogo: dockBrandLogo,
          onCompleteTransition: completeFlowReveal,
          onClose: { finish(launchIconWindowFrame: nil) }
        )
      }
    }
    .coordinateSpace(name: OnboardingRootCoordinateSpace.name)
    .onPreferenceChange(OnboardingBrandIconFrameKey.self) { frame in
      if frame.width > 0 && frame.height > 0 {
        brandIconFrame = frame
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
    .onAppear {
      SnapzyOnboardingWelcomeAudio.shared.prewarmInteractionEffects()
    }
  }

  // MARK: - Content

  @ViewBuilder
  private var content: some View {
    if isShowingCompletion {
      SnapzyOnboardingCompletionCard(
        externalLaunchTrigger: completionLaunchTrigger,
        onBeginLaunch: { isLaunchingFinale = true },
        onFinish: { iconFrame in
          finish(launchIconWindowFrame: iconFrame)
        },
        onBack: retreat
      )
      .transition(.opacity.combined(with: .scale(scale: 0.98)))
    } else if state.currentStep.usesWideLayout {
      SnapzyOnboardingPermissionsView(state: state)
        .transition(stepTransition)
    } else {
      stepColumns
        .transition(stepTransition)
    }
  }

  /// Steps tell which way they moved: the new page arrives from the side the target step lives
  /// on, and a longer jump travels further. An opacity-only fade under Reduce Motion keeps the
  /// meaning without the travel.
  private var stepTransition: AnyTransition {
    if SnapzyMotionPreferences.shared.reduceMotion {
      return .opacity
    }
    let travel = min(18 + CGFloat(state.navigationDistance) * 14, 58)
    let arrival: CGFloat = state.navigationDirection == .forward ? travel : -travel
    return .asymmetric(
      insertion: .opacity.combined(with: .offset(x: arrival)).combined(with: .scale(scale: 0.985)),
      removal: .opacity.combined(with: .offset(x: -arrival))
    )
  }

  private var stepColumns: some View {
    HStack(alignment: .top, spacing: SnapzyOnboardingMetrics.columnGap) {
      SnapzyOnboardingInstructionPanel(state: state, isRevealed: isFlowSettled)
        .frame(width: SnapzyOnboardingMetrics.railWidth, alignment: .topLeading)
        .offset(x: reduceMotion ? 0 : (isFlowSettled ? 0 : -22))
        .animation(
          reduceMotion ? nil : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.78),
          value: isFlowSettled
        )
        // Re-identified per step: the page is a document that gets replaced, and the fresh
        // identity is what lets its own staged entrance replay instead of firing once ever. The
        // replacement travels with the flow's direction, not always the same way.
        .id(state.currentStep)
        .transition(stepTransition)

      SnapzyOnboardingMockHost(state: state)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isFlowSettled ? 1 : 0)
        .scaleEffect(reduceMotion ? 1.0 : (isFlowSettled ? 1.0 : 0.965))
        .offset(y: reduceMotion ? 0 : (isFlowSettled ? 0 : 14))
        .animation(
          reduceMotion ? .easeOut(duration: 0.20) : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.86).delay(0.06),
          value: isFlowSettled
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Header

  private var header: some View {
    ZStack {
      HStack {
        brand
        Spacer(minLength: 0)
        HStack(spacing: SnapzySpace.md) {
          SnapzyOnboardingLanguagePicker()
          SnapzyOnboardingCloseButton(action: { finish(launchIconWindowFrame: nil) })
        }
        .opacity(isFlowSettled ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (isFlowSettled ? 0 : -8))
        .animation(
          reduceMotion ? .easeOut(duration: 0.20) : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.76).delay(0.08),
          value: isFlowSettled
        )
      }

      if !isShowingCompletion {
        SnapzyOnboardingStepRail(state: state)
          .frame(maxWidth: 460)
          .opacity(isFlowSettled ? 1 : 0)
          .offset(y: reduceMotion ? 0 : (isFlowSettled ? 0 : -8))
          .animation(
            reduceMotion ? .easeOut(duration: 0.20) : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.78).delay(0.06),
            value: isFlowSettled
          )
          .transition(.opacity)
      }
    }
    .frame(height: SnapzyOnboardingMetrics.headerHeight)
    .padding(.bottom, SnapzySpace.lg)
  }

  private var brand: some View {
    HStack(spacing: SnapzySpace.lg) {
      Image(nsImage: SnapzyOnboardingIconCache.appIcon)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 26, height: 26)
        // radius-lint:allow — clips the app icon bitmap; matches the icon's own corner
        .clipShape(Radius.rect(Radius.controlS))
        // Stays fixed at exact resting coordinates (zero offset) so the Welcome morph lands on it
        // pixel-for-pixel, then reveals synchronously on dock.
        .opacity(isBrandIconDocked ? 1 : 0)
        .background(
          GeometryReader { geo in
            Color.clear.preference(
              key: OnboardingBrandIconFrameKey.self,
              value: geo.frame(in: .named(OnboardingRootCoordinateSpace.name))
            )
          }
        )

      Text("Snapzy")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(SnapzyGlassInk.primary)
        .opacity(isFlowSettled ? 1 : 0)
        .offset(x: reduceMotion ? 0 : (isFlowSettled ? 0 : -8))
        .animation(
          reduceMotion ? .easeOut(duration: 0.20) : .timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.62).delay(0.46),
          value: isFlowSettled
        )
    }
    .fixedSize()
  }

  // MARK: - Footer

  private var escapeHintText: String {
    state.canGoBack ? L10n.Onboarding.goBackHint : L10n.Onboarding.closeHint
  }

  private var footer: some View {
    HStack(spacing: SnapzySpace.xxl) {
      if isShowingCompletion {
        Spacer()
      } else {
        SnapzyOnboardingEscapeHint(text: escapeHintText)
        Spacer()
        actionBar
      }
    }
    .frame(height: SnapzyOnboardingMetrics.footerHeight)
    .padding(.top, SnapzySpace.lg)
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
      isHinted: state.isCurrentStepComplete || isLastStep,
      onSkip: skipAction,
      onContinue: advance
    )
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

  /// The welcome sheet owns the first beat: both navigation keys trigger the same liquid aperture
  /// transition as clicking the arrow pill so keyboard & pointer starts feel identical.
  private func startFlow() {
    welcomeStartTrigger += 1
  }

  /// Silently mounts Step 1 behind the opaque Welcome aurora once the CTA is ready so layout,
  /// Liquid Glass sampling, and Metal pipelines are warm before the user clicks — zero click stall.
  private func prewarmFlow() {
    guard !isFlowMounted else { return }
    isFlowMounted = true
  }

  private func beginFlowReveal() {
    if !isFlowMounted {
      isFlowMounted = true
    }
    isFlowSettled = true
  }

  private func dockBrandLogo() {
    isBrandIconDocked = true
  }

  private func completeFlowReveal() {
    isBrandIconDocked = true
    isShowingWelcome = false
  }

  private func advance() {
    if isShowingWelcome {
      startFlow()
      return
    }
    if isShowingCompletion {
      completionLaunchTrigger += 1
      return
    }
    guard state.canGoForward else {
      SnapzyOnboardingWelcomeAudio.shared.playStepComplete()
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
      SnapzyOnboardingWelcomeAudio.shared.playStepComplete()
      withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
        isShowingCompletion = true
      }
      return
    }
    state.nextStep()
  }

  private func retreat() {
    if isShowingWelcome {
      startFlow()
      return
    }
    if isShowingCompletion {
      guard !isLaunchingFinale else { return }
      SnapzyOnboardingWelcomeAudio.shared.playStepBackward()
      withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
        isShowingCompletion = false
      }
    } else if state.canGoBack {
      state.previousStep()
    } else {
      SnapzyOnboardingWelcomeAudio.shared.playButtonTap()
      finish(launchIconWindowFrame: nil)
    }
  }

  private func finish(launchIconWindowFrame: CGRect?) {
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

    let finaleFrame = (isUnderXCTest || requiresRelaunch) ? nil : launchIconWindowFrame
    onDismiss(finaleFrame)
  }
}

private enum OnboardingRootCoordinateSpace {
  static let name = "SnapzyOnboardingRootSpace"
}

private struct OnboardingBrandIconFrameKey: PreferenceKey {
  static var defaultValue: CGRect = .zero

  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    let candidate = nextValue()
    if candidate.width > 0 && candidate.height > 0 {
      value = candidate
    }
  }
}
