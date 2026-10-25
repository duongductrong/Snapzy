//
//  PaintedSkyBackdrop.swift
//  Snapzy
//
//  Reusable brand backdrop: a painterly cobalt sky with mottled brush patches
//  and soft white clouds banking along the bottom edge.
//

import SwiftUI

/// Decorative desktop-style backdrop for previews and hero surfaces.
///
/// The blurred composition is rasterized once per process and shared by every
/// instance, so on-screen cost is a single scaled bitmap: no per-frame blur
/// passes, no offscreen layers, and the same ~2.9 MB texture however many
/// backdrops are visible. Content is unit-space, so the image fills any frame
/// and crops from the center.
struct PaintedSkyBackdrop: View {
  var body: some View {
    // Size comes from the proposed frame only: an aspect-fill image reports an
    // ideal size larger than its container, so it is drawn as an overlay and
    // never participates in layout.
    Color.clear
      .overlay {
        if let image = Self.renderedImage {
          Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.medium)
            .aspectRatio(contentMode: .fill)
        } else {
          PaintedSkyComposition()
        }
      }
      .clipped()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  /// Reference raster size. 2:1 matches the typical wide preview strip; the
  /// content is soft enough that upscaling to Retina is visually lossless.
  private static let renderSize = CGSize(width: 1200, height: 600)

  @MainActor
  private static let renderedImage: CGImage? = {
    let renderer = ImageRenderer(
      content: PaintedSkyComposition()
        .frame(width: renderSize.width, height: renderSize.height)
    )
    renderer.scale = 1
    renderer.isOpaque = true
    return renderer.cgImage
  }()
}

// MARK: - Composition

/// The live vector composition. Rendered once into `PaintedSkyBackdrop`'s
/// shared bitmap; only drawn directly if rasterization fails.
private struct PaintedSkyComposition: View {
  /// (x, y, width, height, tone) in unit space; tone < 0 darkens, > 0 lightens.
  private static let patches: [(CGFloat, CGFloat, CGFloat, CGFloat, Double)] = [
    (0.12, 0.18, 0.30, 0.22, 0.18), (0.48, 0.10, 0.26, 0.18, -0.22),
    (0.78, 0.30, 0.34, 0.24, 0.14), (0.30, 0.45, 0.28, 0.20, -0.18),
    (0.62, 0.55, 0.30, 0.22, 0.16), (0.90, 0.08, 0.22, 0.16, 0.20),
    (0.05, 0.60, 0.24, 0.20, -0.14), (0.45, 0.30, 0.18, 0.14, 0.22),
  ]

  /// Cloud puffs (x, y, width, height, opacity) in unit space.
  private static let clouds: [(CGFloat, CGFloat, CGFloat, CGFloat, Double)] = [
    (0.10, 0.90, 0.34, 0.26, 0.95), (0.28, 0.82, 0.24, 0.24, 0.9),
    (0.46, 0.95, 0.30, 0.18, 0.85), (0.70, 0.92, 0.26, 0.20, 0.8),
    (0.88, 0.80, 0.30, 0.28, 0.95), (0.98, 0.70, 0.18, 0.22, 0.85),
    (0.20, 0.72, 0.14, 0.12, 0.6), (0.80, 0.66, 0.12, 0.10, 0.55),
  ]

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      // Blur radii were tuned at a ~600pt-wide preview; keep them proportional.
      let blurScale = size.width / 600

      ZStack {
        LinearGradient(
          colors: [
            Color(red: 0.10, green: 0.32, blue: 0.95),
            Color(red: 0.08, green: 0.26, blue: 0.86),
            Color(red: 0.16, green: 0.40, blue: 0.95),
          ],
          startPoint: .top,
          endPoint: .bottom
        )

        ForEach(Array(Self.patches.enumerated()), id: \.offset) { _, patch in
          Ellipse()
            .fill(patch.4 < 0
              ? Color(red: 0.03, green: 0.14, blue: 0.62).opacity(-patch.4 * 3)
              : Color(red: 0.36, green: 0.58, blue: 1.0).opacity(patch.4 * 3))
            .frame(width: size.width * patch.2, height: size.height * patch.3)
            .rotationEffect(.degrees(-18))
            .position(x: size.width * patch.0, y: size.height * patch.1)
            .blur(radius: 14 * blurScale)
        }

        ForEach(Array(Self.clouds.enumerated()), id: \.offset) { _, cloud in
          Ellipse()
            .fill(
              LinearGradient(
                colors: [Color.white, Color(red: 0.80, green: 0.86, blue: 1.0)],
                startPoint: .top,
                endPoint: .bottom
              )
            )
            .frame(width: size.width * cloud.2, height: size.height * cloud.3)
            .position(x: size.width * cloud.0, y: size.height * cloud.1)
            .opacity(cloud.4)
            .blur(radius: 9 * blurScale)
        }
      }
      .frame(width: size.width, height: size.height)
      .clipped()
    }
  }
}

#Preview {
  PaintedSkyBackdrop()
    .frame(width: 600, height: 300)
}
