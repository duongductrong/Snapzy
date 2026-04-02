//
//  KeyCapView.swift
//  Snapzy
//
//  macOS-native keycap rendering for keyboard shortcuts
//

import SwiftUI

/// Renders a single keyboard key as a raised keycap pill
struct KeyCapView: View {
  let symbol: String
  var fontSize: CGFloat = 12

  var body: some View {
    Text(symbol)
      .font(.system(size: fontSize, weight: .medium, design: .rounded))
      .foregroundColor(.primary)
      .frame(minWidth: 24, minHeight: 22)
      .padding(.horizontal, 6)
      .background(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(Color(nsColor: .controlBackgroundColor))
          .shadow(color: .black.opacity(0.06), radius: 0.5, x: 0, y: 0.5)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
      )
  }
}

/// Renders an array of key parts as keycap pills separated by „+"
struct KeyCapGroupView: View {
  let parts: [String]
  var fontSize: CGFloat = 12

  var body: some View {
    HStack(spacing: 4) {
      ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
        if index > 0 {
          Text("+")
            .font(.system(size: 10, weight: .regular))
            .foregroundColor(.secondary)
        }
        KeyCapView(symbol: part, fontSize: fontSize)
      }
    }
  }
}

#Preview("KeyCap Group") {
  VStack(spacing: 16) {
    KeyCapGroupView(parts: ["⌘", "⇧", "3"])
    KeyCapGroupView(parts: ["⌃", "Y"])
    KeyCapGroupView(parts: ["⌥", "⌘", "A"])
    KeyCapView(symbol: "R")
  }
  .padding(32)
}
