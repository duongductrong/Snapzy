//
//  PPOCRProvider.swift
//  Snapzy
//
//  OCRProvider backed by a downloaded PP-OCR model via ONNX Runtime.
//

import CoreGraphics
import Foundation

/// `OCRProvider` running local PP-OCR det+rec inference for an installed
/// downloadable model. Non-isolated: the blocking ORT work runs on the
/// cooperative executor, off the main actor (`VisionOCRProvider` is the
/// `@MainActor` counterpart).
final class PPOCRProvider: OCRProvider, @unchecked Sendable {
  let engine: OCREngine = .ppOCR

  private let modelID: String
  private let modelDirectory: URL?
  private let sessionManager: PPOCRSessionManager

  init(
    modelID: String,
    modelDirectory: URL?,
    sessionManager: PPOCRSessionManager = .shared
  ) {
    self.modelID = modelID
    self.modelDirectory = modelDirectory
    self.sessionManager = sessionManager
  }

  func recognize(_ request: OCRRequest) async throws -> OCRResult {
    guard let modelDirectory else {
      throw PPOCRError.modelFilesMissing(modelID: modelID, file: "det.onnx")
    }

    let lines: [OCRTextLine]
    let coverage: OCRScriptCoverageReport
    do {
      let sessions = try sessionManager.sessions(modelID: modelID, directory: modelDirectory)
      coverage = sessions.coverage
      lines = try runInference(on: request.image, sessions: sessions)
    } catch let error as PPOCRError {
      throw error
    } catch let error as OCRError {
      throw error
    } catch {
      throw OCRError.recognitionFailed(error)
    }

    guard !lines.isEmpty else {
      DiagnosticLogger.shared.log(.warning, .ocr, "PP-OCR completed: no text found", context: ["model": modelID])
      throw OCRError.noTextFound
    }

    let averageConfidence = lines.map(\.confidence).reduce(0, +) / Float(lines.count)
    let incomplete = coverage.partiallySupported
    DiagnosticLogger.shared.log(.info, .ocr, "PP-OCR completed", context: [
      "model": modelID,
      "lines": "\(lines.count)",
      "confidence": String(format: "%.3f", averageConfidence),
      // Repeated per run so a bad result can be read against the model's
      // charset without going hunting for the session-creation log.
      "charsetGaps": incomplete.isEmpty ? "none" : incomplete.map(\.rawValue).joined(separator: ","),
    ])
    return OCRResult(
      engine: .ppOCR,
      profileID: modelID,
      text: lines.map(\.text).joined(separator: "\n"),
      lines: lines,
      averageConfidence: averageConfidence
    )
  }

  private func runInference(
    on image: CGImage,
    sessions: PPOCRModelSessions
  ) throws -> [OCRTextLine] {
    let boxes = try PPOCRDetector.detectBoxes(in: image, session: sessions.det)
    var lines: [OCRTextLine] = []
    for box in boxes {
      let (text, confidence) = try PPOCRRecognizer.recognize(
        box: box,
        in: image,
        session: sessions.rec,
        dictionary: sessions.dictionary
      )
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      lines.append(OCRTextLine(
        text: trimmed,
        confidence: confidence,
        boundingBox: Self.normalizedBoundingBox(for: box.rect, in: image)
      ))
    }
    return lines
  }

  /// Vision-compatible normalized bounding box (bottom-left origin), so
  /// downstream consumers (link detection, hit-testing) work unchanged.
  private static func normalizedBoundingBox(for rect: CGRect, in image: CGImage) -> CGRect {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    return CGRect(
      x: rect.minX / width,
      y: 1 - rect.maxY / height,
      width: rect.width / width,
      height: rect.height / height
    )
  }
}
