//
//  LiquidGlassActionBar.swift
//  Snapzy
//
//  Grouped capsule Liquid Glass action bar with etched vertical hairlines and tactile segments.
//

import SwiftUI

struct LiquidGlassActionBar: View {
  var cancelTitle: String? = nil
  var confirmTitle: String
  var confirmKey: String? = nil
  var isConfirmEnabled: Bool = true
  var isBusy: Bool = false
  var minWidth: CGFloat? = nil
  var onCancel: (() -> Void)? = nil
  var onConfirm: () -> Void

  private let barHeight: CGFloat = 38

  var body: some View {
    HStack(spacing: 0) {
      if let cancelTitle, let onCancel {
        LiquidGlassBarSegment(
          title: cancelTitle,
          trailingKey: nil,
          isEnabled: true,
          isBusy: false,
          action: onCancel
        )

        // Etched vertical hairline divider
        Rectangle()
          .fill(
            LinearGradient(
              colors: [
                LiquidGlassTokens.veilFill.opacity(0.0),
                LiquidGlassTokens.veilFill.opacity(0.18),
                LiquidGlassTokens.veilFill.opacity(0.0),
              ],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .frame(width: LiquidGlassTokens.specularLineWidth, height: 16)
          .padding(.horizontal, 2)
      }

      LiquidGlassBarSegment(
        title: confirmTitle,
        trailingKey: confirmKey,
        isEnabled: isConfirmEnabled,
        isBusy: isBusy,
        action: onConfirm
      )
    }
    .padding(3)
    .frame(height: barHeight)
    .frame(minWidth: minWidth)
    .liquidGlassSurface(
      shape: Capsule(style: .continuous),
      substrate: LiquidGlassTokens.baseDarkness,
      tint: 0.04,
      highlight: .none,
      // Native glass draws its own edge; the composite path always wants the rim here.
      withRimLighting: true
    )
    .shadow(color: Color.black.opacity(0.20), radius: 10, y: 4)
    .animation(LiquidGlassTokens.settleSpring, value: isConfirmEnabled)
  }
}

// MARK: - Bar Segment

private struct LiquidGlassBarSegment: View {
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
      HStack(spacing: 6) {
        if isBusy {
          ProgressView()
            .controlSize(.small)
            .tint(LiquidGlassTokens.inkPrimary)
        }

        Text(title)
          .font(.system(size: 12, weight: (isHovered && isEnabled) ? .semibold : .medium))
          .foregroundStyle(
            !isEnabled
              ? LiquidGlassTokens.inkFaint
              : (isHovered ? LiquidGlassTokens.inkPrimary : LiquidGlassTokens.inkBody)
          )

        if let trailingKey, !isBusy {
          Text(trailingKey)
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(LiquidGlassTokens.veilFill.opacity((isHovered && isEnabled) ? 0.20 : 0.10))
            .clipShape(Radius.rect(Radius.ornament))
            .opacity(isEnabled ? 1.0 : 0.35)
        }
      }
      .padding(.horizontal, 14)
      .frame(maxHeight: .infinity)
      .liquidGlassSurface(
        shape: Capsule(style: .continuous),
        isVisible: isHovered && isEnabled,
        substrate: LiquidGlassTokens.controlSubstrateHover,
        tint: 0.10,
        highlight: .none,
        withRimLighting: isHovered && isEnabled,
        isInteractive: true
      )
      .contentShape(Capsule(style: .continuous))
    }
    .buttonStyle(LiquidGlassBarSegmentButtonStyle(isEnabled: isEnabled && !isBusy))
    .disabled(!isEnabled || isBusy)
    .onHover { hovering in
      guard isEnabled, !isBusy else {
        isHovered = false
        return
      }
      withAnimation(LiquidGlassTokens.hoverSpring) {
        isHovered = hovering
      }
    }
    .animation(LiquidGlassTokens.settleSpring, value: isEnabled)
  }

}

private struct LiquidGlassBarSegmentButtonStyle: ButtonStyle {
  var isEnabled: Bool = true

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect((configuration.isPressed && isEnabled) ? 0.96 : 1.0)
      .animation(LiquidGlassTokens.pressSpring, value: configuration.isPressed)
  }
}
