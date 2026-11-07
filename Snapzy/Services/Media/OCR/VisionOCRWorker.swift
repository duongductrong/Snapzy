//
//  VisionOCRWorker.swift
//  Snapzy
//
//  Off-main execution for the CPU-heavy parts of OCR: bitmap normalization,
//  Core Image filtering, and synchronous Vision requests.
//

import CoreGraphics
import CoreImage
import Foundation
import Vision

/// Dedicated GCD queue for blocking image/Vision work.
///
/// `VNImageRequestHandler.perform` is synchronous and can take hundreds of
/// milliseconds per pass (accurate recognition, several fallback profiles). Running it on
/// the main actor froze the UI; running it inside a Swift Task would pin a
/// cooperative-pool thread. A separate queue keeps both free.
nonisolated enum OCRWorkQueue {
  private static let queue = DispatchQueue(
    label: "com.snapzy.ocr.work",
    qos: .userInitiated,
    attributes: .concurrent
  )

  static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        continuation.resume(with: Result { try work() })
      }
    }
  }

  static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
      queue.async {
        continuation.resume(returning: work())
      }
    }
  }
}

/// Sendable snapshot of a `VisionOCRProfile`'s request settings.
nonisolated struct VisionRecognitionConfiguration: Sendable {
  let usesLanguageCorrection: Bool
  let recognitionLanguages: [String]
  let customWords: [String]
  let minimumTextHeight: Float?
  let automaticallyDetectsLanguage: Bool

  func configure(_ request: VNRecognizeTextRequest) {
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = usesLanguageCorrection
    if !recognitionLanguages.isEmpty {
      request.recognitionLanguages = recognitionLanguages
    }
    if !customWords.isEmpty {
      request.customWords = customWords
    }
    if let minimumTextHeight {
      request.minimumTextHeight = minimumTextHeight
    }
    if #available(macOS 13.0, *) {
      request.automaticallyDetectsLanguage = automaticallyDetectsLanguage
    }
  }
}

/// One recognized text candidate, detached from Vision's observation objects.
nonisolated struct VisionTextCandidate: Sendable {
  let string: String
  let confidence: Float
}

/// One recognized line with its top candidates (best first).
nonisolated struct VisionTextObservation: Sendable {
  let candidates: [VisionTextCandidate]
  let boundingBox: CGRect
}

nonisolated enum VisionOCRWorker {
  private static let ciContext = CIContext(options: [.cacheIntermediates: false])

  /// Runs one text-recognition request on the OCR work queue.
  static func recognizeText(
    in image: CGImage,
    configuration: VisionRecognitionConfiguration
  ) async throws -> [VisionTextObservation] {
    try await OCRWorkQueue.run {
      let request = VNRecognizeTextRequest()
      configuration.configure(request)
      let handler = VNImageRequestHandler(cgImage: image, options: [:])
      try handler.perform([request])
      return (request.results ?? []).map { observation in
        VisionTextObservation(
          candidates: observation.topCandidates(5).map {
            VisionTextCandidate(string: $0.string, confidence: $0.confidence)
          },
          boundingBox: observation.boundingBox
        )
      }
    }
  }

  /// Draw the image into a standard sRGB bitmap so Vision can read it.
  /// Fixes `TextRecognition.CRImageReaderError` on IOSurface-backed images from
  /// `SCScreenshotManager`. Returns nil when normalization is not possible.
  static func normalizedImageForVision(_ image: CGImage) -> CGImage? {
    let width = image.width
    let height = image.height
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? image.colorSpace ?? CGColorSpaceCreateDeviceRGB()

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

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }

  static func makeContrastEnhancedImage(from image: CGImage) -> CGImage? {
    let ciImage = CIImage(cgImage: image)

    guard
      let colorControls = CIFilter(name: "CIColorControls"),
      let sharpen = CIFilter(name: "CISharpenLuminance")
    else {
      return nil
    }

    colorControls.setValue(ciImage, forKey: kCIInputImageKey)
    colorControls.setValue(0, forKey: kCIInputSaturationKey)
    colorControls.setValue(1.32, forKey: kCIInputContrastKey)
    colorControls.setValue(0.02, forKey: kCIInputBrightnessKey)

    guard let normalizedImage = colorControls.outputImage?.cropped(to: ciImage.extent) else {
      return nil
    }

    sharpen.setValue(normalizedImage, forKey: kCIInputImageKey)
    sharpen.setValue(0.45, forKey: kCIInputSharpnessKey)

    guard let outputImage = sharpen.outputImage?.cropped(to: ciImage.extent) else {
      return nil
    }

    return ciContext.createCGImage(outputImage, from: ciImage.extent)
  }
}
