//
//  LiquidGlassButtonSurface.swift
//  Snapzy
//
//  Hover/press-aware glass surface backing LiquidGlassButtonStyle.
//

import SwiftUI

// MARK: - Button Surface

struct LiquidGlassButtonSurface: View {
  let configuration: ButtonStyleConfiguration
  let emphasis: LiquidGlassActionEmphasis
  let capsule: Bool
  let isActive: Bool

  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovered = false

  private var isVisuallyActive: Bool { (isHovered && isEnabled) || isActive }
  private var isPressed: Bool { configuration.isPressed && isEnabled }

  var body: some View {
    configuration.label
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(foreground)
      .padding(.horizontal, capsule ? 14 : 12)
      .padding(.vertical, capsule ? 7 : 6)
      .modifier(
        // Values are resolved here, where @State/@Environment are valid, rather than read back
        // out of a copy of this view from inside the modifier's own body.
        LiquidGlassButtonBackground(
          capsule: capsule,
          substrate: currentSubstrate,
          tint: currentTint,
          glassTint: currentGlassTint,
          isEnabled: isEnabled,
          isActive: isVisuallyActive
        )
      )
      .overlay { borderLayer }
      .contentShape(hitShape)
      .scaleEffect(isPressed ? 0.97 : 1.0)
      .onHover { hovering in
        guard isEnabled else {
          isHovered = false
          return
        }
        withAnimation(LiquidGlassTokens.hoverSpring) {
          isHovered = hovering
        }
      }
      .onChange(of: isEnabled) { enabled in
        // Disabling a hovered button never delivers an exit event, so clear it explicitly.
        if !enabled { isHovered = false }
      }
      .animation(LiquidGlassTokens.hoverSpring, value: isHovered)
      .animation(LiquidGlassTokens.hoverSpring, value: isActive)
      .animation(LiquidGlassTokens.pressSpring, value: configuration.isPressed)
  }

  @ViewBuilder
  private var borderLayer: some View {
    // Native glass draws its own refractive edge; a second stroke on top reads as a white outline.
    if !LiquidGlassCapabilities.hasNativeLiquidGlass {
      if capsule {
        LiquidGlassRimBorder(
          shape: Capsule(style: .continuous),
          isHovered: isVisuallyActive,
          isEnabled: isEnabled,
          emphasis: emphasis
        )
      } else {
        LiquidGlassRimBorder(
          shape: RoundedRectangle(cornerRadius: LiquidGlassTokens.controlRadius, style: .continuous),
          isHovered: isVisuallyActive,
          isEnabled: isEnabled,
          emphasis: emphasis
        )
      }
    }
  }

  private var hitShape: AnyShape {
    capsule
      ? AnyShape(Capsule(style: .continuous))
      : AnyShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.controlRadius, style: .continuous))
  }

  // MARK: - Legacy Composite Levels

  private var currentSubstrate: CGFloat {
    guard isEnabled else { return 0 }
    switch emphasis {
    case .primary: return isPressed ? 0.38 : (isVisuallyActive ? 0.28 : 0.20)
    case .secondary: return isPressed ? 0.30 : (isVisuallyActive ? 0.22 : 0.12)
    case .destructive: return isPressed ? 0.30 : (isVisuallyActive ? 0.20 : 0.10)
    case .contextPill:
      return isPressed
        ? LiquidGlassTokens.controlSubstratePressed
        : (isVisuallyActive
          ? LiquidGlassTokens.controlSubstrateHover
          : LiquidGlassTokens.controlSubstrateResting)
    }
  }

  private var currentTint: CGFloat {
    guard isEnabled else { return 0.04 }
    switch emphasis {
    case .primary: return isPressed ? 0.22 : (isVisuallyActive ? 0.16 : 0.12)
    case .secondary: return isPressed ? 0.12 : (isVisuallyActive ? 0.08 : 0.03)
    case .destructive: return isPressed ? 0.28 : (isVisuallyActive ? 0.18 : 0.08)
    case .contextPill: return isPressed ? 0.12 : (isVisuallyActive ? 0.08 : 0.04)
    }
  }

  // MARK: - Native Glass Tint

  private var currentGlassTint: Color? {
    guard isEnabled else { return nil }
    switch emphasis {
    case .primary: return .accentColor
    case .destructive: return .red
    case .secondary, .contextPill: return isActive ? .accentColor : nil
    }
  }

  // MARK: - Ink

  private var foreground: Color {
    guard isEnabled else { return LiquidGlassTokens.inkFaint }
    switch emphasis {
    case .primary, .destructive:
      // A saturated accent/red tint is dark in both appearances, so the label stays white —
      // this matches `.glassProminent`. Adaptive ink would put near-black text on accent blue
      // in Light Aqua, which lands around 3:1 and fails AA at 12pt.
      return currentGlassTint == nil ? LiquidGlassTokens.inkPrimary : .white
    case .secondary:
      return isVisuallyActive ? LiquidGlassTokens.inkPrimary : LiquidGlassTokens.inkBody
    case .contextPill:
      return isVisuallyActive ? LiquidGlassTokens.inkPrimary : LiquidGlassTokens.inkMuted
    }
  }
}

// MARK: - Background

/// Applies the glass surface for whichever shape the button uses. Kept as a `ViewModifier` so the
/// generic shape is resolved once, and so the elevation shadow lands on the surface rather than on
/// the label's glyphs.
private struct LiquidGlassButtonBackground: ViewModifier {
  let capsule: Bool
  let substrate: CGFloat
  let tint: CGFloat
  let glassTint: Color?
  let isEnabled: Bool
  let isActive: Bool

  func body(content: Content) -> some View {
    if capsule {
      apply(content, shape: Capsule(style: .continuous))
    } else {
      apply(
        content,
        shape: RoundedRectangle(cornerRadius: LiquidGlassTokens.controlRadius, style: .continuous)
      )
    }
  }

  private func apply<S: InsettableShape>(_ content: Content, shape: S) -> some View {
    content
      .liquidGlassSurface(
        shape: shape,
        substrate: substrate,
        tint: tint,
        highlight: .none,
        withRimLighting: isEnabled && !LiquidGlassCapabilities.hasNativeLiquidGlass,
        isInteractive: isEnabled,
        glassTint: glassTint
      )
      .shadow(color: shadowColor, radius: isActive ? 4 : 2, x: 0, y: isActive ? 2 : 1)
  }

  /// Native glass carries its own elevation, and a shadow here would also fall on the glyphs.
  private var shadowColor: Color {
    guard isEnabled, !LiquidGlassCapabilities.hasNativeLiquidGlass else { return .clear }
    return Color.black.opacity(isActive ? 0.24 : 0.12)
  }
}
