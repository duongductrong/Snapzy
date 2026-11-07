//
//  ScreenRulerRenderer.swift
//  Snapzy
//
//  Draws Screen Ruler measurements. The overlay and the saved image both go through
//  `draw(_:in:)`, so the file shows exactly what was on screen.
//

import AppKit

/// Everything one display's overlay shows. Pixel values are snapshot pixels (top-left origin);
/// `scaleX` / `scaleY` are snapshot pixels per point on each axis (they differ slightly on
/// some scaled display modes, so one scalar would drift away from the stretched backdrop).
struct ScreenRulerDrawing {
  var size: CGSize
  var scaleX: CGFloat
  var scaleY: CGFloat
  var unit: ScreenRulerUnit
  var pins: [ScreenRulerMeasurement] = []
  var live: ScreenRulerMeasurement?
  /// The box being dragged, before it snaps.
  var dragBox: ScreenRulerPixelRect?
  /// Where the reticle goes; nil hides it (and in saved images).
  var pointer: ColorPickerPixel?
  var hint: String?
}

@MainActor
enum ScreenRulerRenderer {
  static let lineColor = NSColor(srgbRed: 1, green: 0.17, blue: 0.42, alpha: 1)
  private static let pinAlpha: CGFloat = 0.75
  private static let tickLength: CGFloat = 7
  private static let labelOffset: CGFloat = 14
  private static let margin: CGFloat = 4

  /// Draws into `context`, whose user space is points with a top-left origin.
  static func draw(_ drawing: ScreenRulerDrawing, in context: CGContext) {
    let graphics = NSGraphicsContext(cgContext: context, flipped: true)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    defer { NSGraphicsContext.restoreGraphicsState() }

    for pin in drawing.pins {
      draw(pin, drawing: drawing, alpha: pinAlpha, in: context)
    }
    if let dragBox = drawing.dragBox {
      draw(.box(dragBox), drawing: drawing, alpha: 1, dashed: true, in: context)
    } else if let live = drawing.live {
      draw(live, drawing: drawing, alpha: 1, in: context)
    }
    if let pointer = drawing.pointer {
      drawReticle(at: pointer, scaleX: drawing.scaleX, scaleY: drawing.scaleY, in: context)
    }
    if let hint = drawing.hint {
      drawHint(hint, size: drawing.size)
    }
  }

