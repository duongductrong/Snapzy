//
//  OCRProvider.swift
//  Snapzy
//
//  Pluggable OCR engine seam used by OCRService routing.
//

/// An OCR engine capable of recognizing text for an `OCRRequest`.
///
/// Implementations: `VisionOCRProvider` (built-in Apple Vision). PP-OCR
/// (Phase 3) and remote OpenAI-compatible endpoints (Phase 4) plug in behind
/// the same seam. Sendability/isolation is left to each implementation —
/// `VisionOCRProvider` is `@MainActor` like `OCRService`.
protocol OCRProvider {
  /// Engine identity stamped on produced `OCRResult`s.
  var engine: OCREngine { get }

  func recognize(_ request: OCRRequest) async throws -> OCRResult
}
