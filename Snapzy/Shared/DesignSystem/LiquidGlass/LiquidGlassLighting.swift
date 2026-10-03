//
//  LiquidGlassLighting.swift
//  Snapzy
//
//  Optical edge rim lighting, caustic flares, and lens gradients for Liquid Glass surfaces.
//

import SwiftUI

// MARK: - Rim Lighting Stroke

/// Renders a clean, crisp 0.5pt specular perimeter hairline for macOS controls.
struct LiquidGlassRimBorder<S: InsettableShape>: View {
  var shape: S
  var isHovered: Bool
  var isEnabled: Bool = true
  var emphasis: LiquidGlassActionEmphasis = .secondary

  var body: some View {
    // Clean 0.5pt specular perimeter hairline for tactile crispness
    shape.strokeBorder(specularGradient, lineWidth: LiquidGlassTokens.specularLineWidth)
  }

  private var specularGradient: LinearGradient {
    guard isEnabled else {
      return LinearGradient(colors: [.white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
    }
    let (top, bottom): (Double, Double) = switch emphasis {
    case .primary: isHovered ? (0.32, 0.12) : (0.22, 0.06)
    case .secondary: isHovered ? (0.24, 0.06) : (0.12, 0.03)
    case .destructive: isHovered ? (0.34, 0.12) : (0.18, 0.04)
    case .contextPill: isHovered ? (0.24, 0.08) : (0.12, 0.03)
    }
    return LinearGradient(
      colors: [.white.opacity(top), .white.opacity(bottom)],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }
}

// MARK: - Caustic Flares & Lens Sheen

/// Placeholder kept for API compatibility; omitted in rendering to prevent artificial glare bloat.
struct LiquidGlassCaustics<S: Shape>: View {
  var shape: S
  var isHovered: Bool
  var isEnabled: Bool = true

  var body: some View {
    EmptyView()
  }
}
