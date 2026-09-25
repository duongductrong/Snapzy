//
//  LiquidGlassWindowBackdrop.swift
//  Snapzy
//
//  Full-window Liquid Glass backdrop with directional scrim, corner radial bloom, and top specular hairline.
//

import SwiftUI

struct LiquidGlassWindowBackdrop: View {
  var cornerRadius: CGFloat = LiquidGlassTokens.windowRadius
  var bloomRadius: CGFloat = 620

  var body: some View {
    ZStack {
      // 1. AppKit HUD window live blur
      LiquidGlassVibrancyBackdrop(material: .hudWindow, blending: .behindWindow)

      // 2. Directional black scrim (darkest at top for title/header contrast)
      LinearGradient(
        colors: [
          Color.black.opacity(0.46),
          Color.black.opacity(0.38),
          Color.black.opacity(0.44),
        ],
        startPoint: .top,
        endPoint: .bottom
      )

      // 3. Subtle radial bloom in top-leading corner
      RadialGradient(
        colors: [Color.white.opacity(0.06), .clear],
        center: .topLeading,
        startRadius: 0,
        endRadius: bloomRadius
      )
    }
    .overlay(alignment: .top) {
      // 4. Specular hairline edge across top boundary, fading before corners
      LinearGradient(
        colors: [.white.opacity(0.02), .white.opacity(0.34), .white.opacity(0.02)],
        startPoint: .leading,
        endPoint: .trailing
      )
      .frame(height: 1)
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(Color.white.opacity(0.10), lineWidth: LiquidGlassTokens.specularLineWidth)
    )
  }
}
