//
//  ToolbarControls.swift
//  Snapzy
//
//  Shared toolbar and bottom-bar icon buttons, on the Liquid Glass design system.
//

import SwiftUI

// MARK: - Toolbar Button

/// Toolbar icon button. Resting buttons stay bare so a row does not read as a wall of pills —
/// glass only materialises under the pointer or on the active tool.
struct ToolbarButton: View {
  let icon: String
  var selectedIcon: String? = nil
  let isSelected: Bool
  var highlightColor: Color = .primary
  var selectedForegroundColor: Color? = nil
  var selectedBadgeIcon: String? = nil

  let action: () -> Void

  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: displayedIcon)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(foregroundColor)
        .frame(width: 28, height: 28)
        // Disabled buttons never show glass. Their dimming is applied to the glyph colour below,
        // never as an `.opacity()` around this surface — that would detach the backdrop (Rule 2).
        .liquidGlassChrome(
          shape: RoundedRectangle(cornerRadius: Size.radiusMd, style: .continuous),
          isVisible: showsGlass,
          isActive: isSelected,
          glassTint: isSelected ? selectedGlassTint : nil
        )
        .overlay(alignment: .topTrailing) {
          if let selectedBadgeIcon, isSelected {
            Image(systemName: selectedBadgeIcon)
              .font(.system(size: 7, weight: .bold))
              .foregroundColor(highlightColor)
              .frame(width: 12, height: 12)
              .background(Circle().fill(Color.white))
              .offset(x: 3, y: -3)
          }
        }
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      // Disabling a hovered button never delivers an exit event, so clear it explicitly.
      // The glass surface appears on hover, so it needs to ease in rather than pop.
      withAnimation(LiquidGlassTokens.hoverSpring) { isHovering = isEnabled && hovering }
    }
    .animation(LiquidGlassTokens.hoverSpring, value: isSelected)
  }

  private var showsGlass: Bool {
    isEnabled && (isSelected || isHovering)
  }

  private var displayedIcon: String {
    if isSelected {
      return selectedIcon ?? icon
    }
    return icon
  }

  /// Disabled dimming lives here rather than in a caller's `.opacity()`. An `.opacity()` wrapped
  /// around the button would enclose its glass surface, promoting it to an offscreen buffer and
  /// severing backdrop sampling (Rule 2).
  private var foregroundColor: Color {
    // A disabled button renders no glass (`showsGlass`), so there is no tint to resolve against
    // and the glyph keeps the adaptive ink, dimmed.
    guard isEnabled else { return Color.primary.opacity(Self.disabledInk) }

    // The tint is carried by the surface, so tinting the glyph too would put e.g. a blue icon on
    // blue glass. It still has to survive that surface: an accent-tinted pill is dark in both
    // appearances, so a selected glyph reads white rather than following the app appearance —
    // `.primary` put black icons on the blue pills in Light theme.
    guard isSelected else { return .primary }
    return selectedForegroundColor ?? LiquidGlassTokens.ink(onTint: selectedGlassTint)
  }

  fileprivate static let disabledInk: Double = 0.4

  /// `.primary` is the default highlight and is a label colour, not a tint — fall back to the
  /// accent so a selected tool still reads as selected on native glass.
  private var selectedGlassTint: Color {
    highlightColor == .primary ? .accentColor : highlightColor
  }
}

// MARK: - Bottom Bar Button

/// Bottom-bar icon button. Same chrome as `ToolbarButton` without the selected state, shared by
/// the Annotate and Video Editor bottom bars.
struct BottomBarButton: View {
  let icon: String
  let tooltip: String
  let action: () -> Void

  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 14))
        .foregroundColor(isEnabled ? .primary : Color.primary.opacity(ToolbarButton.disabledInk))
        .frame(width: 28, height: 28)
        .liquidGlassChrome(
          shape: RoundedRectangle(cornerRadius: Size.radiusMd, style: .continuous),
          isVisible: isEnabled && isHovering
        )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(LiquidGlassTokens.hoverSpring) { isHovering = isEnabled && hovering }
    }
    .help(tooltip)
  }
}

// MARK: - Divider

struct ToolbarDivider: View {
  var body: some View {
    Rectangle()
      .fill(Color(nsColor: .separatorColor))
      .frame(width: 1, height: 20)
      .padding(.horizontal, 4)
  }
}
