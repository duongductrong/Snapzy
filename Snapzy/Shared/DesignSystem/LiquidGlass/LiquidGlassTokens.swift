//
//  LiquidGlassTokens.swift
//  Snapzy
//
//  Design tokens for Liquid Glass surfaces, specular hairline physics, and debug flags.
//

import AppKit
import SwiftUI

// MARK: - Capabilities

enum LiquidGlassRenderMode: String, CaseIterable, Identifiable {
  case system = "system"
  case native = "native"
  case legacy = "legacy"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system:
      return "System Default"
    case .native:
      return "macOS 26+ (Apple Liquid Glass)"
    case .legacy:
      return "macOS 13–15 (Fallback Composite)"
    }
  }
}

struct LiquidGlassTuning: Equatable {
  var substrateOpacity: CGFloat = LiquidGlassTokens.baseDarkness
  var sheenTopOpacity: Double = LiquidGlassTokens.fallbackControlSheenTop
  var sheenBottomOpacity: Double = LiquidGlassTokens.fallbackControlSheenBottom
  var specularTopOpacity: Double = 0.22
  var specularBottomOpacity: Double = 0.06
  var isSubstrateEnabled: Bool = true
  var isRefractionEnabled: Bool = true
  var isVeilEnabled: Bool = true
  var isSpecularEnabled: Bool = true
  var isRimLightingEnabled: Bool = true

  static let `default` = LiquidGlassTuning()
}

private struct LiquidGlassRenderModeKey: EnvironmentKey {
  static let defaultValue: LiquidGlassRenderMode = .system
}

private struct LiquidGlassTuningKey: EnvironmentKey {
  static let defaultValue: LiquidGlassTuning? = nil
}

extension EnvironmentValues {
  var liquidGlassRenderMode: LiquidGlassRenderMode {
    get { self[LiquidGlassRenderModeKey.self] }
    set { self[LiquidGlassRenderModeKey.self] = newValue }
  }

  var liquidGlassTuning: LiquidGlassTuning? {
    get { self[LiquidGlassTuningKey.self] }
    set { self[LiquidGlassTuningKey.self] = newValue }
  }
}

enum LiquidGlassCapabilities {
  /// Dynamic runtime override for in-app testing and playground inspection.
  static var runtimeLegacyOverride: Bool? = nil

  /// Whether the host operating system supports Apple's native Liquid Glass APIs.
  static var isSystemSupported: Bool {
    if #available(macOS 26.0, *) {
      return true
    }
    return false
  }

  /// Whether the user enabled Liquid Glass in Settings (default true).
  static var isUserPreferenceEnabled: Bool {
    UserDefaults.standard.object(forKey: PreferencesKeys.useLiquidGlass) as? Bool ?? true
  }

  /// Forces the pre-26 fallback path for local testing and validation.
  #if DEBUG
    static let argumentForcesLegacy: Bool =
      ProcessInfo.processInfo.arguments.contains("-SnapzyForceLegacyGlass")
      || ProcessInfo.processInfo.environment["SNAPZY_FORCE_LEGACY_GLASS"] == "1"

    static var forcesLegacyGlass: Bool {
      if let runtime = runtimeLegacyOverride {
        return runtime
      }
      if !isUserPreferenceEnabled {
        return true
      }
      return argumentForcesLegacy
    }
  #else
    static var forcesLegacyGlass: Bool {
      if let runtime = runtimeLegacyOverride {
        return runtime
      }
      if !isUserPreferenceEnabled {
        return true
      }
      return false
    }
  #endif

  /// Whether the host operating system supports Apple's native Liquid Glass APIs and is not forced to fallback.
  static var hasNativeLiquidGlass: Bool {
    isSystemSupported && !forcesLegacyGlass
  }

  /// Evaluates whether native glass is active given a scoped render mode.
  ///
  /// `userEnabled` is the caller's reactive `@AppStorage` read of `PreferencesKeys.useLiquidGlass`.
  /// It is passed in rather than re-read here so SwiftUI records a dependency on the preference at
  /// the call site — reading `isUserPreferenceEnabled` inside a view body does not invalidate that
  /// view when the toggle flips, which is exactly what left the effect stuck on the old path.
  static func usesNativeGlass(for mode: LiquidGlassRenderMode, userEnabled: Bool) -> Bool {
    switch mode {
    case .system:
      guard userEnabled, isSystemSupported else { return false }
      return !developerForcedLegacy
    case .native:
      if #available(macOS 26.0, *) {
        return true
      }
      return false
    case .legacy:
      return false
    }
  }

  /// Non-reactive convenience for tests, previews, and call sites that already observe the setting.
  static func usesNativeGlass(for mode: LiquidGlassRenderMode) -> Bool {
    usesNativeGlass(for: mode, userEnabled: isUserPreferenceEnabled)
  }

  /// Developer-only override (`-SnapzyForceLegacyGlass` or the legacy runtime flag).
  private static var developerForcedLegacy: Bool {
    if let runtimeLegacyOverride {
      return runtimeLegacyOverride
    }
    #if DEBUG
      return argumentForcesLegacy
    #else
      return false
    #endif
  }
}

