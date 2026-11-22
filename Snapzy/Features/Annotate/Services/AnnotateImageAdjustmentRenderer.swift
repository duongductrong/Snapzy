//
//  AnnotateImageAdjustmentRenderer.swift
//  Snapzy
//
//  Core Image pipeline for non-destructive image adjustments. Pure and thread-safe:
//  every entry point can run off the main actor.
//

import AppKit
import CoreImage

nonisolated enum AnnotateImageAdjustmentRenderer {
  /// One context for every render (contexts are thread-safe and expensive to create).
  private static let context = CIContext(options: [
    .cacheIntermediates: false,
    .name: "Snapzy.ImageAdjustments",
  ])

  /// Renders `adjustments` over `cgImage`.
  /// - Parameter maxPixelCount: when set and the image is larger, renders a downscaled
  ///   preview whose pixel count fits the budget (live preview on very long captures).
  /// - Returns: nil when Core Image fails; callers then keep showing the unadjusted image.
  static func render(
    _ cgImage: CGImage,
    adjustments: ImageAdjustments,
    maxPixelCount: Int? = nil
  ) -> CGImage? {
    let pixelCount = cgImage.width * cgImage.height
    var scale: CGFloat = 1
    if let maxPixelCount, maxPixelCount > 0, pixelCount > maxPixelCount {
      scale = sqrt(CGFloat(maxPixelCount) / CGFloat(pixelCount))
    }
    return render(cgImage, adjustments: adjustments, scale: scale, detailScale: scale)
  }

  /// Renders a thumbnail whose longest side is at most `maxDimension` pixels.
  static func renderThumbnail(
    _ cgImage: CGImage,
    adjustments: ImageAdjustments,
    maxDimension: CGFloat
  ) -> CGImage? {
    let longest = CGFloat(max(cgImage.width, cgImage.height))
    let scale = longest > maxDimension ? maxDimension / longest : 1
    return render(cgImage, adjustments: adjustments, scale: scale, detailScale: scale)
  }

  /// Downscales `cgImage` once to fit `maxPixelCount` (no adjustments) for live slider
  /// previews. Returns the bitmap and the scale it was rendered at (1 = untouched).
  static func makePreviewBase(_ cgImage: CGImage, maxPixelCount: Int) -> (image: CGImage, scale: CGFloat)? {
    let pixelCount = cgImage.width * cgImage.height
    guard maxPixelCount > 0, pixelCount > maxPixelCount else { return (cgImage, 1) }
    let scale = sqrt(CGFloat(maxPixelCount) / CGFloat(pixelCount))
    guard let image = render(cgImage, adjustments: .identity, scale: scale, detailScale: scale) else { return nil }
    return (image, scale)
  }

  /// Renders `adjustments` over an already downscaled bitmap. `detailScale` is the scale
  /// that bitmap was made at, so radius-based filters match the full-resolution result.
  static func renderPreview(_ cgImage: CGImage, adjustments: ImageAdjustments, detailScale: CGFloat) -> CGImage? {
    render(cgImage, adjustments: adjustments, scale: 1, detailScale: detailScale)
  }

  /// Wraps a rendered bitmap so it keeps the base image's point size (annotation space)
  /// whatever its pixel density.
  static func makeImage(_ cgImage: CGImage, pointSize: CGSize) -> NSImage {
    // A real bitmap rep keeps `AnnotateExporter`'s pixel-scale and DPI logic exact.
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = pointSize
    let image = NSImage(size: pointSize)
    image.addRepresentation(rep)
    return image
  }

  // MARK: - Pipeline

  private static func render(
    _ cgImage: CGImage,
    adjustments: ImageAdjustments,
    scale: CGFloat,
    detailScale: CGFloat
  ) -> CGImage? {
    let source = CIImage(cgImage: cgImage)
    var image = source
    if scale < 1 {
      image = image.samplingLinear().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
    let extent = image.extent.integral

    guard !adjustments.isIdentity || scale < 1 else { return cgImage }
    image = applyTone(adjustments, to: image)
    image = applyPreset(adjustments.preset, to: image)
    image = applySharpness(adjustments.sharpness, scale: detailScale, to: image, extent: extent)
    // No alpha re-masking: Core Image color filters work on unpremultiplied values and keep
    // alpha, so cutout edges stay intact (multiplying by the source alpha again would square it).

    let colorSpace = outputColorSpace(for: cgImage)
    let format: CIFormat = cgImage.bitsPerComponent > 8 ? .RGBA16 : .RGBA8
    return context.createCGImage(image.cropped(to: extent), from: extent, format: format, colorSpace: colorSpace)
  }

  /// Maps UI slider units onto `CIColorControls` ranges.
  private static func applyTone(_ adjustments: ImageAdjustments, to image: CIImage) -> CIImage {
    guard adjustments.hasToneChanges else { return image }
    // Brightness: ±100 → ±0.4 (CI's full ±1 washes everything out).
    let brightness = adjustments.brightness / 100 * 0.4
    // Contrast: -100…100 → 0.5…1.5 (1 = unchanged).
    let contrast = 1 + adjustments.contrast / 100 * 0.5
    // Saturation: -100…100 → 0…2 (0 = grayscale).
    let saturation = 1 + adjustments.saturation / 100
    return image.applyingFilter("CIColorControls", parameters: [
      kCIInputBrightnessKey: brightness,
      kCIInputContrastKey: contrast,
      kCIInputSaturationKey: saturation,
    ])
  }

  private static func applyPreset(_ preset: ImageFilterPreset, to image: CIImage) -> CIImage {
    switch preset {
    case .none:
      return image
    case .vivid:
      return image
        .applyingFilter("CIVibrance", parameters: ["inputAmount": 0.7])
        .applyingFilter("CIColorControls", parameters: [
          kCIInputSaturationKey: 1.1,
          kCIInputContrastKey: 1.05,
          kCIInputBrightnessKey: 0.0,
        ])
    case .mono:
      return image.applyingFilter("CIPhotoEffectMono")
    case .noir:
      return image.applyingFilter("CIPhotoEffectNoir")
    case .tonal:
      return image.applyingFilter("CIPhotoEffectTonal")
    case .sepia:
      return image.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.85])
    case .chrome:
      return image.applyingFilter("CIPhotoEffectChrome")
    case .fade:
      return image.applyingFilter("CIPhotoEffectFade")
    case .instant:
      return image.applyingFilter("CIPhotoEffectInstant")
    case .process:
      return image.applyingFilter("CIPhotoEffectProcess")
    case .transfer:
      return image.applyingFilter("CIPhotoEffectTransfer")
    }
  }

  /// Sharpness 0…100 → `CISharpenLuminance` 0…2. The radius follows the render scale so a
  /// downscaled preview looks like the full-resolution result.
  private static func applySharpness(_ sharpness: Double, scale: CGFloat, to image: CIImage, extent: CGRect) -> CIImage {
    guard sharpness > 0 else { return image }
    return image
      .clampedToExtent()
      .applyingFilter("CISharpenLuminance", parameters: [
        kCIInputSharpnessKey: sharpness / 100 * 2,
        kCIInputRadiusKey: max(0.5, 1.69 * Double(scale)),
      ])
      .cropped(to: extent)
  }

  private static func outputColorSpace(for cgImage: CGImage) -> CGColorSpace {
    if let colorSpace = cgImage.colorSpace, colorSpace.model == .rgb {
      return colorSpace
    }
    return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
  }
}
