//
//  QuickAccessActionButton.swift
//  ClaudeShot
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
        .foregroundColor(.white)
        .frame(width: 32, height: 32)
        .background(
          Circle()
            .fill(isHovering ? Color.white.opacity(0.3) : Color.black.opacity(0.5))
        )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.15)) {
        isHovering = hovering
      }
    }
    .help(tooltip)
  }
}
