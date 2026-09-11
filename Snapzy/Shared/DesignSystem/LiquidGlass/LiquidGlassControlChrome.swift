//
//  LiquidGlassControlChrome.swift
//  Snapzy
//
//  Glass chrome for compact property-bar controls — one treatment, one hover rule, one hit target.
//

import SwiftUI

extension View {
  /// Replaces the fill-plus-stroke chrome used by compact property-bar controls with a Liquid
  /// Glass surface.
  ///
  /// Apply this to a control's *label content*, inside the `Button`. It owns its own hover state,
  /// so call sites stay declarative, and it declares an explicit hit target — a glass surface
  /// contributes no hit-testable content, so without one only the glyph responds to clicks.
  func liquidGlassControl(isActive: Bool, cornerRadius: CGFloat = 7) -> some View {
    modifier(LiquidGlassControlChrome(isActive: isActive, cornerRadius: cornerRadius))
  }
}

private struct LiquidGlassControlChrome: ViewModifier {
  let isActive: Bool
  let cornerRadius: CGFloat

  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovering = false

  func body(content: Content) -> some View {
    content
      .liquidGlassSurface(
        shape: shape,
        isVisible: showsGlass,
        substrate: isActive ? 0.24 : 0.14,
        tint: isActive ? 0.10 : 0.05,
        highlight: .none,
        withRimLighting: showsGlass && !LiquidGlassCapabilities.hasNativeLiquidGlass,
        isInteractive: true,
        glassTint: isActive ? .accentColor : nil
      )
      .contentShape(shape)
      .onHover { hovering in
        // Disabling a hovered control never delivers an exit event, so clear it explicitly.
        withAnimation(LiquidGlassTokens.hoverSpring) {
          isHovering = isEnabled && hovering
        }
      }
      .animation(LiquidGlassTokens.hoverSpring, value: isActive)
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
  }

  /// Resting controls render no glass at all. That keeps the cost of a dense property bar
  /// proportional to the one or two surfaces actually lit, not to the number of buttons in it.
  private var showsGlass: Bool {
    isEnabled && (isActive || isHovering)
  }
}
