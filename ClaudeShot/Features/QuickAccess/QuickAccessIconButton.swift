//
//  QuickAccessIconButton.swift
//  ClaudeShot
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

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 10, weight: .bold))
        .foregroundColor(.white)
        .frame(width: 20, height: 20)
        .background(
          Circle()
            .fill(isHovering ? Color.white.opacity(0.35) : Color.black.opacity(0.6))
        )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.15)) {
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
