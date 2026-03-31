//
//  ForegroundCutoutService.swift
//  Snapzy
//
//  Extracts foreground subjects with transparent background using Vision.
//

import AppKit
import CoreImage
import Vision

enum ForegroundCutoutError: LocalizedError {
  case unsupportedOS
  case noSubjectDetected
  case cutoutFailed(Error)
  case imageConversionFailed

  var errorDescription: String? {
    switch self {
    case .unsupportedOS:
      return "Background cutout requires macOS 14 or newer."
    case .noSubjectDetected:
      return "No foreground subject was detected in the selected area."
    case .cutoutFailed(let error):
      return "Background cutout failed: \(error.localizedDescription)"
    case .imageConversionFailed:
      return "Unable to convert cutout result to image."
    }
  }
}

@MainActor
final class ForegroundCutoutService {

  static let shared = ForegroundCutoutService()

  private init() {}

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
}
