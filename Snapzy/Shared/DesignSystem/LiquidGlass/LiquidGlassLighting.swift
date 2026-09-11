//
//  LiquidGlassLighting.swift
//  Snapzy
//
//  Optical edge rim lighting, caustic flares, and lens gradients for Liquid Glass surfaces.
//

import SwiftUI

// MARK: - Rim Lighting Stroke

/// Renders a two-pass optical perimeter: specular downlight plus horizontal convex rim reflections.
struct LiquidGlassRimBorder<S: InsettableShape>: View {
  var shape: S
  var isHovered: Bool
  var isEnabled: Bool = true
  var emphasis: LiquidGlassActionEmphasis = .secondary

  var body: some View {
    ZStack {
      // 1. Specular top-to-bottom hairline
      shape.strokeBorder(specularGradient, lineWidth: LiquidGlassTokens.specularLineWidth)

      // 2. Convex leading & trailing rim lighting
      if isEnabled {
        shape.strokeBorder(rimGradient, lineWidth: 0.75)
      }
    }
  }

  private var specularGradient: LinearGradient {
    guard isEnabled else {
      return LinearGradient(colors: [.white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
    }
    let (top, bottom): (Double, Double) = switch emphasis {
    case .primary: isHovered ? (0.36, 0.14) : (0.24, 0.08)
    case .secondary: isHovered ? (0.28, 0.08) : (0.14, 0.04)
    case .destructive: isHovered ? (0.40, 0.14) : (0.18, 0.04)
    case .contextPill: isHovered ? (0.28, 0.10) : (0.14, 0.04)
    }
    return LinearGradient(
      colors: [.white.opacity(top), .white.opacity(bottom)],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private var rimGradient: LinearGradient {
    let leadOpacity = isHovered ? LiquidGlassTokens.rimLeadingHover : LiquidGlassTokens.rimLeadingResting
    let trailOpacity = isHovered ? LiquidGlassTokens.rimTrailingHover : LiquidGlassTokens.rimTrailingResting

    return LinearGradient(
      stops: [
        .init(color: .white.opacity(leadOpacity), location: 0.0),
        .init(color: .white.opacity(leadOpacity * 0.45), location: 0.06),
        .init(color: .clear, location: 0.20),
        .init(color: .clear, location: 0.80),
        .init(color: .white.opacity(trailOpacity * 0.45), location: 0.94),
        .init(color: .white.opacity(trailOpacity), location: 1.0),
      ],
      startPoint: .leading,
      endPoint: .trailing
    )
  }
}

// MARK: - Caustic Flares & Lens Sheen

/// Internal lens refraction and caustics: top lip reflection, bottom bounce, and corner radial blooms.
struct LiquidGlassCaustics<S: Shape>: View {
  var shape: S
  var isHovered: Bool
  var isEnabled: Bool = true

  var body: some View {
    if isEnabled {
      ZStack {
        // Vertical lens thickness
        shape.fill(
          LinearGradient(
            stops: [
              .init(color: .white.opacity(isHovered ? 0.12 : 0.06), location: 0.0),
              .init(color: .clear, location: 0.35),
              .init(color: .clear, location: 0.70),
              .init(color: .white.opacity(isHovered ? 0.06 : 0.02), location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
          )
        )

        // Leading radial glare bloom
        shape.fill(
          RadialGradient(
            colors: [
              Color.white.opacity(isHovered ? LiquidGlassTokens.glareLeadingHover : LiquidGlassTokens.glareLeadingResting),
              Color.white.opacity(0.0),
            ],
            center: .leading,
            startRadius: 0,
            endRadius: 30
          )
        )

        // Trailing radial glare bloom
        shape.fill(
          RadialGradient(
            colors: [
              Color.white.opacity(isHovered ? LiquidGlassTokens.glareTrailingHover : LiquidGlassTokens.glareTrailingResting),
              Color.white.opacity(0.0),
            ],
            center: .trailing,
            startRadius: 0,
            endRadius: 26
          )
        )
      }
    }
  }
}
