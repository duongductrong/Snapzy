//
//  QuickAccessTextButton.swift
//  Snapzy
//
//  Text-based action button for quick access screenshot cards
//

import SwiftUI

/// Text-based action button with hover effect for card overlays
struct QuickAccessTextButton: View {
  let label: String
  let action: () -> Void

  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Text(label)
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(LiquidGlassTokens.inkOverlay.opacity(isEnabled ? 1 : 0.55))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .liquidGlassChrome(
          shape: Capsule(style: .continuous),
          isVisible: true,
          isActive: isEnabled && isHovering,
          emphasis: .overlay
        )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      guard isEnabled else {
        isHovering = false
        return
      }
      withAnimation(LiquidGlassTokens.hoverSpring) {
        isHovering = hovering
      }
    }
  }
}
