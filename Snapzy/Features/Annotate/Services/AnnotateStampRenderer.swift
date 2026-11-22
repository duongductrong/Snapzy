//
//  AnnotateStampRenderer.swift
//  Snapzy
//
//  Draws stamp annotations. Used by the canvas, the drag preview and every export
//  through `AnnotationRenderer`, so what the editor shows is what gets saved.
//

import AppKit
import CoreGraphics
import CoreText
import ImageIO

nonisolated enum AnnotateStampRenderer {
  /// Die-cut outline width, as a fraction of the stamp's shorter side.
  static let outlineFraction: CGFloat = 0.075
  /// Hard drop shadow (no blur): how far it falls, as a fraction of the stamp's shorter side,
  /// and its opacity.
  static let shadowOffsetFraction: CGFloat = 0.06
  static let shadowAlpha: CGFloat = 0.18

  // MARK: - Geometry

  /// The rect the stamp actually occupies inside `bounds`: its content aspect-fit and centered,
  /// so a free resize never distorts it.
  static func fittedRect(for content: StampContent, in bounds: CGRect) -> CGRect {
    aspectFit(aspectRatio: content.aspectRatio, in: bounds.standardized)
  }

  /// How far a sticker-style stamp's shadow reaches past its bounds.
  static func shadowOverhang(for bounds: CGRect) -> CGFloat {
    let side = min(abs(bounds.width), abs(bounds.height))
    return side * shadowOffsetFraction
  }

  /// Bounds for a new stamp whose longer side is `size`, centered on `center`.
  static func bounds(for content: StampContent, size: CGFloat, centeredAt center: CGPoint) -> CGRect {
    let ratio = max(content.aspectRatio, 0.01)
    let width = ratio >= 1 ? size : size * ratio
    let height = ratio >= 1 ? size / ratio : size
    return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
  }

  static func aspectFit(aspectRatio: CGFloat, in rect: CGRect) -> CGRect {
    guard rect.width > 0, rect.height > 0, aspectRatio > 0, aspectRatio.isFinite else { return rect }
    var size = CGSize(width: rect.width, height: rect.width / aspectRatio)
    if size.height > rect.height {
      size = CGSize(width: rect.height * aspectRatio, height: rect.height)
    }
    return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
  }

  // MARK: - Drawing

  static func draw(_ stamp: StampAnnotation, in bounds: CGRect, opacity: CGFloat, context: CGContext) {
    let fitted = fittedRect(for: stamp.content, in: bounds)
    guard fitted.width >= 1, fitted.height >= 1 else { return }
    let side = min(fitted.width, fitted.height)
    let outline = stamp.isStickerStyle ? side * outlineFraction : 0
    // The outline grows inward so the whole sticker stays inside its bounds.
    let contentRect = aspectFit(aspectRatio: stamp.content.aspectRatio, in: fitted.insetBy(dx: outline, dy: outline))
    let alpha = min(max(opacity, 0), 1)
    let deviceScale = Self.deviceScale(of: context)

    context.saveGState()
    defer { context.restoreGState() }
    context.setAlpha(alpha)
    if stamp.isStickerStyle {
      applyShadow(side: side, context: context)
    }
    let usesLayer = stamp.isStickerStyle || alpha < 1
    if usesLayer { context.beginTransparencyLayer(auxiliaryInfo: nil) }

    switch stamp.content {
    case .sticker(let sticker):
      drawSticker(sticker, in: contentRect, outline: outline, deviceScale: deviceScale, context: context)
    case .emoji(let emoji):
      let pixels = pixelBucket(max(contentRect.width, contentRect.height) * deviceScale)
      if let image = StampRasterCache.emoji(emoji, pixelSize: pixels) {
        if outline > 0, let silhouette = StampRasterCache.silhouette(of: image, key: "emoji|\(emoji)|\(pixels)") {
          drawDieCut(silhouette, in: contentRect, outline: outline, context: context)
        }
        drawImage(image, in: contentRect, context: context)
      }
    case .image(let stampImage):
      if let image = StampRasterCache.image(stampImage) {
        if outline > 0, let silhouette = StampRasterCache.silhouette(of: image, key: "image|\(stampImage.id.uuidString)") {
          drawDieCut(silhouette, in: contentRect, outline: outline, context: context)
        }
        drawImage(image, in: contentRect, context: context)
      }
    }

    if usesLayer { context.endTransparencyLayer() }
  }

  private static func drawSticker(
    _ sticker: StampSticker,
    in rect: CGRect,
    outline: CGFloat,
    deviceScale: CGFloat,
    context: CGContext
  ) {
    let shape: CGPath
    let outlineShape: CGPath
    switch sticker.shape {
    case .badge:
      shape = CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
      let outer = rect.insetBy(dx: -outline, dy: -outline)
      outlineShape = CGPath(roundedRect: outer, cornerWidth: outer.height / 2, cornerHeight: outer.height / 2, transform: nil)
    case .round:
      shape = CGPath(ellipseIn: rect, transform: nil)
      outlineShape = CGPath(ellipseIn: rect.insetBy(dx: -outline, dy: -outline), transform: nil)
    }

    if outline > 0 {
      context.addPath(outlineShape)
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fillPath()
    }

    // Body: one flat color. No gradient, gloss or inner highlight.
    context.addPath(shape)
    context.setFillColor(sticker.fill.cgColor())
    context.fillPath()

    let foreground = sticker.foreground.cgColor()
    switch sticker.shape {
    case .round:
      let iconSide = rect.height * 0.54
      let iconRect = CGRect(x: rect.midX - iconSide / 2, y: rect.midY - iconSide / 2, width: iconSide, height: iconSide)
      drawSymbol(sticker.symbolName, weight: .bold, color: sticker.foreground, in: iconRect, deviceScale: deviceScale, context: context)
    case .badge:
      let height = rect.height
      let iconSide = height * StampBadgeLayout.iconSize
      let iconRect = CGRect(
        x: rect.minX + height * StampBadgeLayout.horizontalPadding,
        y: rect.midY - iconSide / 2,
        width: iconSide,
        height: iconSide
      )
      drawSymbol(sticker.symbolName, weight: .heavy, color: sticker.foreground, in: iconRect, deviceScale: deviceScale, context: context)
      if let line = StampBadgeLayout.textLine(for: sticker, height: height, color: foreground) {
        let font = StampBadgeLayout.roundedHeavyFont(size: height * StampBadgeLayout.fontSize)
        let capHeight = CTFontGetCapHeight(font)
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(
          x: iconRect.maxX + height * StampBadgeLayout.iconGap,
          y: rect.midY - capHeight / 2
        )
        CTLineDraw(line, context)
        context.restoreGState()
      }
    }
  }

  private static func drawSymbol(
    _ name: String,
    weight: NSFont.Weight,
    color: StampSticker.RGB,
    in rect: CGRect,
    deviceScale: CGFloat,
    context: CGContext
  ) {
    let pixels = pixelBucket(max(rect.width, rect.height) * deviceScale)
    guard let image = StampRasterCache.symbol(name, weight: weight, color: color, pixelSize: pixels) else { return }
    drawImage(image, in: rect, context: context)
  }

  /// A white sticker edge around any shape: the content's silhouette stamped in a ring.
  private static func drawDieCut(_ silhouette: CGImage, in rect: CGRect, outline: CGFloat, context: CGContext) {
    let steps = 24
    for step in 0 ..< steps {
      let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
      drawImage(silhouette, in: rect.offsetBy(dx: cos(angle) * outline, dy: sin(angle) * outline), context: context)
    }
    drawImage(silhouette, in: rect, context: context)
  }

  private static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
    context.saveGState()
    context.interpolationQuality = .high
    context.draw(image, in: rect)
    context.restoreGState()
  }

  /// Shadow offset lives in base space (y-up, unaffected by the CTM), so scale them by
  /// the CTM's scale: the canvas at any zoom and every export resolution then show the same
  /// shadow relative to the stamp. The drop always points down, even for a rotated stamp,
  /// like the light source of the other annotation shadows.
  private static func applyShadow(side: CGFloat, context: CGContext) {
    let scale = deviceScale(of: context)
    context.setShadow(
      offset: CGSize(width: 0, height: -side * shadowOffsetFraction * scale),
      blur: 0,
      color: CGColor(gray: 0, alpha: shadowAlpha)
    )
  }

  static func deviceScale(of context: CGContext) -> CGFloat {
    let transform = context.userSpaceToDeviceSpaceTransform
    let scale = sqrt(abs(transform.a * transform.d - transform.b * transform.c))
    return scale.isFinite && scale > 0 ? scale : 1
  }

  /// Raster sizes snap to powers of two (32…1024 px) so zooming reuses cached images.
  static func pixelBucket(_ pixels: CGFloat) -> Int {
    let target = min(max(pixels.isFinite ? pixels : 64, 32), 1024)
    var bucket = 32
    while CGFloat(bucket) < target { bucket *= 2 }
    return bucket
  }
}

