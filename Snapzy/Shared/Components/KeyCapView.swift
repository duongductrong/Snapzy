//
//  KeyCapView.swift
//  Snapzy
//
//  macOS-native keycap rendering for keyboard shortcuts
//

import SwiftUI

/// Renders a single keyboard key as a compact glass keycap.
struct KeyCapView: View {
  let symbol: String
  var fontSize: CGFloat = 12

  var body: some View {
    keyLabel
      .frame(minWidth: 24, minHeight: 22)
      .liquidGlassSurface(
        shape: Radius.rect(Radius.ornament),
        substrate: LiquidGlassTokens.controlSubstrateResting,
        tint: 0.02,
        highlight: .specular
      )
  }

  private var keyLabel: some View {
    Text(symbol)
      .font(.system(size: fontSize, weight: .semibold, design: .rounded))
      .foregroundStyle(LiquidGlassTokens.inkPrimary)
      .lineLimit(1)
  }
}

/// Renders a shortcut as one continuous badge with lightly etched key separators.
struct KeyCapGroupView: View {
  let parts: [String]
  var fontSize: CGFloat = 12

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
        if index > 0 {
          Text("+")
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(LiquidGlassTokens.inkMuted)
            .frame(width: 8, height: 14)
        }

        Text(part)
          .font(.system(size: fontSize, weight: .semibold, design: .rounded))
          .foregroundStyle(LiquidGlassTokens.inkPrimary)
          .lineLimit(1)
          .frame(minWidth: 20, minHeight: 18)
      }
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 2)
    .liquidGlassSurface(
      shape: Capsule(style: .continuous),
      substrate: LiquidGlassTokens.controlSubstrateResting,
      tint: 0.02,
      highlight: .specular
    )
    .fixedSize(horizontal: true, vertical: false)
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
