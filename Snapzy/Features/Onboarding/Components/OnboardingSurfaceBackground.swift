//
//  OnboardingSurfaceBackground.swift
//  Snapzy
//
//  Opaque adaptive background for onboarding — subtle gradient + noise texture
//

import SwiftUI

/// Premium opaque background that replaces the old transparent hudWindow material.
/// Renders a solid adaptive base, a soft radial gradient accent, and a subtle noise overlay.
struct OnboardingSurfaceBackground: View {

  var body: some View {
    ZStack {
      // 1. Solid adaptive base
      Color(nsColor: NSColor(
        name: nil,
        dynamicProvider: { appearance in
          appearance.bestMatch(from: [.darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 28/255, green: 28/255, blue: 30/255, alpha: 1)   // #1C1C1E
            : NSColor(srgbRed: 242/255, green: 242/255, blue: 247/255, alpha: 1) // #F2F2F7
        }
      ))

      // 2. Subtle radial gradient accent — adds depth without revealing wallpaper
      RadialGradient(
        colors: [
          Color(nsColor: NSColor(
            name: nil,
            dynamicProvider: { appearance in
              appearance.bestMatch(from: [.darkAqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.04)
                : NSColor.black.withAlphaComponent(0.02)
            }
          )),
          Color.clear,
        ],
        center: .top,
        startRadius: 0,
        endRadius: 500
      )

      // 3. Noise texture overlay — fine grain for premium feel
      NoiseOverlay()
    }
  }
}

// MARK: - Noise Overlay

/// Renders a subtle static noise pattern using Canvas for texture.
private struct NoiseOverlay: View {
  var body: some View {
    Canvas { context, size in
      let step: CGFloat = 3
      var x: CGFloat = 0
      // Simple deterministic noise pattern using a seeded approach
      var seed: UInt64 = 42
      while x < size.width {
        var y: CGFloat = 0
        while y < size.height {
          // Simple xorshift-based pseudo-random
          seed ^= (seed << 13)
          seed ^= (seed >> 7)
          seed ^= (seed << 17)
          let value = Double(seed % 256) / 255.0
          let alpha = value * 0.03 // Very subtle — 0–3% opacity per pixel
          context.fill(
            Path(CGRect(x: x, y: y, width: step, height: step)),
            with: .color(.white.opacity(alpha))
          )
          y += step
        }
        x += step
      }
    }
    .blendMode(.overlay)
    .allowsHitTesting(false)
  }
}

#Preview("Dark") {
  OnboardingSurfaceBackground()
    .frame(width: 800, height: 600)
    .environment(\.colorScheme, .dark)
}

#Preview("Light") {
  OnboardingSurfaceBackground()
    .frame(width: 800, height: 600)
    .environment(\.colorScheme, .light)
}
