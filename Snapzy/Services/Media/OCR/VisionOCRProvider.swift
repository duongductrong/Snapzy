//
//  VisionOCRProvider.swift
//  Snapzy
//
//  Built-in Apple Vision OCR provider.
//

/// `OCRProvider` backed by the Apple Vision pipeline in `OCRService`.
@MainActor
struct VisionOCRProvider: OCRProvider {
  let engine: OCREngine = .vision

  func recognize(_ request: OCRRequest) async throws -> OCRResult {
    try await OCRService.shared.recognizeWithVision(request)
  }
}
