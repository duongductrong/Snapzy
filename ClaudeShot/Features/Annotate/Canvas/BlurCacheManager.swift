//
//  BlurCacheManager.swift
//  ClaudeShot
//
//  Manages cached blur images for performance optimization
//

import AppKit
import CoreGraphics

/// Manages cached blur images for annotation items
/// Caches pixelated blur regions as CGImage to avoid per-frame recomputation
final class BlurCacheManager {
  private var cache: [UUID: CacheEntry] = [:]

  private struct CacheEntry {
    let image: CGImage
    let bounds: CGRect
  }

  /// Get or create cached blur image for annotation
  /// - Parameters:
  ///   - annotationId: The annotation's unique identifier
  ///   - bounds: The annotation bounds in image coordinates
  ///   - sourceImage: The source image to sample from
  ///   - pixelSize: Size of each pixel block for blur effect
  /// - Returns: Cached CGImage if available, or newly rendered image
  func getCachedBlur(
    for annotationId: UUID,
    bounds: CGRect,
    sourceImage: NSImage,
    pixelSize: CGFloat = BlurEffectRenderer.defaultPixelSize
  ) -> CGImage? {
    // Return cached if valid (same bounds)
    if let entry = cache[annotationId], entry.bounds == bounds {
      return entry.image
    }

    // Render to offscreen context
    guard let rendered = renderBlurToImage(
      bounds: bounds,
      sourceImage: sourceImage,
      pixelSize: pixelSize
    ) else { return nil }

    cache[annotationId] = CacheEntry(image: rendered, bounds: bounds)
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
    pixelSize: CGFloat
  ) -> CGImage? {
    let width = Int(ceil(bounds.width))
    let height = Int(ceil(bounds.height))
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

    // Create a temporary region at origin for rendering
    let localRegion = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)

    // Render blur using the original bounds for sampling, but draw at origin
    renderPixelatedRegion(
      in: context,
      sourceImage: sourceImage,
      sourceRegion: bounds,
      destRegion: localRegion,
      pixelSize: pixelSize
    )

    return context.makeImage()
  }

  /// Render pixelated region directly to context
  /// Similar to BlurEffectRenderer but optimized for cache rendering
  private func renderPixelatedRegion(
    in context: CGContext,
    sourceImage: NSImage,
    sourceRegion: CGRect,
    destRegion: CGRect,
    pixelSize: CGFloat
  ) {
    guard sourceRegion.width > 0, sourceRegion.height > 0 else { return }

    // Get CGImage from NSImage
    guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      drawFallbackBlur(in: context, region: destRegion)
      return
    }

    // Calculate image scale (NSImage size vs CGImage pixels)
    let imageScale = CGFloat(cgImage.width) / sourceImage.size.width

    // Convert region to pixel coordinates (flip Y for CGImage)
    let pixelRegion = CGRect(
      x: sourceRegion.origin.x * imageScale,
      y: (sourceImage.size.height - sourceRegion.origin.y - sourceRegion.height) * imageScale,
      width: sourceRegion.width * imageScale,
      height: sourceRegion.height * imageScale
    )

    // Clamp to image bounds
    let clampedPixelRegion = pixelRegion.intersection(
      CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
    )
    guard !clampedPixelRegion.isEmpty else {
      drawFallbackBlur(in: context, region: destRegion)
      return
    }

    // Crop the region from source image
    guard let croppedImage = cgImage.cropping(to: clampedPixelRegion) else {
      drawFallbackBlur(in: context, region: destRegion)
      return
    }

    // Draw pixelated version
    drawPixelated(
      croppedImage: croppedImage,
      in: context,
      destRect: destRegion,
      pixelSize: pixelSize
    )
  }

  /// Draw pixelated version of cropped image region
  private func drawPixelated(
    croppedImage: CGImage,
    in context: CGContext,
    destRect: CGRect,
    pixelSize: CGFloat
  ) {
    // Calculate grid dimensions
    let cols = Int(ceil(destRect.width / pixelSize))
    let rows = Int(ceil(destRect.height / pixelSize))

    guard cols > 0, rows > 0 else { return }

    // Sample colors from the cropped image
    let imageWidth = croppedImage.width
    let imageHeight = croppedImage.height

    // Create bitmap context to read pixel data
    guard let dataProvider = croppedImage.dataProvider,
          let data = dataProvider.data,
          let bytes = CFDataGetBytePtr(data) else {
      drawFallbackBlur(in: context, region: destRect)
      return
    }

    let bytesPerPixel = croppedImage.bitsPerPixel / 8
    let bytesPerRow = croppedImage.bytesPerRow

    // Draw each pixel block
    for row in 0..<rows {
      for col in 0..<cols {
        // Calculate sample position in image
        let sampleX = Int((CGFloat(col) + 0.5) / CGFloat(cols) * CGFloat(imageWidth))
        let sampleY = Int((CGFloat(row) + 0.5) / CGFloat(rows) * CGFloat(imageHeight))

        // Clamp to valid range
        let clampedX = min(max(sampleX, 0), imageWidth - 1)
        let clampedY = min(max(sampleY, 0), imageHeight - 1)

        // Get pixel color
        let offset = clampedY * bytesPerRow + clampedX * bytesPerPixel
        let r = CGFloat(bytes[offset]) / 255.0
        let g = CGFloat(bytes[offset + 1]) / 255.0
        let b = CGFloat(bytes[offset + 2]) / 255.0
        let a = bytesPerPixel >= 4 ? CGFloat(bytes[offset + 3]) / 255.0 : 1.0

        // Calculate block rect (flip Y for Core Graphics)
        let blockX = destRect.origin.x + CGFloat(col) * pixelSize
        let blockY = destRect.origin.y + destRect.height - CGFloat(row + 1) * pixelSize
        let blockWidth = min(pixelSize, destRect.maxX - blockX)
        let blockHeight = min(pixelSize, blockY + pixelSize - destRect.origin.y)

        let blockRect = CGRect(x: blockX, y: blockY, width: blockWidth, height: blockHeight)

        // Fill block with sampled color
        context.setFillColor(red: r, green: g, blue: b, alpha: a)
        context.fill(blockRect)
      }
    }
  }

  /// Fallback blur when image sampling fails
  private func drawFallbackBlur(in context: CGContext, region: CGRect) {
    context.setFillColor(NSColor.gray.withAlphaComponent(0.7).cgColor)
    context.fill(region)
  }
}
