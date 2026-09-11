//
//  LiquidGlassTokens.swift
//  Snapzy
//
//  Design tokens for Liquid Glass surfaces, specular hairline physics, and debug flags.
//

import AppKit
import SwiftUI

// MARK: - Capabilities

enum LiquidGlassCapabilities {
  /// Forces the pre-26 fallback path for local testing and validation.
  #if DEBUG
    static let forcesLegacyGlass: Bool =
      ProcessInfo.processInfo.arguments.contains("-SnapzyForceLegacyGlass")
      || ProcessInfo.processInfo.environment["SNAPZY_FORCE_LEGACY_GLASS"] == "1"
  #else
    static let forcesLegacyGlass: Bool = false
  #endif

  /// Whether the host operating system supports Apple's native Liquid Glass APIs.
  static var hasNativeLiquidGlass: Bool {
    if #available(macOS 26.0, *) {
      !forcesLegacyGlass
    } else {
      false
    }
  }
}

// MARK: - Tokens

enum LiquidGlassTokens {
  // Base dark substrate (Dark Aqua)
  static let baseDarkness: CGFloat = 0.28
  static let fallbackSubstrateScale: CGFloat = 0.40

  // Specular hairline physics
  static let specularLineWidth: CGFloat = 0.50
  static let specularTopColor: Color = .white.opacity(0.16)
  static let specularBottomColor: Color = .white.opacity(0.04)

  // Control substrate levels
  static let controlSubstrateResting: CGFloat = 0.20
  static let controlSubstrateHover: CGFloat = 0.28
  static let controlSubstratePressed: CGFloat = 0.36

  // Control stroke levels
  static let controlStrokeResting: CGFloat = 0.08
  static let controlStrokeHover: CGFloat = 0.22

  // Fallback control gradient sheen
  static let fallbackControlSheenTop: Double = 0.10
  static let fallbackControlSheenBottom: Double = 0.02

  // Leading & Trailing edge lighting (convex rim reflections)
  static let rimLeadingResting: Double = 0.34
  static let rimLeadingHover: Double = 0.56
  static let rimTrailingResting: Double = 0.22
  static let rimTrailingHover: Double = 0.42

  // Lens caustics / corner glare blooms
  static let glareLeadingResting: Double = 0.18
  static let glareLeadingHover: Double = 0.32
  static let glareTrailingResting: Double = 0.12
  static let glareTrailingHover: Double = 0.24

  // Radii
  static let controlRadius: CGFloat = 10
  static let cardRadius: CGFloat = 14
  static let surfaceRadius: CGFloat = 20
  static let windowRadius: CGFloat = 26

  // Spring physics
  static let hoverSpring: Animation = .spring(response: 0.28, dampingFraction: 0.75)
  static let pressSpring: Animation = .spring(response: 0.18, dampingFraction: 0.80)
  static let settleSpring: Animation = .spring(response: 0.24, dampingFraction: 0.82)

  // Text Ink — resolves per drawing appearance so glass controls stay legible in Light Aqua.
  static let inkPrimary: Color = adaptiveInk(dark: 1.00, light: 0.92)
  static let inkBody: Color = adaptiveInk(dark: 0.72, light: 0.68)
  static let inkMuted: Color = adaptiveInk(dark: 0.46, light: 0.50)
  static let inkFaint: Color = adaptiveInk(dark: 0.24, light: 0.28)

  /// Substrate fill. Darkens the composite under Dark Aqua, lightens it under Aqua, so the
  /// `substrate` opacities below read the same way in both appearances.
  static let substrateFill: Color = adaptiveNeutral(dark: .black, light: .white)

  /// Body tint / veil fill. Inverse of the substrate: lifts the control off its backdrop.
  static let veilFill: Color = adaptiveNeutral(dark: .white, light: .black)

  /// Resolves substrate compensation for fallback vibrancy backdrops.
  static func backdropSubstrate(_ base: CGFloat) -> CGFloat {
    LiquidGlassCapabilities.hasNativeLiquidGlass ? base : base * fallbackSubstrateScale
  }

  /// Light Aqua glass is thinner than Dark Aqua, so veils need to be pulled back to avoid muddying it.
  static func veilOpacity(_ base: Double, isDark: Bool) -> Double {
    isDark ? base : base * 0.55
  }

  static func isDark(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
  }

  private static func adaptiveInk(dark: CGFloat, light: CGFloat) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
      isDark(appearance)
        ? NSColor.white.withAlphaComponent(dark)
        : NSColor.black.withAlphaComponent(light)
    })
  }

  private static func adaptiveNeutral(dark: NSColor, light: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
      isDark(appearance) ? dark : light
    })
  }
}
