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
