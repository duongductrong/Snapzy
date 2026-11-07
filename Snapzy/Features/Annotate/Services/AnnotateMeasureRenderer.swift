//
//  AnnotateMeasureRenderer.swift
//  Snapzy
//
//  Draws Measure annotations: span lines with end ticks or a box outline, plus a label
//  capsule. Used by `AnnotationRenderer`, so the canvas, its live preview and every export
//  draw the same thing. Coordinates are image points with a bottom-left origin.
//

import AppKit
import CoreGraphics

nonisolated enum AnnotateMeasureRenderer {
  static let lineWidth: CGFloat = 1.5
  static let tickLength: CGFloat = 8
  static let labelFontSize: CGFloat = 12
  private static let labelGap: CGFloat = 6
  private static let labelPadding = CGSize(width: 7, height: 3)

  static func draw(_ item: AnnotationItem, color: CGColor, in context: CGContext, dashed: Bool = false) {
    guard case .measurement(let geometry) = item.type else { return }
    let bounds = item.bounds
    context.saveGState()
    context.setStrokeColor(color)
    context.setLineWidth(lineWidth)
    context.setLineCap(.butt)
    if dashed {
      context.setLineDash(phase: 0, lengths: [4, 3])
    }
    switch geometry.kind {
    case .box:
      context.setFillColor(color.copy(alpha: 0.08) ?? color)
      context.fill(bounds)
      context.stroke(bounds)
    case .span:
      for segment in geometry.segments(in: bounds) {
        strokeLine(segment.start, segment.end, in: context)
        let horizontal = segment.start.y == segment.end.y
        for end in [segment.start, segment.end] {
          let half = tickLength / 2
          if horizontal {
            strokeLine(CGPoint(x: end.x, y: end.y - half), CGPoint(x: end.x, y: end.y + half), in: context)
          } else {
            strokeLine(CGPoint(x: end.x - half, y: end.y), CGPoint(x: end.x + half, y: end.y), in: context)
          }
        }
      }
    }
    context.restoreGState()
    drawLabel(for: item, in: context)
  }

  /// Where the label capsule goes: below-right of a span's crossing point, centered under a
  /// box. Image space starts at 0, so a label that would drop below the image (or left of it)
  /// goes above / right of the measurement instead and stays visible in a bare export.
  static func labelRect(for item: AnnotationItem) -> CGRect? {
    guard case .measurement(let geometry) = item.type else { return nil }
    let size = capsuleSize(for: geometry.label(for: item.bounds))
    var rect: CGRect
    switch geometry.kind {
    case .span:
      rect = CGRect(
        x: geometry.origin.x + labelGap,
        y: geometry.origin.y - labelGap - size.height,
        width: size.width,
        height: size.height
      )
      if rect.minY < 0 { rect.origin.y = geometry.origin.y + labelGap }
    case .box:
      rect = CGRect(
        x: item.bounds.midX - size.width / 2,
        y: item.bounds.minY - labelGap - size.height,
        width: size.width,
        height: size.height
      )
      if rect.minY < 0 { rect.origin.y = item.bounds.maxY + labelGap }
    }
    rect.origin.x = max(rect.origin.x, 0)
    return rect
  }

  // MARK: - Private

  private static var labelAttributes: [NSAttributedString.Key: Any] {
    [
      .font: NSFont.monospacedDigitSystemFont(ofSize: labelFontSize, weight: .semibold),
      .foregroundColor: NSColor.white,
    ]
  }

  private static func capsuleSize(for text: String) -> CGSize {
    let textSize = (text as NSString).size(withAttributes: labelAttributes)
    return CGSize(
      width: ceil(textSize.width) + labelPadding.width * 2,
      height: ceil(textSize.height) + labelPadding.height * 2
    )
  }

  private static func drawLabel(for item: AnnotationItem, in context: CGContext) {
    guard case .measurement(let geometry) = item.type, let rect = labelRect(for: item) else { return }
    let text = geometry.label(for: item.bounds)
    let radius = rect.height / 2
    context.saveGState()
    context.setFillColor(NSColor.black.withAlphaComponent(0.78).cgColor)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
    context.restoreGState()

    // Text goes through AppKit, like counter and text annotations: the caller has made an
    // NSGraphicsContext over `context` current.
    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    (text as NSString).draw(
      at: CGPoint(x: rect.minX + labelPadding.width, y: rect.minY + labelPadding.height),
      withAttributes: labelAttributes
    )
    NSGraphicsContext.restoreGraphicsState()
  }

  private static func strokeLine(_ a: CGPoint, _ b: CGPoint, in context: CGContext) {
    context.move(to: a)
    context.addLine(to: b)
    context.strokePath()
  }
}
