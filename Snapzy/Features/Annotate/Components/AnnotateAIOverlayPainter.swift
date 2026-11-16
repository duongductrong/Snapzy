//
//  AnnotateAIOverlayPainter.swift
//  Snapzy
//
//  Drawing shared by the AI overlays on the Annotate canvas (Auto Translate and the
//  AI prompt), so both "read" and "work" with the same light: a slowly turning
//  multi-hue rim (`TranslationCardMotion.rimHues`) and a soft diagonal sweep.
//

import SwiftUI

enum AnnotateAIOverlayPainter {
  /// Faint multi-hue light running around `shape`, like the translation card's rim.
  static func drawRim(
    in context: inout GraphicsContext,
    shape: Path,
    rect: CGRect,
    now: Date,
    strength: Double,
    reduceMotion: Bool,
    isDark: Bool,
    lineWidth: CGFloat = 1.2
  ) {
    guard strength > 0.01 else { return }
    let angle: Angle
    if reduceMotion {
      angle = .zero
    } else {
      let turn = now.timeIntervalSinceReferenceDate
        .truncatingRemainder(dividingBy: TranslationCardMotion.rimTurnDuration) / TranslationCardMotion.rimTurnDuration
      angle = .degrees(turn * 360)
    }
    let shading = GraphicsContext.Shading.conicGradient(
      Gradient(colors: TranslationCardMotion.rimHues),
      center: CGPoint(x: rect.midX, y: rect.midY),
      angle: angle
    )
    var glow = context
    glow.opacity = strength * (isDark ? 0.55 : 0.45)
    glow.addFilter(.blur(radius: 4))
    glow.stroke(shape, with: shading, lineWidth: lineWidth * 2.5)

    var line = context
    line.opacity = strength * (isDark ? 0.85 : 0.75)
    line.stroke(shape, with: shading, lineWidth: lineWidth)
  }

  /// Apple Intelligence edge hues (Siri-style glow); first == last so the turn has no seam.
  static let edgeHues: [Color] = [
    Color(red: 0.74, green: 0.51, blue: 0.95),
    Color(red: 0.96, green: 0.73, blue: 0.92),
    Color(red: 0.55, green: 0.62, blue: 1.00),
    Color(red: 0.67, green: 0.43, blue: 0.93),
    Color(red: 1.00, green: 0.40, blue: 0.47),
    Color(red: 1.00, green: 0.73, blue: 0.44),
    Color(red: 0.78, green: 0.53, blue: 1.00),
    Color(red: 0.74, green: 0.51, blue: 0.95),
  ]

  /// Rounded outline of the image as the canvas draws it (overlay space, top-left origin).
  static func imageShape(size: CGSize, cornerRadius: CGFloat) -> Path {
    let rect = CGRect(origin: .zero, size: size)
    let radius = max(0, min(cornerRadius, min(size.width, size.height) / 2))
    return Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
  }

  /// Apple Intelligence style glow running along the inside of the image edge while the AI
  /// scans. Purely painted on top: callers pass the overlay's own bounds, so the image and
  /// its layout are never touched. Strokes sit on the edge and are clipped to `shape`, so
  /// the glow only falls inward and never spills past rounded corners.
  static func drawEdgeGlow(
    in context: inout GraphicsContext,
    shape: Path,
    rect: CGRect,
    now: Date,
    strength: Double,
    reduceMotion: Bool,
    isDark: Bool
  ) {
    guard strength > 0.01, rect.width > 2, rect.height > 2 else { return }
    let time = now.timeIntervalSinceReferenceDate
    let angle: Angle
    let breathe: Double
    if reduceMotion {
      angle = .zero
      breathe = 1
    } else {
      let turn = time.truncatingRemainder(dividingBy: TranslationCardMotion.rimTurnDuration * 0.8)
        / (TranslationCardMotion.rimTurnDuration * 0.8)
      angle = .degrees(turn * 360)
      breathe = 0.86 + 0.14 * sin(time * 2.2)
    }
    let shading = GraphicsContext.Shading.conicGradient(
      Gradient(colors: edgeHues),
      center: CGPoint(x: rect.midX, y: rect.midY),
      angle: angle
    )
    // Size the glow to the on-screen image: visible on small images, not a frame on big ones.
    let base = max(4, min(min(rect.width, rect.height) * 0.025, 14))
    let boost = isDark ? 1.0 : 0.85

    var layer = context
    layer.clip(to: shape)

    // Wide, soft bloom → mid glow → crisp rim (stroke is centered on the edge, so half shows).
    let passes: [(width: CGFloat, blur: CGFloat, opacity: Double)] = [
      (base * 4.0, base * 2.2, 0.55),
      (base * 2.0, base * 0.9, 0.75),
      (base * 0.7, 0, 0.95),
    ]
    for pass in passes {
      var stroke = layer
      stroke.opacity = strength * pass.opacity * boost * (pass.blur > 0 ? breathe : 1)
      if pass.blur > 0 { stroke.addFilter(.blur(radius: pass.blur)) }
      stroke.stroke(shape, with: shading, lineWidth: pass.width)
    }
  }

  /// A soft diagonal band moving leading → trailing, as in the card's reading sweep.
  static func drawSweep(
    in context: inout GraphicsContext,
    rect: CGRect,
    clip: Path? = nil,
    now: Date,
    phaseOffset: Double,
    strength: Double
  ) {
    guard strength > 0.01 else { return }
    let cycle = TranslationCardMotion.sweepDuration + TranslationCardMotion.sweepRest
    let t = (now.timeIntervalSinceReferenceDate + phaseOffset).truncatingRemainder(dividingBy: cycle)
    let raw = min(t / TranslationCardMotion.sweepDuration, 1)
    guard raw < 1 else { return }
    let eased = raw < 0.5 ? 4 * raw * raw * raw : 1 - pow(-2 * raw + 2, 3) / 2
    let width = 0.38
    let center = -width + eased * (1 + 2 * width)

    var layer = context
    if let clip { layer.clip(to: clip) }
    layer.blendMode = .plusLighter
    let gradient = Gradient(stops: [
      .init(color: .clear, location: max(0, min(1, center - width))),
      .init(color: .white.opacity(strength), location: max(0, min(1, center))),
      .init(color: .clear, location: max(0, min(1, center + width))),
    ])
    layer.fill(
      Path(rect),
      with: .linearGradient(
        gradient,
        startPoint: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.2),
        endPoint: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.8)
      )
    )
  }
}
