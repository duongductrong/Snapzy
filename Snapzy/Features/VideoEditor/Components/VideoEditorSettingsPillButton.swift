//
//  VideoEditorSettingsPillButton.swift
//  Snapzy
//
//  Bottom-bar settings pill for the video editor: single-line icon + title sized to match
//  the neighbouring liquid glass buttons. Tapping toggles its section in the settings
//  drawer that expands above the bar; the glass surface stays lit while the section is open.
//

import SwiftUI

/// A minimal tab pill for the video editor bottom bar. The caller owns the expanded state —
/// tapping the pill toggles its drawer section, so the pill can light up while it is open
/// and hand the surface back when it closes.
struct VideoEditorSettingsPillButton: View {
  let icon: String
  let title: String
  let isActive: Bool
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: icon)
          .font(.system(size: 11, weight: .semibold))

        Text(title)
          .font(.system(size: 12, weight: .medium))
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 7)
      .liquidGlassChrome(
        shape: Capsule(style: .continuous),
        isVisible: isHovered || isActive,
        isActive: isActive
      )
      .animation(LiquidGlassTokens.hoverSpring, value: isHovered)
      .animation(LiquidGlassTokens.hoverSpring, value: isActive)
      .contentShape(Capsule(style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(LiquidGlassTokens.hoverSpring) { isHovered = hovering }
    }
    .help(title)
  }
}
