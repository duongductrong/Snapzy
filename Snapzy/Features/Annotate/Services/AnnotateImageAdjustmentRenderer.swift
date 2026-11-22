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

  /// Center-crops `cgImage` to `pixelSize`'s aspect ratio and downscales it to fill exactly
  /// that size (no adjustments): the shared base for filter preset thumbnails, so tiles are
  /// sharp at their display size instead of upscaling a letterboxed bitmap.
  static func makeThumbnailBase(_ cgImage: CGImage, pixelSize: CGSize) -> CGImage? {
    guard pixelSize.width > 0, pixelSize.height > 0, cgImage.width > 0, cgImage.height > 0 else { return nil }
    let source = CGSize(width: cgImage.width, height: cgImage.height)
    let targetAspect = pixelSize.width / pixelSize.height
    var crop = CGRect(origin: .zero, size: source)
    if source.width / source.height > targetAspect {
      crop.size.width = source.height * targetAspect
      crop.origin.x = (source.width - crop.width) / 2
    } else {
      crop.size.height = source.width / targetAspect
      crop.origin.y = (source.height - crop.height) / 2
    }
    crop = crop.integral.intersection(CGRect(origin: .zero, size: source))
    let scale = min(1, pixelSize.width / crop.width)
    let image = CIImage(cgImage: cgImage)
      .cropped(to: crop)
      .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
      .clampedToExtent()
      // Lanczos keeps big downscales (4K → ~200 px) free of aliasing; runs once per base.
      .applyingFilter("CILanczosScaleTransform", parameters: [
        kCIInputScaleKey: scale,
        kCIInputAspectRatioKey: 1.0,
      ])
    let extent = CGRect(origin: .zero, size: CGSize(
      width: (crop.width * scale).rounded(), height: (crop.height * scale).rounded()
    ))
    return context.createCGImage(
      image.cropped(to: extent), from: extent, format: .RGBA8, colorSpace: outputColorSpace(for: cgImage)
    )
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
    image = applyAdjustments(adjustments, to: image, detailScale: detailScale, extent: extent)
    // No alpha re-masking: Core Image color filters work on unpremultiplied values and keep
    // alpha, so cutout edges stay intact (multiplying by the source alpha again would square it).

    let colorSpace = outputColorSpace(for: cgImage)
    let format: CIFormat = cgImage.bitsPerComponent > 8 ? .RGBA16 : .RGBA8
    return context.createCGImage(image.cropped(to: extent), from: extent, format: format, colorSpace: colorSpace)
  }

  /// Full chain in a fixed order. Every stage is skipped at its neutral value, and the
  /// per-pixel color stages fuse into one GPU kernel, so only clarity (one blur) and
  /// sharpness add real cost.
  static func applyAdjustments(
    _ adjustments: ImageAdjustments,
    to input: CIImage,
    detailScale: CGFloat,
    extent: CGRect
  ) -> CIImage {
    var image = input
    image = applyExposure(adjustments.exposure, to: image)
    image = applyWhiteBalance(temperature: adjustments.temperature, tint: adjustments.tint, to: image)
    image = applyToneCurve(adjustments, to: image)
    image = applyColorControls(adjustments, to: image)
    image = applyVibrance(adjustments.vibrance, to: image)
    image = applyPreset(adjustments, to: image, detailScale: detailScale, extent: extent)
    image = applyClarity(adjustments.clarity, scale: detailScale, to: image, extent: extent)
    image = applySharpness(adjustments.sharpness, scale: detailScale, to: image, extent: extent)
    image = applyVignette(adjustments.vignette, to: image, extent: extent)
    return image
  }

  // MARK: - Light

  /// Exposure ±100 → ±2 EV.
  private static func applyExposure(_ exposure: Double, to image: CIImage) -> CIImage {
    guard exposure != 0 else { return image }
    return image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposure / 100 * 2])
  }

  /// Highlights, shadows, whites and blacks as one 5-point tone curve (one cheap per-pixel
  /// pass, works in both directions unlike `CIHighlightShadowAdjust`).
  private static func applyToneCurve(_ adjustments: ImageAdjustments, to image: CIImage) -> CIImage {
    guard adjustments.hasToneCurveChanges else { return image }
    let points = toneCurvePoints(adjustments)
    return image.applyingFilter("CIToneCurve", parameters: [
      "inputPoint0": CIVector(x: points[0].x, y: points[0].y),
      "inputPoint1": CIVector(x: points[1].x, y: points[1].y),
      "inputPoint2": CIVector(x: points[2].x, y: points[2].y),
      "inputPoint3": CIVector(x: points[3].x, y: points[3].y),
      "inputPoint4": CIVector(x: points[4].x, y: points[4].y),
    ])
  }

  /// Curve control points, strictly increasing in x and y for every slider combination.
  static func toneCurvePoints(_ adjustments: ImageAdjustments) -> [CGPoint] {
    let endpointReach = 0.2
    let midReach = 0.15
    // Blacks: + lifts the floor (matte), − crushes by moving the black point right.
    let blacks = adjustments.blacks / 100
    let p0 = blacks >= 0
      ? CGPoint(x: 0, y: blacks * endpointReach)
      : CGPoint(x: -blacks * endpointReach, y: 0)
    // Whites: + clips earlier by moving the white point left, − lowers the ceiling.
    let whites = adjustments.whites / 100
    let p4 = whites >= 0
      ? CGPoint(x: 1 - whites * endpointReach, y: 1)
      : CGPoint(x: 1, y: 1 + whites * endpointReach)
    let p1 = CGPoint(x: 0.25, y: 0.25 + adjustments.shadows / 100 * midReach)
    let p3 = CGPoint(x: 0.75, y: 0.75 + adjustments.highlights / 100 * midReach)
    let p2 = CGPoint(x: 0.5, y: 0.5 + (adjustments.shadows + adjustments.highlights) / 200 * midReach * 0.35)
    // Endpoint and mid sliders can pull against each other (Blacks +100 with Shadows −100):
    // keep y non-decreasing so tones never invert.
    var points = [p0, p1, p2, p3, p4]
    for index in 1 ..< points.count {
      points[index].y = max(points[index].y, points[index - 1].y + 0.01)
    }
    return points
  }

  /// Brightness/contrast/saturation mapped onto `CIColorControls` ranges.
  private static func applyColorControls(_ adjustments: ImageAdjustments, to image: CIImage) -> CIImage {
    guard adjustments.hasColorControlChanges else { return image }
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

  // MARK: - Color

  /// Temperature/tint as a white-balance shift from D65: a higher assumed neutral renders
  /// warmer, a positive tint offset renders more magenta.
  private static func applyWhiteBalance(temperature: Double, tint: Double, to image: CIImage) -> CIImage {
    guard temperature != 0 || tint != 0 else { return image }
    let t = temperature / 100
    // Asymmetric in Kelvin so both directions feel equally strong (≈3 500 K … 13 000 K).
    let neutralKelvin = t >= 0 ? 6500 + t * 6500 : 6500 + t * 3000
    return image.applyingFilter("CITemperatureAndTint", parameters: [
      "inputNeutral": CIVector(x: neutralKelvin, y: tint),
      "inputTargetNeutral": CIVector(x: 6500, y: 0),
    ])
  }

  /// Vibrance ±100 → `CIVibrance` ±1 (boosts muted colors more than saturated ones).
  private static func applyVibrance(_ vibrance: Double, to image: CIImage) -> CIImage {
    guard vibrance != 0 else { return image }
    return image.applyingFilter("CIVibrance", parameters: ["inputAmount": vibrance / 100])
  }

  // MARK: - Presets

  /// Applies the preset, then blends it over the unfiltered result by `presetIntensity`.
  private static func applyPreset(
    _ adjustments: ImageAdjustments,
    to image: CIImage,
    detailScale: CGFloat,
    extent: CGRect
  ) -> CIImage {
    guard adjustments.hasVisiblePreset else { return image }
    let filtered = presetImage(adjustments.preset, from: image, detailScale: detailScale, extent: extent)
    let intensity = adjustments.presetIntensity / 100
    guard intensity < 1 else { return filtered }
    return image.applyingFilter("CIDissolveTransition", parameters: [
      kCIInputTargetImageKey: filtered,
      kCIInputTimeKey: intensity,
    ])
  }

  private static func presetImage(
    _ preset: ImageFilterPreset,
    from image: CIImage,
    detailScale: CGFloat,
    extent: CGRect
  ) -> CIImage {
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
    case .warm:
      return applyVibrance(15, to: applyWhiteBalance(temperature: 35, tint: 4, to: image))
    case .cool:
      return applyVibrance(5, to: applyWhiteBalance(temperature: -35, tint: -3, to: image))
    case .dramatic:
      var dramatic = ImageAdjustments(contrast: 30, highlights: -25, shadows: -10, saturation: -15)
      dramatic.clarity = 45
      var result = applyToneCurve(dramatic, to: image)
      result = applyColorControls(dramatic, to: result)
      result = applyClarity(dramatic.clarity, scale: detailScale, to: result, extent: extent)
      return applyVignette(-35, to: result, extent: extent)
    case .matte:
      let matte = ImageAdjustments(contrast: -12, highlights: -15, whites: -18, blacks: 40, saturation: -12)
      return applyColorControls(matte, to: applyToneCurve(matte, to: image))
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

  // MARK: - Effects

  /// Clarity ±100: + wide-radius unsharp mask (local contrast), − blends toward a wide blur
  /// (`CIUnsharpMask` clamps negative intensity to 0). The radius follows the render scale so
  /// previews match the full-resolution result.
  private static func applyClarity(_ clarity: Double, scale: CGFloat, to image: CIImage, extent: CGRect) -> CIImage {
    guard clarity != 0 else { return image }
    let radius = max(1, 18 * Double(scale))
    if clarity > 0 {
      return image
        .clampedToExtent()
        .applyingFilter("CIUnsharpMask", parameters: [
          kCIInputRadiusKey: radius,
          kCIInputIntensityKey: clarity / 100 * 0.7,
        ])
        .cropped(to: extent)
    }
    let blurred = image
      .clampedToExtent()
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
      .cropped(to: extent)
    return image.applyingFilter("CIDissolveTransition", parameters: [
      kCIInputTargetImageKey: blurred,
      kCIInputTimeKey: -clarity / 100 * 0.5,
    ])
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

  /// Vignette ±100: − darkens, + lightens the corners. Sized from the extent so it is
  /// resolution independent.
  private static func applyVignette(_ vignette: Double, to image: CIImage, extent: CGRect) -> CIImage {
    guard vignette != 0, extent.width > 0, extent.height > 0 else { return image }
    let halfDiagonal = hypot(extent.width, extent.height) / 2
    return image.applyingFilter("CIVignetteEffect", parameters: [
      kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY),
      kCIInputRadiusKey: halfDiagonal * 0.85,
      kCIInputIntensityKey: -vignette / 100,
      "inputFalloff": 0.6,
    ])
  }

  private static func outputColorSpace(for cgImage: CGImage) -> CGColorSpace {
    if let colorSpace = cgImage.colorSpace, colorSpace.model == .rgb {
      return colorSpace
    }
    return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
  }
}
