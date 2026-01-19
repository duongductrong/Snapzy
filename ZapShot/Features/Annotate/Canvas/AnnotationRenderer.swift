//
//  AnnotationRenderer.swift
//  ZapShot
//
//  Handles rendering annotations to CGContext
//

import AppKit
import CoreGraphics
import SwiftUI

/// Renders annotations to a CGContext
struct AnnotationRenderer {
  let context: CGContext
  var editingTextId: UUID?
  var sourceImage: NSImage?
  var blurCacheManager: BlurCacheManager?

  init(
    context: CGContext,
    editingTextId: UUID? = nil,
    sourceImage: NSImage? = nil,
    blurCacheManager: BlurCacheManager? = nil
  ) {
    self.context = context
    self.editingTextId = editingTextId
    self.sourceImage = sourceImage
    self.blurCacheManager = blurCacheManager
  }

  func draw(_ annotation: AnnotationItem) {
    // Skip rendering text that is being edited (overlay handles display)
    if case .text = annotation.type, annotation.id == editingTextId {
      return
    }

    let strokeColor = NSColor(annotation.properties.strokeColor).cgColor
    let fillColor = NSColor(annotation.properties.fillColor).cgColor

    context.setStrokeColor(strokeColor)
    context.setFillColor(fillColor)
    context.setLineWidth(annotation.properties.strokeWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    switch annotation.type {
    case .rectangle:
      context.stroke(annotation.bounds)

    case .oval:
      context.strokeEllipse(in: annotation.bounds)

    case .arrow(let start, let end):
      drawArrow(from: start, to: end)

    case .line(let start, let end):
      context.move(to: start)
      context.addLine(to: end)
      context.strokePath()

    case .path(let points), .highlight(let points):
      drawPath(points: points, isHighlight: annotation.type.isHighlight)

    case .counter(let value):
      drawCounter(value: value, at: annotation.bounds.origin, color: annotation.properties.strokeColor)

    case .blur:
      drawBlur(bounds: annotation.bounds, annotationId: annotation.id)

    case .text(let content):
      drawText(content, in: annotation.bounds, properties: annotation.properties)
    }
  }

  func drawCurrentStroke(
    tool: AnnotationToolType,
    start: CGPoint,
    currentPath: [CGPoint],
    strokeColor: Color,
    strokeWidth: CGFloat
  ) {
    context.setStrokeColor(NSColor(strokeColor).cgColor)
    context.setLineWidth(strokeWidth)
    context.setLineCap(.round)

    switch tool {
    case .pencil, .highlighter:
      if tool == .highlighter {
        context.setAlpha(0.4)
        context.setLineWidth(strokeWidth * 3)
      }
      guard currentPath.count > 1 else { return }
      context.move(to: currentPath[0])
      for point in currentPath.dropFirst() {
        context.addLine(to: point)
      }
      context.strokePath()
      context.setAlpha(1.0)

    case .rectangle:
      let currentPoint = currentPath.last ?? start
      let rect = makeRect(from: start, to: currentPoint)
      context.stroke(rect)

    case .oval:
      let currentPoint = currentPath.last ?? start
      let rect = makeRect(from: start, to: currentPoint)
      context.strokeEllipse(in: rect)

    case .line:
      let currentPoint = currentPath.last ?? start
      context.move(to: start)
      context.addLine(to: currentPoint)
      context.strokePath()

    case .arrow:
      let currentPoint = currentPath.last ?? start
      drawArrow(from: start, to: currentPoint)

    default:
      break
    }
  }

  // MARK: - Private Drawing Helpers

  private func drawPath(points: [CGPoint], isHighlight: Bool, strokeWidth: CGFloat = 3) {
    guard points.count > 1 else { return }
    if isHighlight {
      context.setAlpha(0.4)
      context.setLineWidth(strokeWidth * 3)
    }
    context.move(to: points[0])
    for point in points.dropFirst() {
      context.addLine(to: point)
    }
    context.strokePath()
    context.setAlpha(1.0)
  }

  private func drawArrow(from start: CGPoint, to end: CGPoint) {
    context.move(to: start)
    context.addLine(to: end)
    context.strokePath()

    let angle = atan2(end.y - start.y, end.x - start.x)
    let arrowLength: CGFloat = 15
    let arrowAngle: CGFloat = .pi / 6

    let point1 = CGPoint(
      x: end.x - arrowLength * cos(angle - arrowAngle),
      y: end.y - arrowLength * sin(angle - arrowAngle)
    )
    let point2 = CGPoint(
      x: end.x - arrowLength * cos(angle + arrowAngle),
      y: end.y - arrowLength * sin(angle + arrowAngle)
    )

    context.move(to: end)
    context.addLine(to: point1)
    context.move(to: end)
    context.addLine(to: point2)
    context.strokePath()
  }

  private func drawCounter(value: Int, at point: CGPoint, color: Color) {
    let size: CGFloat = 24
    let rect = CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size)

    context.setFillColor(NSColor(color).cgColor)
    context.fillEllipse(in: rect)

    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12, weight: .bold),
      .foregroundColor: NSColor.white
    ]
    let text = "\(value)" as NSString
    let textSize = text.size(withAttributes: attributes)
    let textPoint = CGPoint(
      x: point.x - textSize.width/2,
      y: point.y - textSize.height/2
    )
    text.draw(at: textPoint, withAttributes: attributes)
  }

  private func drawText(_ content: String, in bounds: CGRect, properties: AnnotationProperties) {
    let padding: CGFloat = 4
    let displayText = content.isEmpty ? "" : content

    // Draw background if fillColor is not clear
    if properties.fillColor != .clear {
      context.setFillColor(NSColor(properties.fillColor).cgColor)
      let bgRect = CGRect(
        x: bounds.origin.x - padding,
        y: bounds.origin.y - padding,
        width: bounds.width + padding * 2,
        height: bounds.height + padding * 2
      )
      context.fill(bgRect)
    }

    // Draw text
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: properties.fontSize, weight: .regular),
      .foregroundColor: NSColor(properties.strokeColor)
    ]
    let text = displayText as NSString
    let textPoint = CGPoint(x: bounds.origin.x, y: bounds.origin.y)
    text.draw(at: textPoint, withAttributes: attributes)
  }

  private func makeRect(from start: CGPoint, to end: CGPoint) -> CGRect {
    CGRect(
      x: min(start.x, end.x),
      y: min(start.y, end.y),
      width: abs(end.x - start.x),
      height: abs(end.y - start.y)
    )
  }

  private func drawBlur(bounds: CGRect, annotationId: UUID) {
    guard let sourceImage = sourceImage else {
      // Fallback when no source image available
      BlurEffectRenderer.drawBlurPreview(
        in: context,
        region: bounds,
        strokeColor: NSColor.gray.cgColor
      )
      return
    }

    // Try cached version first for performance
    if let cacheManager = blurCacheManager,
       let cachedImage = cacheManager.getCachedBlur(
         for: annotationId,
         bounds: bounds,
         sourceImage: sourceImage
       ) {
      context.draw(cachedImage, in: bounds)
      return
    }

    // Fallback to direct render (slower)
    BlurEffectRenderer.drawPixelatedRegion(
      in: context,
      sourceImage: sourceImage,
      region: bounds
    )
  }

  /// Draw blur preview during drag operation
  func drawBlurPreview(start: CGPoint, currentPoint: CGPoint, strokeColor: Color) {
    let rect = makeRect(from: start, to: currentPoint)
    guard rect.width > 0, rect.height > 0 else { return }

    if let sourceImage = sourceImage {
      // Show actual pixelated preview
      BlurEffectRenderer.drawPixelatedRegion(
        in: context,
        sourceImage: sourceImage,
        region: rect,
        pixelSize: BlurEffectRenderer.defaultPixelSize
      )
    }

    // Draw border indicator
    BlurEffectRenderer.drawBlurPreview(
      in: context,
      region: rect,
      strokeColor: NSColor(strokeColor).cgColor
    )
  }
}

// MARK: - AnnotationType Extension

extension AnnotationType {
  var isHighlight: Bool {
    if case .highlight = self { return true }
    return false
  }
}
