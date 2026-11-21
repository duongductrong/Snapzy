//
//  SnapzyOnboardingStepRail.swift
//  Snapzy
//
//  The progress spine across the onboarding header: four beads, joined by tracks that fill as the
//  flow advances.
//

import SwiftUI

struct SnapzyOnboardingStepRail: View {
  @ObservedObject var state: SnapzyOnboardingState

  private static let beadDiameter: CGFloat = 22
  private static let trackHeight: CGFloat = 1.5

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(SnapzyOnboardingStep.allCases.enumerated()), id: \.element) { index, step in
        if index > 0 {
          track(leadingInto: step)
        }
        node(for: step)
      }
    }
    .animation(SnapzyMotionPreferences.shared.spec(.settle).animation, value: state.currentStep)
    .accessibilityElement(children: .contain)
  }

  // MARK: - Node

  private func node(for step: SnapzyOnboardingStep) -> some View {
    let isCurrent = state.currentStep == step
    let isVisited = state.completedSteps.contains(step)
    let isReachable = isVisited || step.stepNumber <= state.currentStep.stepNumber

    return Button {
      guard isReachable else { return }
      state.transition(to: step)
    } label: {
      HStack(spacing: SnapzySpace.md) {
        bead(number: step.stepNumber, isCurrent: isCurrent, isVisited: isVisited)

        Text(step.shortTitle)
          .font(.system(size: SnapzyOnboardingType.caption, weight: isCurrent ? .semibold : .regular))
          .foregroundStyle(isCurrent ? SnapzyGlassInk
            .primary : (isVisited ? SnapzyGlassInk.body : SnapzyGlassInk.muted))
          .fixedSize()
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(SnapzyStepNodeButtonStyle())
    .disabled(!isReachable)
    .help(step.shortTitle)
    .accessibilityLabel("\(step.stepNumber). \(step.shortTitle)")
    .accessibilityAddTraits(isCurrent ? .isSelected : [])
  }

  /// Clickable step nodes press like controls: the label dips on press and settles back on a
  /// spring, so a click-back feels physically taken, not just applied.
  private struct SnapzyStepNodeButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .opacity(configuration.isPressed ? 0.7 : 1)
        .scaleEffect(configuration.isPressed ? 0.94 : 1)
        .background {
          Capsule(style: .continuous)
            .fill(SnapzyGlassInk.fillQuiet)
            .opacity(isHovered && !configuration.isPressed ? 1 : 0)
        }
        .animation(SnapzyMotionPreferences.shared.spec(.hover).animation, value: isHovered)
        .animation(SnapzyMotionPreferences.shared.spec(.anticipation).animation, value: configuration.isPressed)
        .onHover { isHovered = $0 }
    }
  }

  private func bead(number: Int, isCurrent: Bool, isVisited: Bool) -> some View {
    ZStack {
      Circle()
        .fill(
          isCurrent
            ? Color.white
            : (isVisited ? Color.white.opacity(0.16) : Color.white.opacity(0.04))
        )

      Circle()
        .strokeBorder(
          isCurrent
            ? Color.clear
            : SnapzyGlassInk.faint.opacity(isVisited ? 0.85 : 0.45),
          lineWidth: 0.75
        )

      if isVisited, !isCurrent {
        Image(systemName: "checkmark")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(SnapzyGlassInk.primary)
          .transition(.scale(scale: 0.7).combined(with: .opacity))
      } else {
        Text("\(number)")
          .font(.system(size: 10.5, weight: isCurrent ? .bold : .medium))
          .foregroundStyle(
            isCurrent
              ? Color(red: 0.04, green: 0.08, blue: 0.22)
              : SnapzyGlassInk.muted
          )
      }
    }
    .scaleEffect(isCurrent ? 1.04 : 1)
    .frame(width: SnapzyOnboardingStepRail.beadDiameter, height: SnapzyOnboardingStepRail.beadDiameter)
  }

  // MARK: - Track

  /// The connector fills from the side it was crossed, so progress reads as travel rather than as
  /// a colour change.
  private func track(leadingInto step: SnapzyOnboardingStep) -> some View {
    let isTraversed = step.stepNumber <= state.currentStep.stepNumber

    return ZStack(alignment: .leading) {
      Capsule(style: .continuous)
        .fill(SnapzyGlassInk.faint.opacity(0.32))

      Capsule(style: .continuous)
        .fill(SnapzyGlassInk.primary.opacity(0.82))
        .scaleEffect(x: isTraversed ? 1 : 0, anchor: .leading)
    }
    .frame(height: SnapzyOnboardingStepRail.trackHeight)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, SnapzySpace.md)
    .accessibilityHidden(true)
  }
}
