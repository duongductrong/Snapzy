//
//  QuickAccessActionButton.swift
//  Snapzy
//
//  Reusable action button for quick access screenshot cards
//

import SwiftUI

/// Circular action button with hover effect for card overlays
struct QuickAccessActionButton: View {
  let icon: String
  let tooltip: String
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(LiquidGlassTokens.inkOverlay)
        .frame(width: 32, height: 32)
        // Stays lit at rest: the button overlays the capture itself, so there is nothing else to
        // signal it is interactive.
        .liquidGlassChrome(
          shape: Circle(),
          isVisible: true,
          isActive: isHovering,
          emphasis: .overlay
        )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(LiquidGlassTokens.hoverSpring) {
        isHovering = hovering
      }
    }
    .help(tooltip)
  }
}