// MARK: - Tokens

enum LiquidGlassTokens {
  // Base dark substrate (Dark Aqua)
  static let baseDarkness: CGFloat = 0.60
  static let fallbackSubstrateScale: CGFloat = 0.40

  // Specular hairline physics
  static let specularLineWidth: CGFloat = 0.50
  static let specularTopColor: Color = .white.opacity(0.22)
  static let specularBottomColor: Color = .white.opacity(0.06)

  // Control substrate levels
  static let controlSubstrateResting: CGFloat = 0.45
  static let controlSubstrateHover: CGFloat = 0.60
  static let controlSubstratePressed: CGFloat = 0.72

  // Control stroke levels
  static let controlStrokeResting: CGFloat = 0.12
  static let controlStrokeHover: CGFloat = 0.26

  // Fallback control gradient sheen
  static let fallbackControlSheenTop: Double = 0.00
  static let fallbackControlSheenBottom: Double = 0.00

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

  // Radii — thin aliases onto the app-wide scale in RadiusTokens.swift, so glass surfaces and
  // plain chrome cannot drift apart. `controlRadius` is the non-capsule text-button radius, which
  // is the 28pt control step.
  static let controlRadius = Radius.controlM
  static let cardRadius = Radius.card
  static let surfaceRadius = Radius.panel
  static let windowRadius = Radius.window

  // Spring physics
  static let hoverSpring: Animation = .spring(response: 0.28, dampingFraction: 0.75)
  static let pressSpring: Animation = .spring(response: 0.18, dampingFraction: 0.80)
  static let settleSpring: Animation = .spring(response: 0.24, dampingFraction: 0.82)

  // Text Ink — resolves per drawing appearance so glass controls stay legible in Light Aqua.
  static let inkPrimary: Color = adaptiveInk(dark: 1.00, light: 0.92)
  static let inkBody: Color = adaptiveInk(dark: 0.72, light: 0.68)
  static let inkMuted: Color = adaptiveInk(dark: 0.46, light: 0.50)
  static let inkFaint: Color = adaptiveInk(dark: 0.24, light: 0.28)

  /// Ink for `.overlay` chrome. Does *not* adapt: overlay controls pin their own glass dark
  /// through `LiquidGlassChromeEmphasis.glassTint(isActive:)`, so they stay light in both
  /// appearances — a screenshot's brightness has nothing to do with Light or Dark Aqua.
  static let inkOverlay: Color = .white

  /// Ink for content sitting on an accent-tinted glass surface — the `isActive` state of every
  /// glass control. See `ink(onTint:otherwise:)`.
  static var inkOnAccent: Color { ink(onTint: .accentColor) }

  /// Ink for content sitting on a colour-tinted glass surface.
  ///
  /// Both macOS 26+ native glass and macOS 13–15 fallback composite render `glassTint`,
  /// so ink resolves against the tint's own luminance to maintain > 4.5:1 contrast across
  /// all appearances.
  static func ink(onTint tint: Color?, otherwise fallback: Color = inkPrimary) -> Color {
    guard let tint else { return fallback }
    return resolveTintLuminanceInk(tint: tint)
  }

  static func ink(onTint tint: Color?, renderMode: LiquidGlassRenderMode, otherwise fallback: Color = inkPrimary) -> Color {
    guard let tint else { return fallback }
    return resolveTintLuminanceInk(tint: tint)
  }

  private static func resolveTintLuminanceInk(tint: Color) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
      var luminance: CGFloat = 0
      appearance.performAsCurrentDrawingAppearance {
        luminance = relativeLuminance(of: tint)
      }
      // Accent blue, red and graphite all land well under this, so they keep white glyphs. Only a
      // genuinely bright tint (a yellow or orange accent) flips to dark ink.
      return luminance > 0.55 ? NSColor.black.withAlphaComponent(0.88) : .white
    })
  }

  /// sRGB relative luminance (WCAG). Falls back to 0 — and therefore to white ink — for a colour
  /// that cannot be bridged, which is the right default for the accent tints in use.
  private static func relativeLuminance(of color: Color) -> CGFloat {
    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return 0 }

    func channel(_ value: CGFloat) -> CGFloat {
      value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    return 0.2126 * channel(rgb.redComponent)
      + 0.7152 * channel(rgb.greenComponent)
      + 0.0722 * channel(rgb.blueComponent)
  }

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
