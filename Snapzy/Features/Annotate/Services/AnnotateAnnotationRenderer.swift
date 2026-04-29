//
//  AnnotationRenderer.swift
//  Snapzy
//
//  Handles rendering annotations to CGContext
//

import AppKit
import CoreGraphics
import SwiftUI

/// Renders annotations to a CGContext
struct AnnotationRenderer {
  private static let interactiveApproximateReuseAreaThreshold: CGFloat = 90_000
  private static let livePreviewFullQualityAreaThreshold: CGFloat = 120_000

  let context: CGContext
  var editingTextId: UUID?
  var sourceImage: NSImage?
  var blurCacheManager: BlurCacheManager?
  var interactiveBlurAnnotationId: UUID?
  var interactiveEmbeddedImageAnnotationId: UUID?
  var embeddedImageProvider: ((UUID) -> NSImage?)?
  var embeddedCGImageProvider: ((UUID) -> CGImage?)?

  init(
    context: CGContext,
    editingTextId: UUID? = nil,
    sourceImage: NSImage? = nil,
    blurCacheManager: BlurCacheManager? = nil,
    interactiveBlurAnnotationId: UUID? = nil,
    interactiveEmbeddedImageAnnotationId: UUID? = nil,
    embeddedImageProvider: ((UUID) -> NSImage?)? = nil,
    embeddedCGImageProvider: ((UUID) -> CGImage?)? = nil
  ) {
    self.context = context
    self.editingTextId = editingTextId
    self.sourceImage = sourceImage
    self.blurCacheManager = blurCacheManager
    self.interactiveBlurAnnotationId = interactiveBlurAnnotationId
    self.interactiveEmbeddedImageAnnotationId = interactiveEmbeddedImageAnnotationId
    self.embeddedImageProvider = embeddedImageProvider
    self.embeddedCGImageProvider = embeddedCGImageProvider
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
      context.addPath(roundedRectPath(in: annotation.bounds, cornerRadius: annotation.properties.cornerRadius))
      context.strokePath()

    case .filledRectangle:
      context.addPath(roundedRectPath(in: annotation.bounds, cornerRadius: annotation.properties.cornerRadius))
      context.drawPath(using: .fillStroke)

    case .oval:
      context.strokeEllipse(in: annotation.bounds)

    case .arrow(let geometry):
      drawArrow(geometry, strokeWidth: annotation.properties.strokeWidth)

    case .line(let start, let end):
      context.move(to: start)
      context.addLine(to: end)
      context.strokePath()

    case .path(let points), .highlight(let points):
      drawPath(
        points: points,
        isHighlight: annotation.type.isHighlight,
        strokeWidth: annotation.properties.strokeWidth
      )

    case .counter(let value):
      drawCounter(value: value, in: annotation.bounds, properties: annotation.properties)

    case .blur(let blurType):
      drawBlur(
        bounds: annotation.bounds,
        annotationId: annotation.id,
        blurType: blurType,
        controlValue: annotation.properties.strokeWidth
      )

    case .text(let content):
      drawText(content, in: annotation.bounds, properties: annotation.properties)

    case .watermark(let content):
      drawWatermark(content, in: annotation.bounds, properties: annotation.properties)

    case .embeddedImage(let assetId):
      drawEmbeddedImage(assetId: assetId, annotationId: annotation.id, in: annotation.bounds)
    }
  }

  func drawCurrentStroke(
    tool: AnnotationToolType,
    start: CGPoint,
    currentPath: [CGPoint],
    strokeColor: Color,
    strokeWidth: CGFloat,
    fillColor: Color = .clear,
    arrowStyle: ArrowStyle = .straight,
    rectangleCornerRadius: CGFloat = 0,
    watermarkText: String = "Snapzy",
    watermarkStyle: WatermarkStyle = .diagonal,
    watermarkOpacity: CGFloat = 0.22,
    watermarkRotationDegrees: CGFloat = -24,
    watermarkFontSize: CGFloat = 36
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
      context.addPath(roundedRectPath(in: rect, cornerRadius: rectangleCornerRadius))
      context.strokePath()

    case .filledRectangle:
      let currentPoint = currentPath.last ?? start
      let rect = makeRect(from: start, to: currentPoint)
      let resolvedFillColor = fillColor == .clear ? strokeColor.opacity(1) : fillColor
      context.setFillColor(NSColor(resolvedFillColor).cgColor)
      context.addPath(roundedRectPath(in: rect, cornerRadius: rectangleCornerRadius))
      context.drawPath(using: .fillStroke)
      context.setFillColor(NSColor.clear.cgColor)

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
      drawArrow(
        ArrowGeometry(start: start, end: currentPoint, style: arrowStyle),
        strokeWidth: strokeWidth
      )

    case .watermark:
      let currentPoint = currentPath.last ?? start
      let rect = makeRect(from: start, to: currentPoint)
      guard rect.width >= 24, rect.height >= 24 else { return }
      drawWatermark(
        watermarkText,
        in: rect,
        properties: AnnotationProperties(
          strokeColor: strokeColor,
          fillColor: .clear,
          strokeWidth: strokeWidth,
          fontSize: watermarkFontSize,
          opacity: watermarkOpacity,
          rotationDegrees: watermarkRotationDegrees,
          watermarkStyle: watermarkStyle
        )
      )

    default:
      break
    }
  }

  // MARK: - Private Drawing Helpers

  private func drawPath(points: [CGPoint], isHighlight: Bool, strokeWidth: CGFloat) {
    guard points.count > 1 else { return }
    if isHighlight {
      context.setAlpha(0.4)
      context.setLineWidth(strokeWidth * 3)
    } else {
      context.setLineWidth(strokeWidth)
    }
    context.move(to: points[0])
    for point in points.dropFirst() {
      context.addLine(to: point)
    }
    context.strokePath()
    context.setAlpha(1.0)
  }

  private func roundedRectPath(in rect: CGRect, cornerRadius: CGFloat) -> CGPath {
    let clampedCornerRadius = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
    guard clampedCornerRadius > 0 else {
      return CGPath(rect: rect, transform: nil)
    }
    return CGPath(
      roundedRect: rect,
      cornerWidth: clampedCornerRadius,
      cornerHeight: clampedCornerRadius,
      transform: nil
    )
  }

  private func drawArrow(_ geometry: ArrowGeometry, strokeWidth: CGFloat) {
    context.addPath(geometry.path())
    context.strokePath()

    guard geometry.isRenderable else { return }

    let angle = geometry.tangentAngleAtEnd()
    let arrowLength = min(max(strokeWidth * 3.5, 12), 24)
    let arrowAngle: CGFloat = .pi / 6
    let end = geometry.end

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

  private func drawCounter(value: Int, in bounds: CGRect, properties: AnnotationProperties) {
    let rect: CGRect
    if bounds.standardized.isEmpty {
      let size = AnnotationProperties.counterDiameter(for: properties.strokeWidth)
      rect = CGRect(x: bounds.origin.x - size / 2, y: bounds.origin.y - size / 2, width: size, height: size)
    } else {
      rect = bounds.standardized
    }

    context.setFillColor(NSColor(properties.strokeColor).cgColor)
    context.fillEllipse(in: rect)

    let fontSize = min(max(rect.height * 0.5, 11), 56)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
      .foregroundColor: NSColor.white
    ]
    let text = "\(value)" as NSString
    let textSize = text.size(withAttributes: attributes)
    let textPoint = CGPoint(
      x: rect.midX - textSize.width / 2,
      y: rect.midY - textSize.height / 2
    )
    text.draw(at: textPoint, withAttributes: attributes)
  }

  private func drawText(_ content: String, in bounds: CGRect, properties: AnnotationProperties) {
    let displayText = content.isEmpty ? "" : content
    let font = AnnotateTextLayout.font(size: properties.fontSize, fontName: properties.fontName)

    // Draw background if fillColor is not clear
    if properties.fillColor != .clear {
      context.setFillColor(NSColor(properties.fillColor).cgColor)
      let bgRect = CGRect(
        x: bounds.origin.x - AnnotateTextLayout.horizontalPadding,
        y: bounds.origin.y - AnnotateTextLayout.verticalPadding,
        width: bounds.width + AnnotateTextLayout.horizontalPadding * 2,
        height: bounds.height + AnnotateTextLayout.verticalPadding * 2
      )
      context.fill(bgRect)
    }

    // Draw text with word wrapping within bounds
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineBreakMode = .byWordWrapping

    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: NSColor(properties.strokeColor),
      .paragraphStyle: paragraphStyle
    ]

    let textRect = AnnotateTextLayout.textRect(for: content, font: font, in: bounds)
    let text = displayText as NSString
    text.draw(in: textRect, withAttributes: attributes)
  }

  private func drawWatermark(_ content: String, in bounds: CGRect, properties: AnnotationProperties) {
    let resolvedText = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !resolvedText.isEmpty else { return }

    let visibleBounds = bounds.standardized
    guard visibleBounds.width > 0, visibleBounds.height > 0 else { return }

    let font = NSFontManager.shared.convert(
      AnnotateTextLayout.font(size: properties.fontSize, fontName: properties.fontName),
      toHaveTrait: .boldFontMask
    )
    let alpha = AnnotationProperties.clampedOpacity(properties.opacity)
    let text = resolvedText as NSString
    let attributes = watermarkAttributes(
      font: font,
      color: NSColor(properties.strokeColor).withAlphaComponent(alpha)
    )
    let textSize = text.size(withAttributes: attributes)

    context.saveGState()
    context.clip(to: visibleBounds)

    switch properties.watermarkStyle {
    case .single:
      drawCenteredWatermarkText(text, textSize: textSize, attributes: attributes, in: visibleBounds, rotationDegrees: properties.rotationDegrees)

    case .diagonal:
      drawCenteredWatermarkText(text, textSize: textSize, attributes: attributes, in: visibleBounds, rotationDegrees: properties.rotationDegrees)

    case .tiled:
      drawTiledWatermarkText(text, textSize: textSize, attributes: attributes, in: visibleBounds, rotationDegrees: properties.rotationDegrees)
    }

    context.restoreGState()
  }

  private func watermarkAttributes(font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 1.5
    shadow.shadowOffset = .zero
    shadow.shadowColor = NSColor.black.withAlphaComponent(min(color.alphaComponent * 0.35, 0.12))

    return [
      .font: font,
      .foregroundColor: color,
      .kern: font.pointSize * 0.04,
      .shadow: shadow
    ]
  }

  private func drawCenteredWatermarkText(
    _ text: NSString,
    textSize: CGSize,
    attributes: [NSAttributedString.Key: Any],
    in bounds: CGRect,
    rotationDegrees: CGFloat
  ) {
    context.saveGState()
    context.translateBy(x: bounds.midX, y: bounds.midY)
    context.rotate(by: rotationDegrees * .pi / 180)
    text.draw(
      at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2),
      withAttributes: attributes
    )
    context.restoreGState()
  }

  private func drawTiledWatermarkText(
    _ text: NSString,
    textSize: CGSize,
    attributes: [NSAttributedString.Key: Any],
    in bounds: CGRect,
    rotationDegrees: CGFloat
  ) {
    let span = hypot(bounds.width, bounds.height)
    let xStep = max(textSize.width + textSize.height * 2.4, 120)
    let yStep = max(textSize.height * 3.4, 72)

    context.saveGState()
    context.translateBy(x: bounds.midX, y: bounds.midY)
    context.rotate(by: rotationDegrees * .pi / 180)

    var y = -span
    while y <= span {
      var x = -span
      while x <= span {
        text.draw(at: CGPoint(x: x - textSize.width / 2, y: y - textSize.height / 2), withAttributes: attributes)
        x += xStep
      }
      y += yStep
    }

    context.restoreGState()
  }

  private func drawEmbeddedImage(assetId: UUID, annotationId: UUID, in bounds: CGRect) {
    let isInteractive = interactiveEmbeddedImageAnnotationId == annotationId
    let interpolationQuality: CGInterpolationQuality = isInteractive ? .low : .high

    if let cgImage = embeddedCGImageProvider?(assetId) {
      context.saveGState()
      context.interpolationQuality = interpolationQuality
      context.draw(cgImage, in: bounds)
      context.restoreGState()
      return
    }

    guard let image = embeddedImageProvider?(assetId) else { return }
    let sourceRect = CGRect(origin: .zero, size: image.size)
    context.saveGState()
    context.interpolationQuality = interpolationQuality
    image.draw(
      in: bounds,
      from: sourceRect,
      operation: .sourceOver,
      fraction: 1.0
    )
    context.restoreGState()
  }

  private func makeRect(from start: CGPoint, to end: CGPoint) -> CGRect {
    CGRect(
      x: min(start.x, end.x),
      y: min(start.y, end.y),
      width: abs(end.x - start.x),
      height: abs(end.y - start.y)
    )
  }

  private func drawBlur(bounds: CGRect, annotationId: UUID, blurType: BlurType, controlValue: CGFloat) {
    let visibleBounds = bounds.standardized
    guard visibleBounds.width > 0, visibleBounds.height > 0 else { return }

    guard let sourceImage = sourceImage else {
      // Fallback when no source image available
      BlurEffectRenderer.drawBlurPreview(
        in: context,
        region: visibleBounds,
        strokeColor: NSColor.gray.cgColor
      )
      return
    }

    let renderBounds = alignToSourcePixelGrid(visibleBounds, sourceImage: sourceImage)
    let effectValue = blurEffectValue(for: blurType, controlValue: controlValue)
    let shouldAllowApproximateReuse =
      interactiveBlurAnnotationId == annotationId &&
      (visibleBounds.width * visibleBounds.height) >= Self.interactiveApproximateReuseAreaThreshold

    context.saveGState()
    context.clip(to: visibleBounds)
    defer { context.restoreGState() }

    // Try cached version first for performance
    if let cacheManager = blurCacheManager,
       let cachedImage = cacheManager.getCachedBlur(
         for: annotationId,
         bounds: renderBounds,
         sourceImage: sourceImage,
         blurType: blurType,
         effectValue: effectValue,
         allowApproximateReuse: shouldAllowApproximateReuse
       ) {
      switch blurType {
      case .pixelated:
        context.saveGState()
        context.setAllowsAntialiasing(false)
        context.setShouldAntialias(false)
        context.interpolationQuality = .none
        context.draw(cachedImage, in: renderBounds)
        context.restoreGState()
      case .gaussian:
        context.interpolationQuality = .high
        context.draw(cachedImage, in: renderBounds)
      }
      return
    }

    // Fallback to direct render (slower)
    switch blurType {
    case .pixelated:
      BlurEffectRenderer.drawPixelatedRegion(
        in: context,
        sourceImage: sourceImage,
        region: renderBounds,
        pixelSize: effectValue
      )
    case .gaussian:
      BlurEffectRenderer.drawGaussianRegion(
        in: context,
        sourceImage: sourceImage,
        region: renderBounds,
        radius: Double(effectValue)
      )
    }
  }

  private func alignToSourcePixelGrid(_ rect: CGRect, sourceImage: NSImage) -> CGRect {
    guard sourceImage.size.width > 0,
          sourceImage.size.height > 0,
          let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
          cgImage.width > 0,
          cgImage.height > 0 else {
      return rect
    }

    let scaleX = CGFloat(cgImage.width) / sourceImage.size.width
    let scaleY = CGFloat(cgImage.height) / sourceImage.size.height
    let minX = floor(rect.minX * scaleX) / scaleX
    let maxX = ceil(rect.maxX * scaleX) / scaleX
    let minY = floor(rect.minY * scaleY) / scaleY
    let maxY = ceil(rect.maxY * scaleY) / scaleY
    let aligned = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    return aligned.standardized
  }

  /// Draw blur preview during drag operation
  func drawBlurPreview(
    start: CGPoint,
    currentPoint: CGPoint,
    strokeColor: Color,
    blurType: BlurType,
    controlValue: CGFloat
  ) {
    let rect = makeRect(from: start, to: currentPoint)
    guard rect.width > 0, rect.height > 0 else { return }

    if (rect.width * rect.height) >= Self.livePreviewFullQualityAreaThreshold {
      BlurEffectRenderer.drawBlurPreview(
        in: context,
        region: rect,
        strokeColor: NSColor(strokeColor).cgColor
      )
      return
    }

    if let sourceImage = sourceImage {
      let effectValue = blurEffectValue(for: blurType, controlValue: controlValue)
      // Show preview based on selected blur type
      switch blurType {
      case .pixelated:
        BlurEffectRenderer.drawPixelatedRegion(
          in: context,
          sourceImage: sourceImage,
          region: rect,
          pixelSize: effectValue
        )
      case .gaussian:
        BlurEffectRenderer.drawGaussianRegion(
          in: context,
          sourceImage: sourceImage,
          region: rect,
          radius: Double(effectValue)
        )
      }
    }

    // Draw border indicator
    BlurEffectRenderer.drawBlurPreview(
      in: context,
      region: rect,
      strokeColor: NSColor(strokeColor).cgColor
    )
  }

  private func blurEffectValue(for blurType: BlurType, controlValue: CGFloat) -> CGFloat {
    switch blurType {
    case .pixelated:
      return AnnotationProperties.pixelatedBlurSize(for: controlValue)
    case .gaussian:
      return AnnotationProperties.gaussianBlurRadius(for: controlValue)
    }
  }
}

// MARK: - AnnotationType Extension

extension AnnotationType {
  var isHighlight: Bool {
    if case .highlight = self { return true }
    return false
  }
}
