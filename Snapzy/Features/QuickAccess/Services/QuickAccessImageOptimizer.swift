//
//  QuickAccessImageOptimizer.swift
//  Snapzy
//
//  Pure, thread-safe helpers behind the Quick Access "Optimize" action: which
//  downscale levels a screenshot offers, and how a level is rendered and encoded.
//
//  Only downscaling is offered. Upscaling with plain interpolation makes the file
//  bigger without adding detail, so it is deliberately not a level.
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// One entry of the Optimize list: a fraction of the original pixel size.
nonisolated struct QuickAccessOptimizeLevel: Identifiable, Equatable, Hashable, Sendable {
  /// Fraction of the original pixel dimensions; `1` is the original.
  let fraction: CGFloat
  /// Display density the image has at this level (pixels per point), e.g. `2` for "2x".
  let scale: CGFloat
  let pixelWidth: Int
  let pixelHeight: Int

  var id: CGFloat { fraction }
  var isOriginal: Bool { fraction >= 1 }

  /// "0.5x", "1x", "1.5x", "0.75x".
  var scaleLabel: String { QuickAccessImageOptimizer.formatScale(scale) }
  var dimensionsLabel: String { "\(pixelWidth)×\(pixelHeight)" }
}

/// What the optimizer needs to know about a source file without decoding it.
nonisolated struct QuickAccessOptimizeSourceInfo: Equatable, Sendable {
  let pixelWidth: Int
  let pixelHeight: Int
  /// Pixels per point the file was captured at (from its DPI), e.g. `2` on Retina.
  let nativeScale: CGFloat
}

