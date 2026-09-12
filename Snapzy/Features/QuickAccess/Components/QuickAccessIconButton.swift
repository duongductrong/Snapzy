//
//  QuickAccessIconButton.swift
//  Snapzy
//
//  Reusable icon button with hover effect and cursor state for quick access cards
//

import AppKit
import SwiftUI

/// Icon button with hover effect and pointer cursor for card action buttons
struct QuickAccessIconButton: View {
  let icon: String
  let action: () -> Void
  var helpText: String? = nil

  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovering = false
  @State private var isPressed = false

  var body: some View {
    Button(action: {
      guard isEnabled else { return }
      // Immediate visual feedback before action
      withAnimation(LiquidGlassTokens.pressSpring) {
        isPressed = true
      }
      // Execute action immediately
      action()
      // Reset press state
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        isPressed = false
      }
    }) {
      Image(systemName: icon)
        .font(.system(size: 10, weight: .bold))
        .foregroundColor(LiquidGlassTokens.inkOverlay.opacity(isEnabled ? 1 : 0.55))
        .frame(width: 20, height: 20)
        // These buttons are the only affordance on the card, so the surface stays lit at rest
        // rather than materialising on hover. `.overlay` emphasis pins the glass dark so the
        // glyph stays legible whether the capture underneath is a white page or a black terminal.
        .liquidGlassChrome(
          shape: Circle(),
          isVisible: true,
          isActive: isEnabled && (isPressed || isHovering),
          emphasis: .overlay
        )
        // Rule 2: scale folds into a transform, so it never detaches the backdrop the way an
        // animated `.opacity` would.
        .scaleEffect(isPressed ? 0.85 : 1.0)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      guard isEnabled else {
        isHovering = false
        NSCursor.arrow.set()
        return
      }
      withAnimation(LiquidGlassTokens.hoverSpring) {
        isHovering = hovering
      }
      if hovering {
        NSCursor.pointingHand.set()
      } else {
        NSCursor.arrow.set()
      }
    }
    .if(helpText != nil) { view in
      view.help(helpText!)
    }
  }

}
