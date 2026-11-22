//
//  AnnotateMagnifierRenderer.swift
//  Snapzy
//
//  Draws Magnifier (loupe) annotations. Called from `AnnotationRenderer.draw`, so the canvas,
//  live preview and every export path match. The lens shows the source image's own pixels
//  (other annotations are not magnified, like Measure), sampled at draw time.
//

import AppKit
import CoreGraphics
import SwiftUI

nonisolated enum AnnotateMagnifierRenderer {
  /// Everything a magnifier paints: the lens with its border and shadow, plus the source
  /// outline and connector when shown. Nil for other types.
  static func drawnBounds(for item: AnnotationItem) -> CGRect? {
    guard case .magnifier(let geometry) = item.type else { return nil }
    let lens = item.bounds.standardized
    let border = max(0, item.properties.strokeWidth) / 2
    var result = lens.insetBy(dx: -border, dy: -border)
    if geometry.showsShadow {
      let blur = max(6, min(lens.width, lens.height) * 0.08)
      let offset = max(2, lens.height * 0.02)
      result = result.union(lens.insetBy(dx: -blur, dy: -blur).offsetBy(dx: 0, dy: -offset))
    }
    if geometry.showsConnector {
      let lineWidth = max(1, item.properties.strokeWidth * 0.6)
      result = result.union(geometry.sourceRect(forLens: lens).insetBy(dx: -lineWidth, dy: -lineWidth))
    }
    return result
  }

  /// Draws `item` into `context`.
  /// - Parameters:
  ///   - sourceImageOrigin: where the source image's bottom-left corner sits in `context`'s
  ///     coordinates (the export path shifts annotations by the crop origin and padding).
  ///   - blurItems: blur/redact annotations in image space (unshifted). They are baked into the
  ///     magnified pixels so a lens never shows what a blur hides.
  static func draw(
    _ item: AnnotationItem,
    sourceImage: NSImage?,
    sourceCGImage: CGImage?,
    sourceImageOrigin: CGPoint,
    blurItems: [AnnotationItem],
    in context: CGContext
  ) {
    guard case .magnifier(let geometry) = item.type else { return }
    let lens = item.bounds.standardized
    guard lens.width > 0, lens.height > 0 else { return }

    let borderColor = NSColor(item.properties.strokeColor).cgColor
    let borderWidth = max(0, item.properties.strokeWidth)
    let source = geometry.sourceRect(forLens: lens)
    let lensPath = MagnifierGeometry.path(for: geometry.shape, in: lens)

    if geometry.showsConnector {
      drawConnector(geometry: geometry, lens: lens, source: source, color: borderColor, lensBorderWidth: borderWidth, in: context)
    }

    // Shadow is cast by an opaque fill under the content, so it shows even where the
    // magnified area is transparent.
    if geometry.showsShadow {
      context.saveGState()
      context.setShadow(
        offset: CGSize(width: 0, height: -max(2, lens.height * 0.02)),
        blur: max(6, min(lens.width, lens.height) * 0.08),
        color: NSColor.black.withAlphaComponent(0.35).cgColor
      )
      context.addPath(lensPath)
      context.setFillColor(NSColor.white.cgColor)
      context.fillPath()
      context.restoreGState()
    }

    if let sourceImage, let sourceCGImage {
      drawMagnifiedPixels(
        sourceImage: sourceImage,
        image: sourceCGImage,
        imageOrigin: sourceImageOrigin,
        blurItems: blurItems,
        geometry: geometry,
        lens: lens,
        source: source,
        clipPath: lensPath,
        in: context
      )
    }

    if borderWidth > 0 {
      context.saveGState()
      context.addPath(lensPath)
      context.setStrokeColor(borderColor)
      context.setLineWidth(borderWidth)
      context.setLineDash(phase: 0, lengths: [])
      context.strokePath()
      context.restoreGState()
    }
  }

  /// Opacity of the cone fill between the source and the lens.
  static let coneFillAlpha: CGFloat = 0.14

  /// Source outline plus a callout cone (two edge lines and a light fill) joining it to the
  /// lens, drawn under the lens. Falls back to one center line when the cone cannot be built,
  /// and draws nothing while the lens covers the source center.
  private static func drawConnector(
    geometry: MagnifierGeometry,
    lens: CGRect,
    source: CGRect,
    color: CGColor,
    lensBorderWidth: CGFloat,
    in context: CGContext
  ) {
    let lineWidth = max(1, lensBorderWidth * 0.6)
    let lensCenter = CGPoint(x: lens.midX, y: lens.midY)
    let sourceCenter = CGPoint(x: source.midX, y: source.midY)
    guard !lens.contains(sourceCenter) else { return }
    let sourcePath = MagnifierGeometry.path(for: geometry.shape, in: source)

    context.saveGState()
    defer { context.restoreGState() }
    context.setStrokeColor(color)
    context.setLineWidth(lineWidth)
    context.setLineDash(phase: 0, lengths: [])
    context.setLineCap(.round)
    context.setLineJoin(.round)

    if let cone = MagnifierGeometry.calloutCone(shape: geometry.shape, source: source, lens: lens) {
      // Fill the cone everywhere but over the source, so the called-out pixels stay untinted.
      context.saveGState()
      let outside = source.union(lens).insetBy(dx: -lens.width, dy: -lens.height)
      context.addRect(outside)
      context.addPath(sourcePath)
      context.clip(using: .evenOdd)
      context.beginPath()
      context.addLines(between: cone)
      context.closePath()
      context.setFillColor(color.copy(alpha: (color.alpha) * coneFillAlpha) ?? color)
      context.fillPath()
      context.restoreGState()

      context.beginPath()
      context.move(to: cone[0])
      context.addLine(to: cone[1])
      context.move(to: cone[2])
      context.addLine(to: cone[3])
      context.strokePath()
    } else if !lens.intersects(source) {
      let from = MagnifierGeometry.boundaryPoint(of: geometry.shape, in: source, toward: lensCenter)
      let to = MagnifierGeometry.boundaryPoint(of: geometry.shape, in: lens, toward: sourceCenter)
      context.beginPath()
      context.move(to: from)
      context.addLine(to: to)
      context.strokePath()
    }

    context.addPath(sourcePath)
    context.strokePath()
  }

  private static func drawMagnifiedPixels(
    sourceImage: NSImage,
    image: CGImage,
    imageOrigin: CGPoint,
    blurItems: [AnnotationItem],
    geometry: MagnifierGeometry,
    lens: CGRect,
    source: CGRect,
    clipPath: CGPath,
    in context: CGContext
  ) {
    let imageSize = sourceImage.size
    guard imageSize.width > 0, imageSize.height > 0, image.width > 0, image.height > 0 else { return }
    let scaleX = CGFloat(image.width) / imageSize.width
    let scaleY = CGFloat(image.height) / imageSize.height

    // Source area in the image's own point space, padded a pixel so edge pixels fill the lens.
    let padding = 1 / min(scaleX, scaleY)
    let imageBounds = CGRect(origin: .zero, size: imageSize)
    let local = source
      .offsetBy(dx: -imageOrigin.x, dy: -imageOrigin.y)
      .insetBy(dx: -padding, dy: -padding)
      .intersection(imageBounds)
    guard !local.isNull, local.width > 0, local.height > 0 else { return }

    // Integral pixel crop (CGImage rows run top-down).
    let pixelMinX = max(0, floor(local.minX * scaleX))
    let pixelMaxX = min(CGFloat(image.width), ceil(local.maxX * scaleX))
    let pixelMinY = max(0, floor((imageSize.height - local.maxY) * scaleY))
    let pixelMaxY = min(CGFloat(image.height), ceil((imageSize.height - local.minY) * scaleY))
    let pixelRect = CGRect(x: pixelMinX, y: pixelMinY, width: pixelMaxX - pixelMinX, height: pixelMaxY - pixelMinY)
    guard pixelRect.width >= 1, pixelRect.height >= 1,
          var cropped = image.cropping(to: pixelRect) else { return }

    // The crop in image points, then in context points, then mapped through the lens.
    let croppedImagePoints = CGRect(
      x: pixelRect.minX / scaleX,
      y: imageSize.height - pixelRect.maxY / scaleY,
      width: pixelRect.width / scaleX,
      height: pixelRect.height / scaleY
    )
    let coveringBlurs = blurItems.filter { $0.bounds.standardized.intersects(croppedImagePoints) }
    if !coveringBlurs.isEmpty,
       let composited = compositeBlurs(
         coveringBlurs,
         over: cropped,
         imagePointRect: croppedImagePoints,
         scale: CGSize(width: scaleX, height: scaleY),
         sourceImage: sourceImage,
         sourceCGImage: image
       ) {
      cropped = composited
    }
    let croppedPoints = croppedImagePoints.offsetBy(dx: imageOrigin.x, dy: imageOrigin.y)
    let zoom = geometry.zoom
    let destination = CGRect(
      x: lens.midX + (croppedPoints.minX - geometry.sourceCenter.x) * zoom,
      y: lens.midY + (croppedPoints.minY - geometry.sourceCenter.y) * zoom,
      width: croppedPoints.width * zoom,
      height: croppedPoints.height * zoom
    )

    context.saveGState()
    context.addPath(clipPath)
    context.clip()
    // Crisp pixels when zoomed in far; smooth at small factors, where nearest-neighbour
    // duplication looks uneven.
    context.interpolationQuality = zoom >= 3 ? .none : .high
    context.draw(cropped, in: destination)
    context.restoreGState()
  }

  /// Renders `blurs` over the cropped source pixels in an offscreen context laid out in image
  /// space, through the deterministic (export) blur path, so canvas and export agree.
  private static func compositeBlurs(
    _ blurs: [AnnotationItem],
    over cropped: CGImage,
    imagePointRect: CGRect,
    scale: CGSize,
    sourceImage: NSImage,
    sourceCGImage: CGImage
  ) -> CGImage? {
    let colorSpace = cropped.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let offscreen = CGContext(
      data: nil,
      width: cropped.width,
      height: cropped.height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    offscreen.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
    offscreen.scaleBy(x: scale.width, y: scale.height)
    offscreen.translateBy(x: -imagePointRect.minX, y: -imagePointRect.minY)
    let renderer = AnnotationRenderer(context: offscreen, sourceImage: sourceImage, sourceCGImage: sourceCGImage)
    for blur in blurs {
      renderer.draw(blur)
    }
    return offscreen.makeImage()
  }
}