  /// `image` with `drawing` on top, at the image's own pixel size.
  static func renderImage(_ image: CGImage, drawing: ScreenRulerDrawing) -> CGImage? {
    let width = image.width
    let height = image.height
    // Some display profiles cannot back a bitmap context; sRGB always can.
    let colorSpace = image.colorSpace.flatMap { $0.supportsOutput ? $0 : nil }
      ?? CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
          ) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: drawing.scaleX, y: -drawing.scaleY)
    draw(drawing, in: context)
    return context.makeImage()
  }

  // MARK: - Measurements

  private static func draw(
    _ measurement: ScreenRulerMeasurement,
    drawing: ScreenRulerDrawing,
    alpha: CGFloat,
    dashed: Bool = false,
    in context: CGContext
  ) {
    let scaleX = drawing.scaleX
    let scaleY = drawing.scaleY
    context.saveGState()
    context.setStrokeColor(lineColor.withAlphaComponent(alpha).cgColor)
    context.setLineWidth(1)
    if dashed {
      context.setLineDash(phase: 0, lengths: [4, 3])
    }

    let labelAnchor: CGPoint
    let labelBelow: Bool
    switch measurement {
    case .span(let span):
      let centerX = (CGFloat(span.origin.x) + 0.5) / scaleX
      let centerY = (CGFloat(span.origin.y) + 0.5) / scaleY
      if span.axis != .vertical {
        let start = CGFloat(span.left) / scaleX
        let end = CGFloat(span.right + 1) / scaleX
        strokeLine(from: CGPoint(x: start, y: centerY), to: CGPoint(x: end, y: centerY), in: context)
        strokeLine(from: CGPoint(x: start, y: centerY - tickLength / 2), to: CGPoint(x: start, y: centerY + tickLength / 2), in: context)
        strokeLine(from: CGPoint(x: end, y: centerY - tickLength / 2), to: CGPoint(x: end, y: centerY + tickLength / 2), in: context)
      }
      if span.axis != .horizontal {
        let start = CGFloat(span.top) / scaleY
        let end = CGFloat(span.bottom + 1) / scaleY
        strokeLine(from: CGPoint(x: centerX, y: start), to: CGPoint(x: centerX, y: end), in: context)
        strokeLine(from: CGPoint(x: centerX - tickLength / 2, y: start), to: CGPoint(x: centerX + tickLength / 2, y: start), in: context)
        strokeLine(from: CGPoint(x: centerX - tickLength / 2, y: end), to: CGPoint(x: centerX + tickLength / 2, y: end), in: context)
      }
      labelAnchor = CGPoint(x: centerX + labelOffset, y: centerY + labelOffset)
      labelBelow = true
    case .box(let rect):
      let box = CGRect(
        x: CGFloat(rect.minX) / scaleX,
        y: CGFloat(rect.minY) / scaleY,
        width: CGFloat(rect.width) / scaleX,
        height: CGFloat(rect.height) / scaleY
      )
      context.setFillColor(lineColor.withAlphaComponent(0.08 * alpha).cgColor)
      context.fill(box)
      context.stroke(box.insetBy(dx: 0.5, dy: 0.5))
      labelAnchor = CGPoint(x: box.midX, y: box.maxY + 6)
      labelBelow = false
    }
    context.restoreGState()

    let text = ScreenRulerFormatter.label(for: measurement, scaleX: scaleX, scaleY: scaleY, unit: drawing.unit)
    drawLabel(text, anchor: labelAnchor, centered: !labelBelow, alpha: alpha, size: drawing.size)
  }

  private static func strokeLine(from a: CGPoint, to b: CGPoint, in context: CGContext) {
    context.move(to: a)
    context.addLine(to: b)
    context.strokePath()
  }

  private static func drawReticle(at pixel: ColorPickerPixel, scaleX: CGFloat, scaleY: CGFloat, in context: CGContext) {
    let center = CGPoint(x: (CGFloat(pixel.x) + 0.5) / scaleX, y: (CGFloat(pixel.y) + 0.5) / scaleY)
    let side = max(1 / min(scaleX, scaleY), 1)
    let cell = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    let ring = cell.insetBy(dx: -3, dy: -3)
    context.saveGState()
    context.setLineWidth(1)
    context.setStrokeColor(NSColor.black.withAlphaComponent(0.7).cgColor)
    context.strokeEllipse(in: ring.insetBy(dx: -1, dy: -1))
    context.setStrokeColor(NSColor.white.cgColor)
    context.strokeEllipse(in: ring)
    context.restoreGState()
  }

  // MARK: - Labels

  private static var labelAttributes: [NSAttributedString.Key: Any] {
    [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
      .foregroundColor: NSColor.white,
    ]
  }

  /// A dark capsule with `text`. `anchor` is its top-left corner, or its top-center when
  /// `centered`; it is kept inside `size`.
  private static func drawLabel(_ text: String, anchor: CGPoint, centered: Bool, alpha: CGFloat, size: CGSize) {
    let string = NSAttributedString(string: text, attributes: labelAttributes)
    let textSize = string.size()
    let capsule = CGSize(width: ceil(textSize.width) + 12, height: ceil(textSize.height) + 6)
    var origin = CGPoint(x: centered ? anchor.x - capsule.width / 2 : anchor.x, y: anchor.y)
    if origin.x + capsule.width > size.width - margin {
      origin.x = centered ? size.width - margin - capsule.width : anchor.x - 2 * labelOffset - capsule.width
    }
    if origin.y + capsule.height > size.height - margin {
      origin.y = centered ? anchor.y - capsule.height - 12 : anchor.y - 2 * labelOffset - capsule.height
    }
    origin.x = max(margin, origin.x)
    origin.y = max(margin, origin.y)
    let rect = CGRect(origin: origin, size: capsule)
    NSColor.black.withAlphaComponent(0.78 * alpha).setFill()
    NSBezierPath(roundedRect: rect, xRadius: capsule.height / 2, yRadius: capsule.height / 2).fill()
    string.draw(at: CGPoint(x: rect.minX + 6, y: rect.minY + 3))
  }

  private static func drawHint(_ hint: String, size: CGSize) {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12, weight: .medium),
      .foregroundColor: NSColor.white,
    ]
    let string = NSAttributedString(string: hint, attributes: attributes)
    let textSize = string.size()
    let capsule = CGSize(width: ceil(textSize.width) + 24, height: ceil(textSize.height) + 12)
    let rect = CGRect(
      x: (size.width - capsule.width) / 2,
      y: size.height - capsule.height - 28,
      width: capsule.width,
      height: capsule.height
    )
    NSColor.black.withAlphaComponent(0.7).setFill()
    NSBezierPath(roundedRect: rect, xRadius: capsule.height / 2, yRadius: capsule.height / 2).fill()
    string.draw(at: CGPoint(x: rect.minX + 12, y: rect.minY + 6))
  }
}
