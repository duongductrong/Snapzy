//
//  AnnotateSpotlightCompositor.swift
//  Snapzy
//
//  Composits spotlight overlay using CGContext and even-odd fill.
//

import CoreGraphics
import AppKit

struct SpotlightRegion {
  let rect: CGRect
  let cornerRadius: CGFloat
  let opacity: CGFloat  // darkness strength, clamped 0.1...0.9
  let strokeColor: CGColor?
  let strokeWidth: CGFloat
  let lineStyle: LineDashStyle

  init(
    rect: CGRect,
    cornerRadius: CGFloat,
    opacity: CGFloat,
    strokeColor: CGColor? = nil,
    strokeWidth: CGFloat = 0,
    lineStyle: LineDashStyle = .solid
  ) {
    self.rect = rect
    self.cornerRadius = cornerRadius
    self.opacity = opacity
    self.strokeColor = strokeColor
    self.strokeWidth = strokeWidth
    self.lineStyle = lineStyle
  }
}

nonisolated enum SpotlightCompositor {
  /// Darken canvasRect except the union of spotlight regions. Opacity is sourced from regions themselves,
  /// so per-item slider changes reflect immediately without a global state sync cycle.
  static func drawOverlay(
    regions: [SpotlightRegion],      // committed spotlight items (canvas coord space)
    previewRegion: SpotlightRegion?, // in-progress drag rect; nil for export
    canvasRect: CGRect,              // effective/cropped visible bounds, same coord space
    in context: CGContext
  ) {
    let holes = regions + (previewRegion.map { [$0] } ?? [])
    guard !holes.isEmpty else { return }

    // All regions share a single global opacity (per design). Source from first committed region;
    // fall back to preview region when no committed regions exist yet (first drag).
    let opacity = (regions.first ?? previewRegion)?.opacity ?? 0.5

    context.saveGState()
    if opacity > 0 {
      context.beginTransparencyLayer(auxiliaryInfo: nil)

      context.setFillColor(NSColor.black.withAlphaComponent(opacity).cgColor)
      context.fill(canvasRect)

      context.setBlendMode(.clear)
      for hole in holes {
        context.addPath(path(for: hole))
        context.fillPath()
      }

      context.endTransparencyLayer()
    }

    for hole in holes {
      drawBorder(for: hole, in: context)
    }

    context.restoreGState()
  }

  private static func path(for region: SpotlightRegion) -> CGPath {
    outlinePath(in: region.rect, cornerRadius: region.cornerRadius)
  }

  /// Corner radius the spotlight hole actually uses: never negative and never
  /// more than half the shorter side.
  static func clampedCornerRadius(_ cornerRadius: CGFloat, in rect: CGRect) -> CGFloat {
    let rect = rect.standardized
    return min(max(cornerRadius, 0), min(rect.width, rect.height) / 2)
  }

  /// Outline of a spotlight hole and its border. Shared with hit testing so a
  /// click lands on the same rounded corners the overlay draws.
  static func outlinePath(in rect: CGRect, cornerRadius: CGFloat) -> CGPath {
    let rect = rect.standardized
    let radius = clampedCornerRadius(cornerRadius, in: rect)
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
  }

  private static func drawBorder(for region: SpotlightRegion, in context: CGContext) {
    guard let strokeColor = region.strokeColor,
          strokeColor.alpha > 0.001,
          region.strokeWidth > 0 else { return }
    let rect = region.rect.standardized
    guard !rect.isEmpty else { return }

    context.saveGState()
    context.setStrokeColor(strokeColor)
    context.setLineWidth(region.strokeWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineDash(phase: 0, lengths: region.lineStyle.dashLengths(for: region.strokeWidth))
    context.addPath(path(for: region))
    context.strokePath()
    context.restoreGState()
  }
}
