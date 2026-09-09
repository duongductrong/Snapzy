//
//  SnapzyOnboardingInstructionPanel.swift
//  Snapzy
//
//  Left-column instruction panel carrying narrative, challenge checklist, and simulation prompt card.
//

import SwiftUI

struct SnapzyOnboardingInstructionPanel: View {
  @ObservedObject var state: SnapzyOnboardingState

  private var activeChallenge: SnapzyOnboardingChallenge? {
    state.currentStep.challenges.first { !state.completedChallenges.contains($0) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      headline

      challengeChecklist

      if !state.currentStep.examplePrompt.isEmpty {
        promptCard
      }

      if !state.currentStep.tip.isEmpty {
        tip
      }

      Spacer(minLength: 0)
    }
    .frame(width: SnapzyOnboardingMetrics.railWidth, alignment: .leading)
  }

  // MARK: - Headline

  private var headline: some View {
    VStack(alignment: .leading, spacing: SnapzySpace.xxl) {
      SnapzyOnboardingOverline("Step \(state.currentStep.stepNumber) of \(SnapzyOnboardingStep.allCases.count)")

      Text(state.currentStep.title)
        .font(.system(size: SnapzyOnboardingType.display, weight: .bold))
        .tracking(-0.6)
        .foregroundStyle(SnapzyGlassInk.primary)
        .fixedSize(horizontal: false, vertical: true)

      Text(state.currentStep.subtitle)
        .font(.system(size: SnapzyOnboardingType.lede))
        .foregroundStyle(SnapzyGlassInk.body)
        .lineSpacing(6)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Checklist

  private var challengeChecklist: some View {
    VStack(alignment: .leading, spacing: SnapzySpace.xxl - SnapzySpace.xxs) {
      ForEach(state.currentStep.challenges) { challenge in
        ChallengeRow(
          challenge: challenge,
          isDone: state.completedChallenges.contains(challenge),
          isActive: activeChallenge == challenge
        )
      }
    }
    .animation(SnapzyMotionPreferences.shared.spec(.settle).animation, value: state.completedChallenges)
  }

  // MARK: - Prompt Card

  private var promptText: String {
    if state.currentStep == .meetSnapzy {
      switch state.step1Stage {
      case .readyToCapture:
        return "Click to freeze the screen and simulate selecting an area with ⇧⌘4."
      case .selectingArea:
        return "Area selected! Click to complete capture and send to Quick Access."
      case .quickAccessFloating:
        return "Capture is in Quick Access! Click card or ✎ to open Annotate window."
      case .annotateWindowOpen:
        return "Annotate window open! Click to replay the complete flow from the beginning."
      }
    }
    return state.currentStep.examplePrompt
  }

  private var promptCard: some View {
    Button {
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
        state.simulateQuickAccessAction("⌘C Copied")
      case .shortcuts:
        state.completeChallenge(.checkShortcuts)
      case .permissions:
        break
      }
    } label: {
      VStack(alignment: .leading, spacing: SnapzySpace.lg) {
        SnapzyOnboardingOverline("Interactive Demo", tint: SnapzyGlassInk.muted)

        Text(promptText)
          .font(.system(size: SnapzyOnboardingType.lede - 0.5).italic())
          .foregroundStyle(SnapzyGlassInk.primary.opacity(0.94))
          .multilineTextAlignment(.leading)
          .lineSpacing(4)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, SnapzySpace.xxl + SnapzySpace.xs)
      .padding(.vertical, SnapzySpace.xxl)
      .background(
        RoundedRectangle(cornerRadius: SnapzyRadius.control, style: .continuous)
          .fill(Color.white.opacity(0.07))
          .overlay(
            RoundedRectangle(cornerRadius: SnapzyRadius.control, style: .continuous)
              .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
          )
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(SnapzyPromptCardButtonStyle())
    .help("Run simulation on mock stage")
  }

  // MARK: - Tip

  private var tip: some View {
    HStack(alignment: .top, spacing: SnapzySpace.lg) {
      Image(systemName: "info.circle")
        .font(.system(size: 12))
        .foregroundStyle(SnapzyGlassInk.faint)

      Text(state.currentStep.tip)
        .font(.system(size: SnapzyOnboardingType.caption))
        .foregroundStyle(SnapzyGlassInk.muted)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

// MARK: - Challenge Row

private struct ChallengeRow: View {
  var challenge: SnapzyOnboardingChallenge
  var isDone: Bool
  var isActive: Bool

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: SnapzySpace.xxl) {
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
  }

  private var labelInk: Color {
    if isActive { return SnapzyGlassInk.primary }
    if isDone { return SnapzyGlassInk.body }
    return SnapzyGlassInk.muted
  }

  @ViewBuilder
  private var marker: some View {
    ZStack {
      if isDone {
        Circle().fill(Color.accentColor)
        Image(systemName: "checkmark")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(.white)
      } else {
        Circle()
          .strokeBorder(
            Color.white.opacity(isActive ? 0.75 : 0.24),
            lineWidth: isActive ? 1.5 : 1
          )
      }
    }
    .frame(width: 20, height: 20)
  }
}

private struct SnapzyPromptCardButtonStyle: ButtonStyle {
  @State private var isHovered = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .overlay(
        RoundedRectangle(cornerRadius: SnapzyRadius.control, style: .continuous)
          .fill(Color.white.opacity(configuration.isPressed ? 0.06 : (isHovered ? 0.04 : 0)))
      )
      .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
      .onHover { hovering in
        withAnimation(SnapzyMotionPreferences.shared.spec(.hover).animation) { isHovered = hovering }
      }
      .animation(.spring(response: 0.18, dampingFraction: 0.8), value: configuration.isPressed)
  }
}
