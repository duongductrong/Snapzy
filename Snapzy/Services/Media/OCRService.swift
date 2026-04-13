//
//  OCRService.swift
//  Snapzy
//
//  Provides OCR text recognition using Vision framework
//

import AppKit
import Vision

/// Errors that can occur during OCR processing
enum OCRError: LocalizedError {
  case imageConversionFailed
  case noTextFound
  case recognitionFailed(Error)

  var errorDescription: String? {
    switch self {
    case .imageConversionFailed:
      return L10n.OCR.imageConversionFailed
    case .noTextFound:
      return L10n.OCR.noTextFound
    case .recognitionFailed(let error):
      return L10n.OCR.recognitionFailed(error.localizedDescription)
    }
  }
}

/// Service for performing OCR text recognition on images
@MainActor
final class OCRService {

  static let shared = OCRService()

  private init() {}

  // MARK: - Public API

  /// Recognize text from a CGImage
  /// - Parameter image: The image to extract text from
  /// - Returns: Recognized text joined by newlines
  func recognizeText(from image: CGImage) async throws -> String {
    DiagnosticLogger.shared.log(.info, .ocr, "OCR started", context: ["width": "\(image.width)", "height": "\(image.height)"])
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
      let request = VNRecognizeTextRequest { request, error in
        if let error = error {
          DiagnosticLogger.shared.logError(.ocr, error, "OCR recognition failed")
          continuation.resume(throwing: OCRError.recognitionFailed(error))
          return
        }

        guard let observations = request.results as? [VNRecognizedTextObservation] else {
          continuation.resume(throwing: OCRError.noTextFound)
          return
        }

        let recognizedStrings = observations.compactMap { observation in
          observation.topCandidates(1).first?.string
        }

        if recognizedStrings.isEmpty {
          DiagnosticLogger.shared.log(.warning, .ocr, "OCR completed: no text found")
          continuation.resume(throwing: OCRError.noTextFound)
        } else {
          let result = recognizedStrings.joined(separator: "\n")
          DiagnosticLogger.shared.log(.info, .ocr, "OCR completed", context: ["lines": "\(recognizedStrings.count)", "chars": "\(result.count)"])
          continuation.resume(returning: result)
        }
      }

      // Configure for best accuracy
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true

      let handler = VNImageRequestHandler(cgImage: image, options: [:])

      do {
        try handler.perform([request])
      } catch {
        DiagnosticLogger.shared.logError(.ocr, error, "OCR handler failed")
        continuation.resume(throwing: OCRError.recognitionFailed(error))
      }
    }
  }

  /// Recognize text from an NSImage
  /// - Parameter image: The NSImage to extract text from
  /// - Returns: Recognized text joined by newlines
  func recognizeText(from image: NSImage) async throws -> String {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      DiagnosticLogger.shared.log(.error, .ocr, "NSImage to CGImage conversion failed")
      throw OCRError.imageConversionFailed
    }
    return try await recognizeText(from: cgImage)
  }
}
