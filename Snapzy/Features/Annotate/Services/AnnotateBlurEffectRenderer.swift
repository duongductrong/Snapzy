//
//  BlurEffectRenderer.swift
//  Snapzy
//
//  Helper for rendering pixelated blur effect on image regions
//

import AppKit
import CoreGraphics

/// Renders pixelated blur effect for sensitive content redaction
struct BlurEffectRenderer {

  /// Default pixel block size for blur effect
  static let defaultPixelSize: CGFloat = 12

  /// Default Gaussian blur radius
  static let defaultGaussianRadius: Double = 20.0

  /// Shared GPU-backed CIContext for performance (reused across blur operations)
  static let sharedCIContext: CIContext = {
    if let metalDevice = MTLCreateSystemDefaultDevice() {
      return CIContext(mtlDevice: metalDevice, options: [
        .cacheIntermediates: true,
        .priorityRequestLow: false
      ])
    }
    return CIContext(options: [.cacheIntermediates: true])
  }()

  /// Draw a pixelated version of the source image region
  /// - Parameters:
  ///   - context: The graphics context to draw into
  ///   - sourceImage: The source image to sample from
  ///   - region: The region bounds in image coordinates
  ///   - pixelSize: Size of each pixel block (larger = more blur)
  static func drawPixelatedRegion(
    in context: CGContext,
    sourceImage: NSImage,
    region: CGRect,
    pixelSize: CGFloat = defaultPixelSize
  ) {
    // Ensure valid region
    guard region.width > 0, region.height > 0 else { return }

    // Get CGImage from NSImage
    guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      // Fallback: draw semi-transparent overlay
      drawFallbackBlur(in: context, region: region)
      return
    }

    // Clamp region to image bounds first (in image coordinate space)
    let imageBounds = CGRect(origin: .zero, size: sourceImage.size)
    let clampedRegion = region.intersection(imageBounds)
    guard !clampedRegion.isEmpty, clampedRegion.width > 0, clampedRegion.height > 0 else {
      drawFallbackBlur(in: context, region: region)
      return
    }

    // Calculate image scale (NSImage size vs CGImage pixels)
    let imageScale = CGFloat(cgImage.width) / sourceImage.size.width

    // Convert clamped region to pixel coordinates (flip Y for CGImage)
    let pixelRegion = CGRect(
      x: clampedRegion.origin.x * imageScale,
      y: (sourceImage.size.height - clampedRegion.origin.y - clampedRegion.height) * imageScale,
      width: clampedRegion.width * imageScale,
      height: clampedRegion.height * imageScale
    )

    // Clamp to pixel bounds (safety check for rounding)
    let clampedPixelRegion = pixelRegion.intersection(
      CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
    )
    guard !clampedPixelRegion.isEmpty else {
      drawFallbackBlur(in: context, region: region)
      return
    }

    // Crop the region from source image
    guard let croppedImage = cgImage.cropping(to: clampedPixelRegion) else {
      drawFallbackBlur(in: context, region: region)
      return
    }

    // Draw pixelated version using the clamped destination rect
    // This ensures source sampling and destination drawing are aligned
    drawPixelated(
      croppedImage: croppedImage,
      in: context,
      destRect: clampedRegion,
      pixelSize: pixelSize
    )
  }

  /// Draw pixelated version of cropped image region
  private static func drawPixelated(
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

    // Clip to destRect to prevent any pixel blocks from overflowing
    context.saveGState()
    context.clip(to: destRect)

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
        // Use ceil rounding so blocks start from top; clipping handles overflow
        let blockX = destRect.origin.x + CGFloat(col) * pixelSize
        let blockY = destRect.origin.y + destRect.height - CGFloat(row + 1) * pixelSize

        let blockRect = CGRect(x: blockX, y: blockY, width: pixelSize, height: pixelSize)

        // Fill block with sampled color (clipping prevents overflow)
        context.setFillColor(red: r, green: g, blue: b, alpha: a)
        context.fill(blockRect)
      }
    }

    context.restoreGState()
  }

  /// Fallback blur when image sampling fails - draws semi-transparent overlay
  private static func drawFallbackBlur(in context: CGContext, region: CGRect) {
    context.setFillColor(NSColor.gray.withAlphaComponent(0.7).cgColor)
    context.fill(region)
  }

  /// Draw blur preview during drag operation (simpler/faster)
  static func drawBlurPreview(
    in context: CGContext,
    region: CGRect,
    strokeColor: CGColor
  ) {
    // Draw semi-transparent overlay with pattern to indicate blur area
    context.setFillColor(NSColor.gray.withAlphaComponent(0.5).cgColor)
    context.fill(region)

    // Draw border
    context.setStrokeColor(strokeColor)
    context.setLineWidth(2)
    context.setLineDash(phase: 0, lengths: [6, 4])
    context.stroke(region)
    context.setLineDash(phase: 0, lengths: [])
  }

  /// Draw Gaussian blur region using CIFilter (GPU-accelerated)
  static func drawGaussianRegion(
    in context: CGContext,
    sourceImage: NSImage,
    region: CGRect,
    radius: Double = defaultGaussianRadius
  ) {
    guard region.width > 0, region.height > 0 else { return }

    guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      drawFallbackBlur(in: context, region: region)
      return
    }

    // Clamp region to image bounds first (in image coordinate space)
    let imageBounds = CGRect(origin: .zero, size: sourceImage.size)
    let clampedRegion = region.intersection(imageBounds)
    guard !clampedRegion.isEmpty, clampedRegion.width > 0, clampedRegion.height > 0 else {
      drawFallbackBlur(in: context, region: region)
      return
    }

    // Calculate image scale
    let imageScale = CGFloat(cgImage.width) / sourceImage.size.width

    // Convert clamped region to pixel coordinates (flip Y for CGImage)
    let pixelRegion = CGRect(
      x: clampedRegion.origin.x * imageScale,
      y: (sourceImage.size.height - clampedRegion.origin.y - clampedRegion.height) * imageScale,
      width: clampedRegion.width * imageScale,
      height: clampedRegion.height * imageScale
    )

    // Clamp to pixel bounds (safety check for rounding)
    let clampedPixelRegion = pixelRegion.intersection(
      CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
    )
    guard !clampedPixelRegion.isEmpty else {
      drawFallbackBlur(in: context, region: region)
      return
    }

    // Crop the region
    guard let croppedImage = cgImage.cropping(to: clampedPixelRegion) else {
      drawFallbackBlur(in: context, region: region)
      return
    }

    // Apply CIGaussianBlur
    let ciImage = CIImage(cgImage: croppedImage)
    let filter = CIFilter(name: "CIGaussianBlur")
    filter?.setValue(ciImage, forKey: kCIInputImageKey)
    filter?.setValue(radius, forKey: kCIInputRadiusKey)

    guard let outputImage = filter?.outputImage else {
      drawFallbackBlur(in: context, region: region)
      return
    }

    // Crop to original extent (blur expands the image)
    let croppedOutput = outputImage.cropped(to: ciImage.extent)

    guard let blurredCGImage = sharedCIContext.createCGImage(croppedOutput, from: ciImage.extent) else {
      drawFallbackBlur(in: context, region: region)
      return
    }

    // Draw using the clamped destination rect to match the clamped source
    context.draw(blurredCGImage, in: clampedRegion)
  }
}
