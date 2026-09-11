//
//  LiquidGlassSurface.swift
//  Snapzy
//
//  Dual-path glass surface: Apple's native Liquid Glass on macOS 26+, 4-layer optical
//  composite (substrate, refraction, tint, specular hairline) on macOS 13–15.
//

import AppKit
import SwiftUI

enum LiquidGlassLayer {
  case backdrop
  case control
}

enum LiquidGlassHighlight: Equatable {
  case specular
  case custom(top: Double, bottom: Double)
  case none

  var stops: (top: Color, bottom: Color)? {
    switch self {
    case .specular:
      return (LiquidGlassTokens.specularTopColor, LiquidGlassTokens.specularBottomColor)
    case let .custom(top, bottom):
      return (.white.opacity(top), .white.opacity(bottom))
    case .none:
      return nil
    }
  }
}

// MARK: - Legacy Refraction Layer

/// Refraction pass for macOS 13–15, where `.glassEffect` is unavailable.
struct LiquidGlassRefraction<S: InsettableShape>: View {
  var shape: S
  var layer: LiquidGlassLayer = .control

  @ViewBuilder
  var body: some View {
    switch layer {
    case .backdrop:
      LiquidGlassVibrancyBackdrop(material: .hudWindow, blending: .behindWindow)
        .clipShape(shape)
    case .control:
      // A live AppKit blur per control would thrash the view hierarchy on every pointer move,
      // so nested controls approximate refraction with a diagonal sheen instead.
      shape.fill(
        LinearGradient(
          colors: [
            Color.white.opacity(LiquidGlassTokens.fallbackControlSheenTop),
            Color.white.opacity(LiquidGlassTokens.fallbackControlSheenBottom),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
    }
  }
}

// MARK: - Legacy Composite Surface

/// The macOS 13–15 composite, used as a `.background`. On macOS 26+ the native `.glassEffect`
/// must be applied *to the content* rather than to a background view — see
/// `View.liquidGlassSurface(...)` below.
struct LiquidGlassSurface<S: InsettableShape>: View {
  var shape: S
  var substrate: CGFloat = LiquidGlassTokens.baseDarkness
  var dim: CGFloat = 0
  var tint: CGFloat = 0
  var highlight: LiquidGlassHighlight = .specular
  var layer: LiquidGlassLayer = .control
  var withRimLighting: Bool = false

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack {
      if resolvedSubstrate > 0 {
        shape.fill(LiquidGlassTokens.substrateFill.opacity(resolvedSubstrate))
      }

      LiquidGlassRefraction(shape: shape, layer: layer)
        .clipShape(shape)

      if withRimLighting {
        LiquidGlassCaustics(shape: shape, isHovered: false, isEnabled: true)
      }

      if dim > 0 {
        shape.fill(LiquidGlassTokens.substrateFill.opacity(dim))
      }

      if resolvedTint > 0 {
        shape.fill(LiquidGlassTokens.veilFill.opacity(resolvedTint))
      }

      if withRimLighting {
        // `LiquidGlassRimBorder` already draws the specular diagonal hairline, so drawing
        // `highlight` as well stacks two identical strokes into a chalky white outline.
        LiquidGlassRimBorder(shape: shape, isHovered: false, isEnabled: true)
      } else if let stops = highlight.stops {
        shape.strokeBorder(
          LinearGradient(
            colors: [stops.top, stops.bottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: LiquidGlassTokens.specularLineWidth
        )
      }
    }
  }

  private var isDark: Bool { colorScheme == .dark }

  private var resolvedSubstrate: CGFloat {
    let base = layer == .backdrop ? LiquidGlassTokens.backdropSubstrate(substrate) : substrate
    return isDark ? base : base * 0.55
  }

  private var resolvedTint: Double {
    LiquidGlassTokens.veilOpacity(tint, isDark: isDark)
  }
}

// MARK: - View Modifiers

extension View {
  /// Puts a Liquid Glass surface behind this view — native `.glassEffect` on macOS 26+, the
  /// 4-layer composite as a `.background` on macOS 13–15.
  ///
  /// `.glassEffect` has to wrap the content it sits behind. Applying it to a `Color.clear` inside
  /// a `.background` instead makes the merged glass layer composite *over* the content, which
  /// erases the label on a tinted surface.
  ///
  /// Pass `isVisible: false` to keep the surface in the hierarchy but render nothing — that maps
  /// to `Glass.identity` on native, which avoids the conditional insert/remove (and its implicit
  /// `.opacity` transition) that would otherwise sever backdrop sampling.
  @ViewBuilder
  func liquidGlassSurface<S: InsettableShape>(
    shape: S,
    isVisible: Bool = true,
    substrate: CGFloat = LiquidGlassTokens.baseDarkness,
    dim: CGFloat = 0,
    tint: CGFloat = 0,
    highlight: LiquidGlassHighlight = .specular,
    layer: LiquidGlassLayer = .control,
    withRimLighting: Bool = false,
    isInteractive: Bool = false,
    glassTint: Color? = nil
  ) -> some View {
    if #available(macOS 26.0, *), !LiquidGlassCapabilities.forcesLegacyGlass {
      glassEffect(
        LiquidGlassNativeStyle.glass(
          isVisible: isVisible,
          isInteractive: isInteractive,
          tint: glassTint
        ),
        in: shape
      )
    } else if isVisible {
      background {
        LiquidGlassSurface(
          shape: shape,
          substrate: substrate,
          dim: dim,
          tint: tint,
          highlight: highlight,
          layer: layer,
          withRimLighting: withRimLighting
        )
      }
    } else {
      self
    }
  }

  /// Legacy alias kept for call sites that also want the content clipped to `shape`.
  func liquidGlass<S: InsettableShape>(
    shape: S,
    substrate: CGFloat = LiquidGlassTokens.baseDarkness,
    dim: CGFloat = 0,
    tint: CGFloat = 0,
    highlight: LiquidGlassHighlight = .specular,
    layer: LiquidGlassLayer = .control,
    withRimLighting: Bool = false,
    isInteractive: Bool = false,
    glassTint: Color? = nil
  ) -> some View {
    liquidGlassSurface(
      shape: shape,
      substrate: substrate,
      dim: dim,
      tint: tint,
      highlight: highlight,
      layer: layer,
      withRimLighting: withRimLighting,
      isInteractive: isInteractive,
      glassTint: glassTint
    )
    .contentShape(shape)
  }
}

// MARK: - Native Glass Resolution

enum LiquidGlassNativeStyle {
  @available(macOS 26.0, *)
  static func glass(isVisible: Bool, isInteractive: Bool, tint: Color?) -> Glass {
    guard isVisible else { return .identity }
    var glass = Glass.regular
    if let tint {
      glass = glass.tint(tint)
    }
    return isInteractive ? glass.interactive() : glass
  }
}
