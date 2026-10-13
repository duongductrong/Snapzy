//
//  SnapzyOnboardingActionBar.swift
//  Snapzy
//
//  Rounded-full capsule Liquid Glass Action Bar with tactile spring button feedback.
//

import SwiftUI

private enum SnapzyOnboardingGlassAppearance {
  // Keep the group and its nested controls in one dark material family. The child surface is
  // only materialized on hover, so the resting two-button bar reads like the single Finish bar.
  static let barTint = Color.black.opacity(0.52)
  static let segmentActiveTint = Color.black.opacity(0.54)
}

struct SnapzyOnboardingActionBar: View {
  var skipTitle: String? = nil
  var continueTitle: String
  var continueKey: String? = nil
  var isContinueEnabled: Bool = true
  var isBusy: Bool = false
  var minWidth: CGFloat? = nil
  var onSkip: (() -> Void)? = nil
  var onContinue: () -> Void

  private let barHeight: CGFloat = 40

  var body: some View {
    HStack(spacing: 0) {
      if let skipTitle, let onSkip {
        SnapzyOnboardingBarSegment(
          title: skipTitle,
          trailingKey: nil,
          isEnabled: true,
          isBusy: false,
          action: onSkip
        )

        // Etched vertical hairline divider
        Rectangle()
          .fill(
            LinearGradient(
              colors: [
                Color.white.opacity(0.0),
                Color.white.opacity(0.18),
                Color.white.opacity(0.0),
              ],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .frame(width: SnapzySurfaceGlass.specularLineWidth, height: 18)
          .padding(.horizontal, 2)
      }

      SnapzyOnboardingBarSegment(
        title: continueTitle,
        trailingKey: continueKey,
        isEnabled: isContinueEnabled,
        isBusy: isBusy,
        action: onContinue
      )
    }
    .padding(3.5)
    .frame(height: barHeight)
    .frame(minWidth: minWidth)
    // Group only the sibling button surfaces. Keeping the outer shell outside the native glass
    // container makes a two-button bar resolve like the single-button Finish bar.
    .liquidGlassGroup(spacing: 0)
    .liquidGlassSurface(
      shape: Capsule(style: .continuous),
      substrate: SnapzySurfaceGlass.baseDarkness,
      tint: 0.04,
      // Keep onboarding chrome grounded over the colourful mock stage. The native path uses
      // this as the tint channel, while the macOS 13–15 path keeps the same four-layer optical
      // composite used by Ruru instead of collapsing into a solid fill.
      nativeGlassTint: SnapzyOnboardingGlassAppearance.barTint
    )
    .clipShape(Capsule(style: .continuous))
    .shadow(color: Color.black.opacity(0.20), radius: 12, y: 5)
    .shadow(color: Color.black.opacity(0.10), radius: 2, y: 1)
    .animation(SnapzyMotionPreferences.shared.spec(.settle).animation, value: isContinueEnabled)
  }
}

private struct SnapzyOnboardingBarSegment: View {
  var title: String
  var trailingKey: String?
  var isEnabled: Bool = true
  var isBusy: Bool = false
  var action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: {
      guard isEnabled, !isBusy else { return }
      action()
    }) {
      HStack(spacing: SnapzySpace.sm) {
        if isBusy {
          ProgressView()
            .controlSize(.small)
            .tint(SnapzyGlassInk.primary)
        }

        Text(title)
          // Keep the label metrics stable while the pointer moves. Hover is expressed by the
          // glass plane, hairline and ink tint; changing weight here makes the label re-center.
          .font(.system(size: SnapzyOnboardingType.body + 1, weight: .medium))
          .foregroundStyle(
            !isEnabled
              ? Color.white.opacity(0.30)
              : (isHovered ? SnapzyGlassInk.primary : SnapzyGlassInk.body)
          )

        if let trailingKey, !isBusy {
          SnapzyKeycapChip(label: trailingKey, emphasis: isHovered && isEnabled)
            .opacity(isEnabled ? 1.0 : 0.35)
        }
      }
      .padding(.horizontal, SnapzySpace.xl + 1)
      .frame(maxHeight: .infinity)
      .liquidGlassSurface(
        shape: Capsule(style: .continuous),
        // Match Ruru's onboarding action bar: the group owns the resting surface, while a
        // button gets its own glass plane only while hovered. `isVisible` keeps the native
        // identity stable instead of inserting/removing an effect view on every pointer move.
        isVisible: isHovered && isEnabled && !isBusy,
        substrate: SnapzySurfaceGlass.controlSubstrateHover,
        tint: 0.10,
        // The hotter diagonal hairline is the hover affordance on both paths. Native glass gets
        // it explicitly here because its default refractive edge is intentionally preserved for
        // the rest of the app.
        highlight: .custom(top: 0.24, bottom: 0.08),
        isInteractive: isEnabled && !isBusy,
        nativeGlassTint: SnapzyOnboardingGlassAppearance.segmentActiveTint,
        nativeHighlight: .custom(top: 0.24, bottom: 0.08)
      )
      .contentShape(Capsule(style: .continuous))
    }
    .buttonStyle(SnapzyInteractiveButtonStyle(isEnabled: isEnabled && !isBusy))
    .disabled(!isEnabled || isBusy)
    .onHover { hovering in
      guard isEnabled, !isBusy else {
        isHovered = false
        return
      }
      withAnimation(SnapzyMotionPreferences.shared.spec(.hover).animation) {
        isHovered = hovering
      }
    }
    .animation(SnapzyMotionPreferences.shared.spec(.settle).animation, value: isEnabled)
  }
}

private struct SnapzyInteractiveButtonStyle: ButtonStyle {
  var isEnabled: Bool = true

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect((configuration.isPressed && isEnabled) ? 0.96 : 1.0)
      .animation(.spring(response: 0.18, dampingFraction: 0.8), value: configuration.isPressed)
  }
}
