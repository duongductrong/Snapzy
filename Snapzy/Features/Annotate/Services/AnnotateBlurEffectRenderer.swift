//
//  BlurEffectRenderer.swift
//  Snapzy
//
//  Helper for rendering pixelated blur effect on image regions
//

import AppKit
import CoreGraphics
import CoreImage
import Metal

/// Renders pixelated blur effect for sensitive content redaction
struct BlurEffectRenderer {

  /// Default pixel block size for blur effect
  static let defaultPixelSize: CGFloat = 12

  /// Default Gaussian blur radius
  static let defaultGaussianRadius: Double = 20.0

  /// Security-first radius floor relative to smallest blur dimension
  private static let gaussianSecurityStrengthFactor: CGFloat = 0.35

  /// Sampling padding multiplier around target region
  private static let gaussianPaddingMultiplier: CGFloat = 2.0

  /// Hard cap to keep Gaussian cost bounded on very large regions
  private static let maxAdaptiveGaussianRadius: CGFloat = 120

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

  private struct RegionMapping {
    let imageScaleX: CGFloat
    let imageScaleY: CGFloat
    let clampedSourceRegion: CGRect
    let clampedDestRegion: CGRect
    let targetPixelRegion: CGRect
  }

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
    drawPixelatedRegion(
      in: context,
      sourceImage: sourceImage,
      sourceRegion: region,
      destRegion: region,
      pixelSize: pixelSize
    )
  }

  /// Draw a pixelated region by sampling from source region and drawing into destination region
  static func drawPixelatedRegion(
    in context: CGContext,
    sourceImage: NSImage,
    sourceRegion: CGRect,
    destRegion: CGRect,
    pixelSize: CGFloat = defaultPixelSize
  ) {
    guard sourceRegion.width > 0, sourceRegion.height > 0, destRegion.width > 0, destRegion.height > 0 else { return }

    guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      drawFallbackBlur(in: context, region: destRegion)
      return
    }

    guard let mapping = makeRegionMapping(
      sourceImage: sourceImage,
      cgImage: cgImage,
      sourceRegion: sourceRegion,
      destRegion: destRegion
    ) else {
      drawFallbackBlur(in: context, region: destRegion)
      return
    }

    guard let croppedImage = cgImage.cropping(to: mapping.targetPixelRegion) else {
      drawFallbackBlur(in: context, region: mapping.clampedDestRegion)
      return
    }

    drawPixelated(
      croppedImage: croppedImage,
      in: context,
      destRect: mapping.clampedDestRegion,
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
    let cols = Int(ceil(destRect.width / pixelSize))
    let rows = Int(ceil(destRect.height / pixelSize))
    guard cols > 0, rows > 0 else { return }

    let imageWidth = croppedImage.width
    let imageHeight = croppedImage.height
    guard let dataProvider = croppedImage.dataProvider,
          let data = dataProvider.data,
          let bytes = CFDataGetBytePtr(data) else {
      drawFallbackBlur(in: context, region: destRect)
      return
    }

    let bytesPerPixel = croppedImage.bitsPerPixel / 8
    let bytesPerRow = croppedImage.bytesPerRow

    context.saveGState()
    context.clip(to: destRect)
    context.setAllowsAntialiasing(false)
    context.setShouldAntialias(false)

    for row in 0..<rows {
      for col in 0..<cols {
        let sampleX = Int((CGFloat(col) + 0.5) / CGFloat(cols) * CGFloat(imageWidth))
        let sampleY = Int((CGFloat(row) + 0.5) / CGFloat(rows) * CGFloat(imageHeight))

        let clampedX = min(max(sampleX, 0), imageWidth - 1)
        let clampedY = min(max(sampleY, 0), imageHeight - 1)

        let offset = clampedY * bytesPerRow + clampedX * bytesPerPixel
        let r = CGFloat(bytes[offset]) / 255.0
        let g = CGFloat(bytes[offset + 1]) / 255.0
        let b = CGFloat(bytes[offset + 2]) / 255.0
        let a = bytesPerPixel >= 4 ? CGFloat(bytes[offset + 3]) / 255.0 : 1.0

        let blockX = destRect.origin.x + CGFloat(col) * pixelSize
        let blockY = destRect.origin.y + destRect.height - CGFloat(row + 1) * pixelSize
        let clampedMinX = max(blockX, destRect.minX)
        let clampedMaxX = min(blockX + pixelSize, destRect.maxX)
        let clampedMinY = max(blockY, destRect.minY)
        let clampedMaxY = min(blockY + pixelSize, destRect.maxY)
        guard clampedMaxX > clampedMinX, clampedMaxY > clampedMinY else { continue }
        let blockRect = CGRect(
          x: clampedMinX,
          y: clampedMinY,
          width: clampedMaxX - clampedMinX,
          height: clampedMaxY - clampedMinY
        )

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
    drawGaussianRegion(
      in: context,
      sourceImage: sourceImage,
      sourceRegion: region,
      destRegion: region,
      radius: radius
    )
  }

  /// Draw Gaussian blur by sampling from source region and drawing into destination region
  static func drawGaussianRegion(
    in context: CGContext,
    sourceImage: NSImage,
    sourceRegion: CGRect,
    destRegion: CGRect,
    radius: Double = defaultGaussianRadius
  ) {
    guard sourceRegion.width > 0, sourceRegion.height > 0, destRegion.width > 0, destRegion.height > 0 else { return }

    guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      drawFallbackBlur(in: context, region: destRegion)
      return
    }

    guard let mapping = makeRegionMapping(
      sourceImage: sourceImage,
      cgImage: cgImage,
      sourceRegion: sourceRegion,
      destRegion: destRegion
    ) else {
      drawFallbackBlur(in: context, region: destRegion)
      return
    }

    let targetPixelRegion = mapping.targetPixelRegion
    let effectiveRadiusPx = effectiveGaussianRadiusPixels(
      baseRadius: CGFloat(radius),
      imageScale: max(mapping.imageScaleX, mapping.imageScaleY),
      pixelRegion: targetPixelRegion
    )
    let samplePaddingPx = ceil(effectiveRadiusPx * gaussianPaddingMultiplier)
    let pixelBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
    let sampledPixelRegion = targetPixelRegion.insetBy(dx: -samplePaddingPx, dy: -samplePaddingPx).intersection(pixelBounds)

    guard !sampledPixelRegion.isEmpty,
          let sampledCGImage = cgImage.cropping(to: sampledPixelRegion) else {
      drawFallbackBlur(in: context, region: mapping.clampedDestRegion)
      return
    }

    let sampledCIImage = CIImage(cgImage: sampledCGImage)
    let clampedInput = sampledCIImage.clampedToExtent()
    let filter = CIFilter(name: "CIGaussianBlur")
    filter?.setValue(clampedInput, forKey: kCIInputImageKey)
    filter?.setValue(effectiveRadiusPx, forKey: kCIInputRadiusKey)
    guard let outputImage = filter?.outputImage else {
      drawFallbackBlur(in: context, region: mapping.clampedDestRegion)
      return
    }

    let croppedSampleOutput = outputImage.cropped(to: sampledCIImage.extent)
    let targetInSample = CGRect(
      x: targetPixelRegion.minX - sampledPixelRegion.minX,
      y: targetPixelRegion.minY - sampledPixelRegion.minY,
      width: targetPixelRegion.width,
      height: targetPixelRegion.height
    ).intersection(sampledCIImage.extent)
    guard !targetInSample.isEmpty else {
      drawFallbackBlur(in: context, region: mapping.clampedDestRegion)
      return
    }
    let croppedTargetOutput = croppedSampleOutput.cropped(to: targetInSample)

    guard let blurredCGImage = sharedCIContext.createCGImage(croppedTargetOutput, from: targetInSample) else {
      drawFallbackBlur(in: context, region: mapping.clampedDestRegion)
      return
    }

    context.saveGState()
    context.clip(to: mapping.clampedDestRegion)
    context.draw(blurredCGImage, in: mapping.clampedDestRegion)
    context.restoreGState()
  }

  private static func makeRegionMapping(
    sourceImage: NSImage,
    cgImage: CGImage,
    sourceRegion: CGRect,
    destRegion: CGRect
  ) -> RegionMapping? {
    guard sourceImage.size.width > 0, sourceImage.size.height > 0 else { return nil }

    let normalizedSourceRegion = sourceRegion.standardized
    let normalizedDestRegion = destRegion.standardized
    guard normalizedSourceRegion.width > 0, normalizedSourceRegion.height > 0,
          normalizedDestRegion.width > 0, normalizedDestRegion.height > 0 else { return nil }

    let imageBounds = CGRect(origin: .zero, size: sourceImage.size)
    let clampedSourceRegion = normalizedSourceRegion.intersection(imageBounds)
    guard !clampedSourceRegion.isEmpty else { return nil }

    let clampedDestRegion: CGRect
    if clampedSourceRegion.equalTo(normalizedSourceRegion) {
      clampedDestRegion = normalizedDestRegion
    } else {
      let scaleX = normalizedDestRegion.width / normalizedSourceRegion.width
      let scaleY = normalizedDestRegion.height / normalizedSourceRegion.height
      let offsetX = clampedSourceRegion.minX - normalizedSourceRegion.minX
      let offsetY = clampedSourceRegion.minY - normalizedSourceRegion.minY
      clampedDestRegion = CGRect(
        x: normalizedDestRegion.minX + offsetX * scaleX,
        y: normalizedDestRegion.minY + offsetY * scaleY,
        width: clampedSourceRegion.width * scaleX,
        height: clampedSourceRegion.height * scaleY
      )
    }

    let imageScaleX = CGFloat(cgImage.width) / sourceImage.size.width
    let imageScaleY = CGFloat(cgImage.height) / sourceImage.size.height
    let pixelBounds = CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))

    let pixelMinX = max(pixelBounds.minX, floor(clampedSourceRegion.minX * imageScaleX))
    let pixelMaxX = min(pixelBounds.maxX, ceil(clampedSourceRegion.maxX * imageScaleX))
    let pixelMinY = max(pixelBounds.minY, floor((sourceImage.size.height - clampedSourceRegion.maxY) * imageScaleY))
    let pixelMaxY = min(pixelBounds.maxY, ceil((sourceImage.size.height - clampedSourceRegion.minY) * imageScaleY))
    let targetPixelRegion = CGRect(
      x: pixelMinX,
      y: pixelMinY,
      width: pixelMaxX - pixelMinX,
      height: pixelMaxY - pixelMinY
    )

    guard !targetPixelRegion.isEmpty, targetPixelRegion.width >= 1, targetPixelRegion.height >= 1 else { return nil }

    return RegionMapping(
      imageScaleX: imageScaleX,
      imageScaleY: imageScaleY,
      clampedSourceRegion: clampedSourceRegion,
      clampedDestRegion: clampedDestRegion,
      targetPixelRegion: targetPixelRegion
    )
  }

  private static func effectiveGaussianRadiusPixels(
    baseRadius: CGFloat,
    imageScale: CGFloat,
    pixelRegion: CGRect
  ) -> CGFloat {
    let baseRadiusPx = max(1, baseRadius * imageScale)
    let minDimensionPx = min(pixelRegion.width, pixelRegion.height)
    let securityFloorPx = minDimensionPx * gaussianSecurityStrengthFactor
    let adaptiveRadiusPx = max(baseRadiusPx, securityFloorPx)
    let maxRegionRadiusPx = max(24, min(maxAdaptiveGaussianRadius, max(pixelRegion.width, pixelRegion.height) * 0.9))
    return min(adaptiveRadiusPx, maxRegionRadiusPx)
  }
}
