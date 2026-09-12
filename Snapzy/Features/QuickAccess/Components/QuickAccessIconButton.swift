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
      withAnimation(.easeOut(duration: 0.05)) {
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
        .foregroundColor(.white.opacity(isEnabled ? 1 : 0.7))
        .frame(width: 20, height: 20)
        .background(
          Circle()
            .fill(buttonBackgroundColor)
        )
        .scaleEffect(isPressed ? 0.85 : 1.0)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      guard isEnabled else {
        isHovering = false
        NSCursor.arrow.set()
        return
      }
      withAnimation(.easeInOut(duration: 0.1)) {
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

  private var buttonBackgroundColor: Color {
    if !isEnabled {
      return Color.black.opacity(0.4)
    } else if isPressed {
      return Color.white.opacity(0.5)
    } else if isHovering {
      return Color.white.opacity(0.35)
    } else {
      return Color.black.opacity(0.6)
    }
  }
}