// MARK: - Raster cache

/// Thread-safe cache of rasterized emoji, symbols, decoded image stamps and their
/// silhouettes. Canvas drawing (main) and exports (background) share it.
nonisolated enum StampRasterCache {
  private nonisolated final class Box {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
  }

  nonisolated(unsafe) private static let cache: NSCache<NSString, Box> = {
    let cache = NSCache<NSString, Box>()
    cache.countLimit = 256
    cache.totalCostLimit = 96 * 1024 * 1024
    return cache
  }()

  private static func cached(_ key: String, make: () -> CGImage?) -> CGImage? {
    if let box = cache.object(forKey: key as NSString) { return box.image }
    guard let image = make() else { return nil }
    cache.setObject(Box(image), forKey: key as NSString, cost: image.bytesPerRow * image.height)
    return image
  }

  static func emoji(_ emoji: String, pixelSize: Int) -> CGImage? {
    cached("emoji|\(emoji)|\(pixelSize)") {
      guard let context = makeContext(width: pixelSize, height: pixelSize) else { return nil }
      let side = CGFloat(pixelSize)
      let font = CTFontCreateWithName("AppleColorEmoji" as CFString, side * 0.8, nil)
      let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
      ]
      let line = CTLineCreateWithAttributedString(NSAttributedString(string: emoji, attributes: attributes))
      let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
      let imageBounds = glyphBounds.isEmpty ? CTLineGetImageBounds(line, context) : glyphBounds
      guard imageBounds.width > 0, imageBounds.height > 0 else { return nil }
      // Fit the glyph into the square with a small margin.
      let fit = min(side * 0.96 / imageBounds.width, side * 0.96 / imageBounds.height, 1.2)
      context.translateBy(x: side / 2, y: side / 2)
      context.scaleBy(x: fit, y: fit)
      context.textMatrix = .identity
      context.textPosition = CGPoint(x: -imageBounds.midX, y: -imageBounds.midY)
      CTLineDraw(line, context)
      return context.makeImage()
    }
  }

  static func symbol(_ name: String, weight: NSFont.Weight, color: StampSticker.RGB, pixelSize: Int) -> CGImage? {
    cached("symbol|\(name)|\(weight.rawValue)|\(color.red),\(color.green),\(color.blue)|\(pixelSize)") {
      guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
            let symbol = base.withSymbolConfiguration(
              NSImage.SymbolConfiguration(pointSize: CGFloat(pixelSize) * 0.8, weight: weight)
            ),
            let context = makeContext(width: pixelSize, height: pixelSize) else { return nil }
      let side = CGFloat(pixelSize)
      let rect = AnnotateStampRenderer.aspectFit(
        aspectRatio: symbol.size.width / max(symbol.size.height, 1),
        in: CGRect(x: 0, y: 0, width: side, height: side)
      )
      let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = graphicsContext
      symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
      NSGraphicsContext.restoreGraphicsState()
      context.setBlendMode(.sourceIn)
      context.setFillColor(color.cgColor())
      context.fill(CGRect(x: 0, y: 0, width: side, height: side))
      return context.makeImage()
    }
  }

  static func image(_ stampImage: StampImage) -> CGImage? {
    cached("image|\(stampImage.id.uuidString)") {
      guard let source = CGImageSourceCreateWithData(stampImage.pngData as CFData, nil) else { return nil }
      return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
  }

  /// The image's alpha filled white, at most 512 px on the long side.
  static func silhouette(of image: CGImage, key: String) -> CGImage? {
    cached("silhouette|\(key)") {
      let longSide = CGFloat(max(image.width, image.height))
      let scale = min(1, 512 / max(longSide, 1))
      let width = max(Int((CGFloat(image.width) * scale).rounded()), 1)
      let height = max(Int((CGFloat(image.height) * scale).rounded()), 1)
      guard let context = makeContext(width: width, height: height) else { return nil }
      let rect = CGRect(x: 0, y: 0, width: width, height: height)
      context.interpolationQuality = .high
      context.draw(image, in: rect)
      context.setBlendMode(.sourceIn)
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fill(rect)
      return context.makeImage()
    }
  }

  private static func makeContext(width: Int, height: Int) -> CGContext? {
    CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  }
}
