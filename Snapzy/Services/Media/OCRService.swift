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
      return "Failed to convert image for OCR processing"
    case .noTextFound:
      return "No text found in the selected area"
    case .recognitionFailed(let error):
      return "OCR recognition failed: \(error.localizedDescription)"
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
    try await withCheckedThrowingContinuation { continuation in
      let request = VNRecognizeTextRequest { request, error in
        if let error = error {
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
          continuation.resume(throwing: OCRError.noTextFound)
        } else {
          continuation.resume(returning: recognizedStrings.joined(separator: "\n"))
        }
      }

      // Configure for best accuracy
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true

      let handler = VNImageRequestHandler(cgImage: image, options: [:])

      do {
        try handler.perform([request])
      } catch {
        continuation.resume(throwing: OCRError.recognitionFailed(error))
      }
    }
  }

  /// Recognize text from an NSImage
  /// - Parameter image: The NSImage to extract text from
  /// - Returns: Recognized text joined by newlines
  func recognizeText(from image: NSImage) async throws -> String {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      throw OCRError.imageConversionFailed
    }
    return try await recognizeText(from: cgImage)
  }
}
