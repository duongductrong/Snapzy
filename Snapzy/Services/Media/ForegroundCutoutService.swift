//
//  ForegroundCutoutService.swift
//  Snapzy
//
//  Extracts foreground subjects with transparent background using Vision.
//

import AppKit
import CoreImage
import Vision

enum ForegroundAutoCropDecision: String, Codable, Sendable {
  case suggested
  case skippedNoOpaquePixels
  case skippedTouchesEdge
  case skippedSubjectTooSmall
  case skippedNotMeaningful
}

struct ForegroundAutoCropPolicy: Sendable {
  var alphaThreshold: UInt8 = 8
  var edgeInsetPixels: Int = 2
  var minimumSubjectDimensionPixels: Int = 24
  var minimumSubjectAreaRatio: CGFloat = 0.004
  var minimumReductionRatio: CGFloat = 0.08
  var paddingRatio: CGFloat = 0.01
  var minimumPaddingPixels: Int = 2
  var maximumPaddingPixels: Int = 16
}

struct ForegroundCutoutResult {
  let fullCanvasImage: CGImage
  let suggestedAutoCropRect: CGRect?
  let autoCropDecision: ForegroundAutoCropDecision
}

enum ForegroundCutoutError: LocalizedError {
  case unsupportedOS
  case noSubjectDetected
  case cutoutFailed(Error)
  case imageConversionFailed

  var errorDescription: String? {
    switch self {
    case .unsupportedOS:
      return L10n.ForegroundCutout.unsupportedOS
    case .noSubjectDetected:
      return L10n.ForegroundCutout.noSubjectDetected
    case .cutoutFailed(let error):
      return L10n.ForegroundCutout.cutoutFailed(error.localizedDescription)
    case .imageConversionFailed:
      return L10n.ForegroundCutout.imageConversionFailed
    }
  }
}

@MainActor
final class ForegroundCutoutService {

  static let shared = ForegroundCutoutService()

  private init() {}

  /// Extract foreground and evaluate whether auto-crop can be applied safely.
  /// - Parameters:
  ///   - image: Source image in display pixel coordinates.
  func extractForegroundResult(from image: CGImage) async throws -> ForegroundCutoutResult {
    try await extractForegroundResult(from: image, policy: ForegroundAutoCropPolicy())
  }

  /// Extract foreground and evaluate whether auto-crop can be applied safely.
  /// - Parameters:
  ///   - image: Source image in display pixel coordinates.
  ///   - policy: Heuristics used to decide if auto-crop is safe and meaningful.
  func extractForegroundResult(
    from image: CGImage,
    policy: ForegroundAutoCropPolicy
  ) async throws -> ForegroundCutoutResult {
    guard #available(macOS 14.0, *) else {
      throw ForegroundCutoutError.unsupportedOS
    }

    DiagnosticLogger.shared.log(
      .info,
      .capture,
      "Foreground cutout started",
      context: ["width": "\(image.width)", "height": "\(image.height)", "mode": "full-canvas+auto-crop-eval"]
    )

