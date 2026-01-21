//
//  QuickAccessTextButton.swift
//  ClaudeShot
//
//  Text-based action button for quick access screenshot cards
//

import SwiftUI

/// Text-based action button with hover effect for card overlays
struct QuickAccessTextButton: View {
  let label: String
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Text(label)
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 24)
            .fill(isHovering ? Color.white.opacity(0.35) : Color.black.opacity(0.6))
        )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.15)) {
        isHovering = hovering
      }
    }
  }
}
