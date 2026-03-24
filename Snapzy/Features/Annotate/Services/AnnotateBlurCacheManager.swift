//
//  BlurCacheManager.swift
//  Snapzy
//
//  Manages cached blur images for performance optimization
//

import AppKit
import CoreGraphics

/// Manages cached blur images for annotation items
/// Caches pixelated blur regions as CGImage to avoid per-frame recomputation
final class BlurCacheManager {
  private var cache: [UUID: CacheEntry] = [:]
  private let maxCachedPixelsPerBlur: CGFloat = 1_600_000

  private struct CacheEntry {
    let image: CGImage
    let bounds: CGRect
    let blurType: BlurType
    let pixelSize: CGFloat
    let sourceSignature: SourceSignature
    let cacheScale: CGFloat
  }

  private struct SourceSignature: Equatable {
    let pixelWidth: Int
    let pixelHeight: Int
    let pointWidth: Int
    let pointHeight: Int
  }

  /// Get or create cached blur image for annotation
  /// - Parameters:
  ///   - annotationId: The annotation's unique identifier
  ///   - bounds: The annotation bounds in image coordinates
  ///   - sourceImage: The source image to sample from
  ///   - blurType: The type of blur effect to apply
  ///   - pixelSize: Size of each pixel block for pixelated blur effect
  /// - Returns: Cached CGImage if available, or newly rendered image
  func getCachedBlur(
    for annotationId: UUID,
    bounds: CGRect,
    sourceImage: NSImage,
    blurType: BlurType = .pixelated,
    pixelSize: CGFloat = BlurEffectRenderer.defaultPixelSize,
    allowApproximateReuse: Bool = false
  ) -> CGImage? {
    let normalizedBounds = bounds.standardized
    let sourceSignature = makeSourceSignature(for: sourceImage)
    let cacheScale = renderScale(for: sourceImage, bounds: normalizedBounds)

    // Return cached if valid.
    // During interactive drag/resize we can temporarily reuse prior cache even if bounds changed,
    // then regenerate accurate cache once interaction ends.
    if let entry = cache[annotationId],
       entry.blurType == blurType,
       entry.pixelSize == pixelSize,
       entry.sourceSignature == sourceSignature,
       entry.cacheScale == cacheScale {
      if entry.bounds.equalTo(normalizedBounds) || allowApproximateReuse {
        return entry.image
      }
    }

    // If approximate reuse was requested but scale changed, still prefer old cache over re-render.
    if allowApproximateReuse, let entry = cache[annotationId],
       entry.blurType == blurType,
       entry.pixelSize == pixelSize,
       entry.sourceSignature == sourceSignature {
      return entry.image
    }

    // Render to offscreen context
    guard let rendered = renderBlurToImage(
      bounds: normalizedBounds,
      sourceImage: sourceImage,
      blurType: blurType,
      pixelSize: pixelSize,
      cacheScale: cacheScale
    ) else { return nil }

    cache[annotationId] = CacheEntry(
      image: rendered,
      bounds: normalizedBounds,
      blurType: blurType,
      pixelSize: pixelSize,
      sourceSignature: sourceSignature,
      cacheScale: cacheScale
    )
    return rendered
  }

  /// Invalidate cache for annotation (call on bounds change)
  func invalidate(id: UUID) {
    cache.removeValue(forKey: id)
  }

  /// Clear all cache (call on image change)
  func clearAll() {
    cache.removeAll()
  }

  /// Check if cache exists for annotation
  func hasCachedBlur(for annotationId: UUID) -> Bool {
    cache[annotationId] != nil
  }

  private func renderBlurToImage(
    bounds: CGRect,
    sourceImage: NSImage,
    blurType: BlurType,
    pixelSize: CGFloat,
    cacheScale: CGFloat
  ) -> CGImage? {
    let width = Int(ceil(bounds.width * cacheScale))
    let height = Int(ceil(bounds.height * cacheScale))
    guard width > 0, height > 0 else { return nil }

    // Create bitmap context
    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,  // Let CGContext calculate optimal row bytes
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Render in point space at higher pixel density for stable compositing.
    context.scaleBy(x: cacheScale, y: cacheScale)
    let localRegion = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)

    // Render blur using the original bounds for sampling, but draw at origin
    switch blurType {
    case .pixelated:
      BlurEffectRenderer.drawPixelatedRegion(
        in: context,
        sourceImage: sourceImage,
        sourceRegion: bounds,
        destRegion: localRegion,
        pixelSize: pixelSize
      )
    case .gaussian:
      BlurEffectRenderer.drawGaussianRegion(
        in: context,
        sourceImage: sourceImage,
        sourceRegion: bounds,
        destRegion: localRegion
      )
    }

    return context.makeImage()
  }

  private func makeSourceSignature(for sourceImage: NSImage) -> SourceSignature {
    let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    return SourceSignature(
      pixelWidth: cgImage?.width ?? Int(sourceImage.size.width),
      pixelHeight: cgImage?.height ?? Int(sourceImage.size.height),
      pointWidth: Int(sourceImage.size.width.rounded(.toNearestOrAwayFromZero)),
      pointHeight: Int(sourceImage.size.height.rounded(.toNearestOrAwayFromZero))
    )
  }

  private func renderScale(for sourceImage: NSImage, bounds: CGRect) -> CGFloat {
    guard sourceImage.size.width > 0,
          let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return 1
    }

    let baseScale = max(1, CGFloat(cgImage.width) / sourceImage.size.width)
    let requestedPixelArea = bounds.width * bounds.height * baseScale * baseScale
    guard requestedPixelArea > maxCachedPixelsPerBlur else { return baseScale }

    let areaScale = sqrt(maxCachedPixelsPerBlur / requestedPixelArea)
    let adaptiveScale = baseScale * areaScale
    return max(1, min(baseScale, adaptiveScale))
  }
}
