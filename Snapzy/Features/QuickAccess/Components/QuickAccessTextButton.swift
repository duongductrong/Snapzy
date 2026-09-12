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
        .foregroundColor(.white.opacity(isEnabled ? 1 : 0.75))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 24)
            .fill(buttonBackgroundColor)
        )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      guard isEnabled else {
        isHovering = false
        return
      }
      withAnimation(.easeInOut(duration: 0.15)) {
        isHovering = hovering
      }
    }
  }

  private var buttonBackgroundColor: Color {
    guard isEnabled else {
      return Color.black.opacity(0.45)
    }
    return isHovering ? Color.white.opacity(0.35) : Color.black.opacity(0.6)
  }
}
