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
  var fontSize: CGFloat = 13

  var body: some View {
    keyLabel
      .frame(minWidth: 28, minHeight: 26)
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
  var fontSize: CGFloat = 13

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
        if index > 0 {
          Text("+")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(LiquidGlassTokens.inkMuted)
            .frame(width: 9, height: 16)
        }

        Text(part)
          .font(.system(size: fontSize, weight: .semibold, design: .rounded))
          .foregroundStyle(LiquidGlassTokens.inkPrimary)
          .lineLimit(1)
          .frame(minWidth: 24, minHeight: 22)
      }
    }
    .padding(.horizontal, 5)
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

/// Ghost glass pill shown when a shortcut row has no assignment yet.
/// Mirrors the keycap silhouette but with muted ink and a quieter substrate.
struct KeyCapPlaceholderView: View {
  let title: String
  var symbol: String = "return"
  var minWidth: CGFloat = 104

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: symbol)
        .font(.system(size: 12, weight: .semibold))
      Text(title)
        .font(.system(size: 13, weight: .medium, design: .rounded))
    }
    .foregroundStyle(LiquidGlassTokens.inkMuted)
    .frame(minWidth: minWidth, minHeight: 26)
    .padding(.horizontal, 8)
    .liquidGlassSurface(
      shape: Capsule(style: .continuous),
      substrate: 0.30,
      tint: 0.0,
      highlight: .none
    )
    .fixedSize(horizontal: true, vertical: false)
  }
}

/// Accent-tinted glass pill shown while the recorder listens for key input.
/// Same capsule silhouette as the keycaps, with a breathing status dot.
struct KeyCapRecordingView: View {
  var minWidth: CGFloat = 104

  @State private var isPulsing = false

  var body: some View {
    HStack(spacing: 7) {
      Circle()
        .fill(LiquidGlassTokens.inkOnAccent)
        .frame(width: 7, height: 7)
        .opacity(isPulsing ? 0.25 : 1)

      Text(L10n.ShortcutRecorder.pressKeys)
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(LiquidGlassTokens.inkOnAccent)
        .lineLimit(1)
    }
    .frame(minWidth: minWidth, minHeight: 26)
    .padding(.horizontal, 8)
    .liquidGlassSurface(
      shape: Capsule(style: .continuous),
      substrate: LiquidGlassTokens.controlSubstrateHover,
      tint: 0.14,
      highlight: .specular,
      glassTint: .accentColor
    )
    .fixedSize(horizontal: true, vertical: false)
    .onAppear {
      withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
        isPulsing = true
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
    KeyCapPlaceholderView(title: "Set Shortcut")
    KeyCapRecordingView(minWidth: 104)
  }
  .padding(32)
}
