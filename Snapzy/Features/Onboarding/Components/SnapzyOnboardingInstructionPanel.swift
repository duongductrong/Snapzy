//
//  SnapzyOnboardingInstructionPanel.swift
//  Snapzy
//
//  Left-column instruction panel: narrative, challenge checklist, simulation prompt, tip.
//

import SwiftUI

struct SnapzyOnboardingInstructionPanel: View {
  @ObservedObject var state: SnapzyOnboardingState
  /// Allows pre-warming the panel behind the Welcome screen and firing its staggered entrance
  /// at the exact moment the Welcome aurora glides aside to reveal the left column.
  var isRevealed: Bool = true

  /// Drives the entrance. The root view re-identifies the panel per step, so this returns to
  /// false and the page arrives in a short stagger every time the step changes.
  @State private var hasAppeared = false

  /// Checklist rows follow the headline, so their beats start after it. The prompt and the tip
  /// continue the same count, which is why they are indexed off the row count rather than hard-coded.
  private var checklistOffset: Int {
    1
  }

  private var trailingIndex: Int {
    checklistOffset + state.currentStep.challenges.count
  }

  private var activeChallenge: SnapzyOnboardingChallenge? {
    state.currentStep.challenges.first { !state.completedChallenges.contains($0) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      headline
        .entrance(0, appeared: hasAppeared)

      challengeChecklist
        .padding(.top, SnapzySpace.hero)

      if !state.currentStep.examplePrompt.isEmpty {
        promptCard
          .padding(.top, SnapzySpace.huge)
          .entrance(trailingIndex, appeared: hasAppeared)
      }

      if !state.currentStep.tip.isEmpty {
        tip
          .padding(.top, SnapzySpace.xxl)
          .entrance(trailingIndex + 1, appeared: hasAppeared)
      }

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onAppear {
      if isRevealed {
        hasAppeared = true
      }
    }
    .onChange(of: isRevealed) { revealed in
      if revealed {
        hasAppeared = true
      }
    }
  }

  // MARK: - Headline

  private var headline: some View {
    VStack(alignment: .leading, spacing: SnapzySpace.xl) {
      SnapzyOnboardingOverline(
        L10n.Onboarding.stepIndicator(state.currentStep.stepNumber, SnapzyOnboardingStep.allCases.count)
      )

      Text(state.currentStep.title)
        .font(.system(size: SnapzyOnboardingType.display, weight: .bold))
        .tracking(SnapzyOnboardingType.displayTracking)
        .foregroundStyle(SnapzyGlassInk.primary)
        .fixedSize(horizontal: false, vertical: true)

      Text(state.currentStep.subtitle)
        .font(.system(size: SnapzyOnboardingType.lede))
        .foregroundStyle(SnapzyGlassInk.body)
        .lineSpacing(7)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Checklist

  private var challengeChecklist: some View {
    VStack(alignment: .leading, spacing: SnapzySpace.xl) {
      ForEach(Array(state.currentStep.challenges.enumerated()), id: \.element) { index, challenge in
        ChallengeRow(
          challenge: challenge,
          isDone: state.completedChallenges.contains(challenge),
          isActive: activeChallenge == challenge
        )
        .entrance(checklistOffset + index, appeared: hasAppeared)
      }
    }
    .animation(SnapzyMotionPreferences.shared.spec(.settle).animation, value: state.completedChallenges)
  }

  // MARK: - Prompt Card

  private var promptText: String {
    if state.currentStep == .meetSnapzy {
      switch state.step1Stage {
      case .readyToCapture:
        return L10n.Onboarding.stepCapturePromptReady
      case .selectingArea:
        return L10n.Onboarding.stepCapturePromptSelecting
      case .quickAccessFloating:
        return L10n.Onboarding.stepCapturePromptFloating
      case .annotateWindowOpen:
        return L10n.Onboarding.stepCapturePromptOpen
      }
    } else if state.currentStep == .quickAccess {
      switch state.step2Stage {
      case .readyToRecord:
        return L10n.Onboarding.stepRecordingPromptReady
      case .prerecordArea:
        return L10n.Onboarding.stepRecordingPromptFramed
      case .recordingActive:
        return L10n.Onboarding.stepRecordingPromptActive(state.recordingSeconds)
      case .videoQuickAccess:
        return L10n.Onboarding.stepRecordingPromptFloating
      case .videoEditorOpen:
        return L10n.Onboarding.stepRecordingPromptOpen
      }
    } else if state.currentStep == .shortcuts {
      if state.hasConflict {
        return L10n.Onboarding.stepShortcutsPromptConflicts
      } else {
        return L10n.Onboarding.stepShortcutsPromptResolved
      }
    }
    return state.currentStep.examplePrompt
  }

  /// The card that tells the user what the demo on the right is waiting for. It is a button
  /// because it *does* the thing: on every step except permissions, tapping it advances the
  /// simulation to the next stage, which is a faster way to discover the demo than reading about it.
  private var promptCard: some View {
    Button {
      triggerNextStage()
    } label: {
      VStack(alignment: .leading, spacing: SnapzySpace.lg) {
        SnapzyOnboardingOverline(L10n.Onboarding.demoOverline, tint: SnapzyGlassInk.muted)

        Text(promptText)
          .font(.system(size: SnapzyOnboardingType.lede - 0.5).italic())
          .foregroundStyle(SnapzyGlassInk.primary.opacity(0.94))
          .multilineTextAlignment(.leading)
          .lineSpacing(4)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, SnapzySpace.xxl + SnapzySpace.xs)
      .padding(.vertical, SnapzySpace.xxl)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(cardShape.fill(SnapzyGlassInk.fillQuiet))
      .overlay(cardShape.strokeBorder(SnapzyGlassInk.hairline, lineWidth: SnapzySurfaceGlass.specularLineWidth))
      .contentShape(cardShape)
    }
    .buttonStyle(SnapzyPromptCardButtonStyle())
    .help(L10n.Onboarding.demoTooltip)
  }

  private var cardShape: RoundedRectangle {
    Radius.rect(SnapzyRadius.card)
  }

  private func triggerNextStage() {
    switch state.currentStep {
    case .meetSnapzy:
      switch state.step1Stage {
      case .readyToCapture:
        state.simulateAreaCapture()
      case .selectingArea:
        state.completeCaptureToQuickAccess()
      case .quickAccessFloating:
        state.openAnnotateFromQuickAccess()
      case .annotateWindowOpen:
        state.resetStep1Flow()
      }
    case .quickAccess:
      switch state.step2Stage {
      case .readyToRecord:
        state.simulateStartPrerecord()
      case .prerecordArea:
        state.simulateStartRecording()
      case .recordingActive:
        state.simulateFinishRecording()
      case .videoQuickAccess:
        state.openVideoEditorFromQuickAccess()
      case .videoEditorOpen:
        state.resetStep2Flow()
      }
    case .shortcuts:
      state.resolveShortcutConflicts()
    case .permissions:
      break
    }
  }

  // MARK: - Tip

  private var tip: some View {
    HStack(alignment: .top, spacing: SnapzySpace.lg) {
      Image(systemName: "info.circle")
        .font(.system(size: 12))
        .foregroundStyle(SnapzyGlassInk.faint)
        .accessibilityHidden(true)

      Text(state.currentStep.tip)
        .font(.system(size: SnapzyOnboardingType.caption))
        .foregroundStyle(SnapzyGlassInk.muted)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Challenge Row

private struct ChallengeRow: View {
  var challenge: SnapzyOnboardingChallenge
  var isDone: Bool
  var isActive: Bool

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: SnapzySpace.xl) {
      marker
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }

      Text(challenge.label)
        .font(.system(size: SnapzyOnboardingType.challenge, weight: isActive ? .semibold : .regular))
        .foregroundStyle(labelInk)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: SnapzySpace.md)

      if !challenge.keys.isEmpty {
        SnapzyKeycapRow(keys: challenge.keys, emphasis: isActive)
          .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }
      }
    }
    .animation(SnapzyMotionPreferences.shared.spec(.pop).animation, value: isDone)
  }

  private var labelInk: Color {
    if isActive {
      return SnapzyGlassInk.primary
    }
    if isDone {
      return SnapzyGlassInk.body
    }
    return SnapzyGlassInk.muted
  }

  /// A ring that becomes a filled disc. The check enters at 0.7 rather than 0 — nothing in the
  /// real world appears out of nothing, and a mark growing from a point reads as a pop-up.
  private var marker: some View {
    ZStack {
      Circle()
        .fill(isDone ? Color(red: 0.14, green: 0.34, blue: 1.0) : Color.clear)

      Circle()
        .strokeBorder(
          isDone ? Color.clear : SnapzyGlassInk.primary.opacity(isActive ? 0.78 : 0.24),
          lineWidth: isActive ? 1.4 : 1
        )

      if isDone {
        Image(systemName: "checkmark")
          .font(.system(size: 9.5, weight: .bold))
          .foregroundStyle(.white)
          .transition(.scale(scale: 0.7).combined(with: .opacity))
      }
    }
    .frame(width: 18, height: 18)
    .accessibilityHidden(true)
  }
}

// MARK: - Prompt Card Style

private struct SnapzyPromptCardButtonStyle: ButtonStyle {
  @State private var isHovered = false

  private var cardShape: RoundedRectangle {
    Radius.rect(SnapzyRadius.card)
  }

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .overlay(
        cardShape
          .fill(SnapzyGlassInk.fillHover.opacity(pressOpacity(configuration.isPressed)))
          .overlay(
            cardShape.strokeBorder(
              SnapzyGlassInk.hairlineStrong,
              lineWidth: SnapzySurfaceGlass.specularLineWidth
            )
            .opacity(pressOpacity(configuration.isPressed))
          )
      )
      .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
      .onHover { hovering in
        withAnimation(SnapzyMotionPreferences.shared.spec(.hover).animation) { isHovered = hovering }
      }
      .animation(SnapzyMotionPreferences.shared.spec(.anticipation).animation, value: configuration.isPressed)
  }

  private func pressOpacity(_ isPressed: Bool) -> Double {
    if isPressed {
      return 0.6
    }
    return isHovered ? 1 : 0
  }
}