    do {
      let result = try await Task.detached(priority: .userInitiated) {
        try Self.extractForegroundResultSync(from: image, policy: policy)
      }.value

      DiagnosticLogger.shared.log(
        .info,
        .capture,
        "Foreground cutout completed",
        context: [
          "width": "\(result.fullCanvasImage.width)",
          "height": "\(result.fullCanvasImage.height)",
          "decision": result.autoCropDecision.rawValue,
          "hasSuggestedCrop": "\(result.suggestedAutoCropRect != nil)"
        ]
      )
      return result
    } catch let error as ForegroundCutoutError {
      DiagnosticLogger.shared.logError(.capture, error, "Foreground cutout failed")
      throw error
    } catch {
      DiagnosticLogger.shared.logError(.capture, error, "Foreground cutout failed")
      throw ForegroundCutoutError.cutoutFailed(error)
    }
  }

  /// Extract foreground objects from a screenshot/image.
  /// - Parameters:
  ///   - image: Source image in display pixel coordinates.
  ///   - cropToSubject: When true, trims transparent padding around detected subject bounds.
  func extractForeground(from image: CGImage, cropToSubject: Bool = false) async throws -> CGImage {
    guard #available(macOS 14.0, *) else {
      throw ForegroundCutoutError.unsupportedOS
    }

    DiagnosticLogger.shared.log(
      .info,
      .capture,
      "Foreground cutout started",
      context: ["width": "\(image.width)", "height": "\(image.height)", "crop": "\(cropToSubject)"]
    )

    do {
      let result = try await Task.detached(priority: .userInitiated) {
        try Self.extractForegroundSync(from: image, cropToSubject: cropToSubject)
      }.value

      DiagnosticLogger.shared.log(
        .info,
        .capture,
        "Foreground cutout completed",
        context: ["width": "\(result.width)", "height": "\(result.height)"]
      )
      return result
    } catch let error as ForegroundCutoutError {
      DiagnosticLogger.shared.logError(.capture, error, "Foreground cutout failed")
      throw error
    } catch {
      DiagnosticLogger.shared.logError(.capture, error, "Foreground cutout failed")
      throw ForegroundCutoutError.cutoutFailed(error)
    }
  }

  @available(macOS 14.0, *)
  private nonisolated static func extractForegroundSync(
    from image: CGImage,
    cropToSubject: Bool
  ) throws -> CGImage {
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: image, options: [:])

    do {
      try handler.perform([request])
    } catch {
      throw ForegroundCutoutError.cutoutFailed(error)
    }

    guard let observation = request.results?.first else {
      throw ForegroundCutoutError.noSubjectDetected
    }

    let instances = observation.allInstances
    guard !instances.isEmpty else {
      throw ForegroundCutoutError.noSubjectDetected
    }

    let maskedPixelBuffer: CVPixelBuffer
    do {
      maskedPixelBuffer = try observation.generateMaskedImage(
        ofInstances: instances,
        from: handler,
        croppedToInstancesExtent: cropToSubject
      )
    } catch {
      throw ForegroundCutoutError.cutoutFailed(error)
    }

    let ciImage = CIImage(cvPixelBuffer: maskedPixelBuffer)
    let extent = ciImage.extent.integral
    guard !extent.isEmpty else {
      throw ForegroundCutoutError.imageConversionFailed
    }

    let context = CIContext(options: nil)
    guard let output = context.createCGImage(ciImage, from: extent) else {
      throw ForegroundCutoutError.imageConversionFailed
    }

    return output
  }

  @available(macOS 14.0, *)
  private nonisolated static func extractForegroundResultSync(
    from image: CGImage,
    policy: ForegroundAutoCropPolicy
  ) throws -> ForegroundCutoutResult {
    let fullCanvasImage = try extractForegroundSync(from: image, cropToSubject: false)
    let (suggestedRect, decision) = evaluateAutoCropSuggestion(for: fullCanvasImage, policy: policy)
    return ForegroundCutoutResult(
      fullCanvasImage: fullCanvasImage,
      suggestedAutoCropRect: suggestedRect,
      autoCropDecision: decision
    )
  }

  private nonisolated static func evaluateAutoCropSuggestion(
    for image: CGImage,
    policy: ForegroundAutoCropPolicy
  ) -> (CGRect?, ForegroundAutoCropDecision) {
    guard let opaqueBounds = alphaBounds(in: image, alphaThreshold: policy.alphaThreshold) else {
      return (nil, .skippedNoOpaquePixels)
    }

    let imageWidth = CGFloat(image.width)
    let imageHeight = CGFloat(image.height)
    let totalArea = max(imageWidth * imageHeight, 1)
    let subjectArea = opaqueBounds.width * opaqueBounds.height

    if opaqueBounds.width < CGFloat(policy.minimumSubjectDimensionPixels) ||
        opaqueBounds.height < CGFloat(policy.minimumSubjectDimensionPixels) ||
        (subjectArea / totalArea) < policy.minimumSubjectAreaRatio {
      return (nil, .skippedSubjectTooSmall)
    }

    let edgeInset = CGFloat(policy.edgeInsetPixels)
    let touchesEdge = opaqueBounds.minX <= edgeInset ||
      opaqueBounds.minY <= edgeInset ||
      opaqueBounds.maxX >= imageWidth - edgeInset ||
      opaqueBounds.maxY >= imageHeight - edgeInset
    if touchesEdge {
      return (nil, .skippedTouchesEdge)
    }

    let shortestEdge = min(image.width, image.height)
    let adaptivePadding = Int(CGFloat(shortestEdge) * policy.paddingRatio)
    let padding = max(policy.minimumPaddingPixels, min(policy.maximumPaddingPixels, adaptivePadding))
    let paddedBounds = expanded(opaqueBounds, padding: padding, imageWidth: image.width, imageHeight: image.height)

    let widthReduction = 1 - (paddedBounds.width / imageWidth)
    let heightReduction = 1 - (paddedBounds.height / imageHeight)
    let areaReduction = 1 - ((paddedBounds.width * paddedBounds.height) / totalArea)
    let isMeaningful = widthReduction >= policy.minimumReductionRatio ||
      heightReduction >= policy.minimumReductionRatio ||
      areaReduction >= policy.minimumReductionRatio
    if !isMeaningful {
      return (nil, .skippedNotMeaningful)
    }

    return (paddedBounds.integral, .suggested)
  }

  private nonisolated static func expanded(
    _ rect: CGRect,
    padding: Int,
    imageWidth: Int,
    imageHeight: Int
  ) -> CGRect {
    guard padding > 0 else { return rect }
    let pad = CGFloat(padding)
    let expanded = rect.insetBy(dx: -pad, dy: -pad)
    let clamped = expanded.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
    return clamped.isNull ? rect : clamped
  }

  private nonisolated static func alphaBounds(in image: CGImage, alphaThreshold: UInt8) -> CGRect? {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }

    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    let didDraw = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
      guard let baseAddress = rawBuffer.baseAddress else { return false }
      guard let context = CGContext(
        data: baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      ) else {
        return false
      }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard didDraw else { return nil }

    var minX = width
    var minY = height
    var maxX = -1
    var maxY = -1

    for y in 0..<height {
      let rowOffset = y * bytesPerRow
      for x in 0..<width {
        let alpha = pixels[rowOffset + x * bytesPerPixel + 3]
        if alpha > alphaThreshold {
          minX = min(minX, x)
          minY = min(minY, y)
          maxX = max(maxX, x)
          maxY = max(maxY, y)
        }
      }
    }

    guard maxX >= 0, maxY >= 0 else { return nil }
    return CGRect(
      x: minX,
      y: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1
    )
  }
}