nonisolated enum QuickAccessImageOptimizer {
  /// Levels whose long edge would drop below this are hidden: past that point the
  /// image stops being useful for the sharing case the action exists for.
  static let minimumLongEdge = 320

  /// File types the action can rewrite in place.
  static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "heic", "heif", "avif"]

  static let jpegQuality: CGFloat = 0.9
  static let webpQuality: CGFloat = 0.85

  /// Rewriting in place re-encodes the file, so an AVIF on a Mac without the encoder is skipped.
  static func supports(url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    return supportedExtensions.contains(ext) && ImageEncoderSupport.canEncode(fileExtension: ext)
  }

  // MARK: - Levels

  /// Fractions of the original offered below it. A Retina capture (2x) gets
  /// 1.5x / 1x / 0.5x; a 1x capture gets 0.75x / 0.5x.
  static func fractions(forNativeScale nativeScale: CGFloat) -> [CGFloat] {
    nativeScale >= 1.75 ? [0.25, 0.5, 0.75] : [0.5, 0.75]
  }

  /// Levels ordered smallest first, with the original always last.
  static func levels(for source: QuickAccessOptimizeSourceInfo) -> [QuickAccessOptimizeLevel] {
    let nativeScale = max(source.nativeScale, 0.25)
    let longEdge = max(source.pixelWidth, source.pixelHeight)

    let reduced = fractions(forNativeScale: nativeScale).compactMap { fraction -> QuickAccessOptimizeLevel? in
      let width = Int((CGFloat(source.pixelWidth) * fraction).rounded())
      let height = Int((CGFloat(source.pixelHeight) * fraction).rounded())
      guard width >= 1, height >= 1,
            Int((CGFloat(longEdge) * fraction).rounded()) >= minimumLongEdge else {
        return nil
      }
      return QuickAccessOptimizeLevel(
        fraction: fraction,
        scale: nativeScale * fraction,
        pixelWidth: width,
        pixelHeight: height
      )
    }

    let original = QuickAccessOptimizeLevel(
      fraction: 1,
      scale: nativeScale,
      pixelWidth: source.pixelWidth,
      pixelHeight: source.pixelHeight
    )
    return reduced + [original]
  }

  static func formatScale(_ scale: CGFloat) -> String {
    let rounded = (Double(scale) * 100).rounded() / 100
    return String(format: "%gx", rounded)
  }

  static func formatByteCount(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }

  // MARK: - Reading

  /// Reads dimensions and DPI from the file header without decoding pixels.
  static func sourceInfo(at url: URL, fallbackScale: CGFloat) -> QuickAccessOptimizeSourceInfo? {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0 else {
      return nil
    }
    return QuickAccessOptimizeSourceInfo(
      pixelWidth: width,
      pixelHeight: height,
      nativeScale: nativeScale(from: properties) ?? fallbackScale
    )
  }

  /// Snapzy writes DPI = 72 × backing scale for PNG, JPEG, HEIC and AVIF. WebP carries no DPI.
  static func nativeScale(from properties: [CFString: Any]) -> CGFloat? {
    guard let dpi = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue,
          dpi > 0 else {
      return nil
    }
    let scale = dpi / 72.0
    // Snap to quarter steps so 143.99 dpi still reads as 2x.
    return CGFloat((scale * 4).rounded() / 4)
  }

  static func loadImage(at url: URL) -> CGImage? {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(imageSource, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
  }

  // MARK: - Rendering

  /// `flattensAlpha` composites onto white first, for formats without alpha (JPEG),
  /// where transparent window shadows would otherwise turn black.
  static func resized(_ image: CGImage, width: Int, height: Int, flattensAlpha: Bool = false) -> CGImage? {
    guard width > 0, height > 0 else { return nil }
    let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
    if width == image.width, height == image.height, !(flattensAlpha && hasAlpha) { return image }

    let colorSpace: CGColorSpace = {
      if let space = image.colorSpace, space.model == .rgb { return space }
      return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }()

    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }
    context.interpolationQuality = .high
    if flattensAlpha {
      context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }

  /// Encodes `image` in the format implied by `fileExtension`, stamping DPI for `scale`
  /// so the next Optimize (and other apps) read the new density correctly. `quality`
  /// overrides the default for lossy formats.
  static func encode(_ image: CGImage, fileExtension: String, scale: CGFloat, quality: CGFloat? = nil) -> Data? {
    let ext = fileExtension.lowercased()
    if ext == "webp" {
      return WebPEncoderService.encode(image, quality: quality ?? webpQuality)
    }

    guard let type = ImageEncoderSupport.typeIdentifier(forExtension: ext),
          ImageEncoderSupport.canEncode(typeIdentifier: type) else {
      return nil
    }
    let utType = type as CFString

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, utType, 1, nil) else {
      return nil
    }
    CGImageDestinationAddImage(
      destination,
      image,
      destinationProperties(fileExtension: ext, scale: scale, quality: quality)
    )
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
  }

  /// Renders and encodes one level from the decoded original.
  static func render(
    _ level: QuickAccessOptimizeLevel,
    from original: CGImage,
    fileExtension: String
  ) -> Data? {
    guard let image = resized(original, width: level.pixelWidth, height: level.pixelHeight) else {
      return nil
    }
    return encode(image, fileExtension: fileExtension, scale: level.scale)
  }

  private static func destinationProperties(
    fileExtension: String,
    scale: CGFloat,
    quality: CGFloat?
  ) -> CFDictionary {
    let dpi = max(Double(scale), 0.25) * 72.0
    var properties: [CFString: Any] = [
      kCGImagePropertyDPIWidth: dpi,
      kCGImagePropertyDPIHeight: dpi,
    ]
    switch fileExtension {
    case "png":
      let pixelsPerMeter = Int((dpi / 0.0254).rounded())
      properties[kCGImagePropertyPNGDictionary] = [
        kCGImagePropertyPNGXPixelsPerMeter: pixelsPerMeter,
        kCGImagePropertyPNGYPixelsPerMeter: pixelsPerMeter,
      ] as CFDictionary
    case "jpg", "jpeg", "heic", "heif", "avif":
      properties[kCGImageDestinationLossyCompressionQuality] = quality ?? jpegQuality
    default:
      break
    }
    return properties as CFDictionary
  }
}
