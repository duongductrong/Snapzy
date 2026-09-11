//
//  ToolbarControls.swift
//  Snapzy
//
//  Shared toolbar icon button and divider, with an opt-in Liquid Glass treatment.
//

import SwiftUI

// MARK: - Toolbar Item Style

/// Visual treatment for `ToolbarButton`. Opt in to `.glass` for toolbars that already use the
/// Liquid Glass design system, so a single row does not mix two button languages.
enum ToolbarButtonTreatment {
  case standard
  case glass
}

struct ToolbarButton: View {
  var treatment: ToolbarButtonTreatment = .standard
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
        .modifier(ToolbarButtonBackground(
          treatment: treatment,
          isEnabled: isEnabled,
          isSelected: isSelected,
          isHovering: isHovering,
          highlightColor: highlightColor
        ))
        // An SF Symbol only hit-tests its own glyph, and the glass surface contributes no
        // hit-testable content, so the click target has to be declared explicitly. Without this
        // the padding around the icon is dead and only a direct hit on the glyph activates.
        .contentShape(RoundedRectangle(cornerRadius: Size.radiusMd, style: .continuous))
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
      let next = isEnabled && hovering
      switch treatment {
      case .standard:
        isHovering = next
      case .glass:
        // The glass surface appears on hover, so it needs to ease in rather than pop.
        withAnimation(LiquidGlassTokens.hoverSpring) { isHovering = next }
      }
    }
    .animation(treatment == .glass ? LiquidGlassTokens.hoverSpring : nil, value: isSelected)
  }

  private var displayedIcon: String {
    if isSelected {
      return selectedIcon ?? icon
    }
    return icon
  }

  private var foregroundColor: Color {
    if isSelected {
      if let selectedForegroundColor { return selectedForegroundColor }
      // On glass the tint is carried by the surface, so tinting the glyph too would put e.g.
      // a blue icon on blue glass. Keep the glyph neutral and let the surface signal selection.
      return treatment == .glass ? .primary : highlightColor
    }
    return .primary
  }
}

/// Toolbar icon backgrounds. The glass surface wraps the icon so `.glassEffect` composites behind
/// it, and stays in the hierarchy as `Glass.identity` while resting — conditionally inserting it
/// would bring an implicit `.opacity` transition, which severs glass backdrop sampling.
private struct ToolbarButtonBackground: ViewModifier {
  let treatment: ToolbarButtonTreatment
  let isEnabled: Bool
  let isSelected: Bool
  let isHovering: Bool
  let highlightColor: Color

  func body(content: Content) -> some View {
    switch treatment {
    case .standard:
      content.background(RoundedRectangle(cornerRadius: 6).fill(standardFill))
    case .glass:
      // Resting icon buttons stay bare so the row does not read as a wall of pills; glass only
      // materialises under the pointer or on the active tool. Disabled buttons never show it —
      // callers dim them with `.opacity()`, which does not mix with glass.
      content.liquidGlassSurface(
        shape: RoundedRectangle(cornerRadius: Size.radiusMd, style: .continuous),
        isVisible: isVisible,
        substrate: isSelected ? 0.24 : 0.14,
        tint: isSelected ? 0.10 : 0.05,
        highlight: .none,
        withRimLighting: isVisible && !LiquidGlassCapabilities.hasNativeLiquidGlass,
        isInteractive: true,
        glassTint: isSelected ? selectedGlassTint : nil
      )
    }
  }

  private var isVisible: Bool {
    isEnabled && (isSelected || isHovering)
  }

  private var standardFill: Color {
    if isSelected { return highlightColor.opacity(0.3) }
    if isHovering { return Color.primary.opacity(0.1) }
    return .clear
  }

  /// `.primary` is the default highlight and is a label colour, not a tint — fall back to the
  /// accent so a selected tool still reads as selected on native glass.
  private var selectedGlassTint: Color {
    highlightColor == .primary ? .accentColor : highlightColor
  }
}

struct ToolbarDivider: View {
  var body: some View {
    Rectangle()
      .fill(Color(nsColor: .separatorColor))
      .frame(width: 1, height: 20)
      .padding(.horizontal, 4)
  }
}
