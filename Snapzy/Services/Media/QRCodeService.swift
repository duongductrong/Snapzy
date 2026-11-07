//
//  QRCodeService.swift
//  Snapzy
//
//  Provides local QR payload extraction using Vision barcode detection.
//

import CoreGraphics
import Foundation
import Vision

nonisolated final class QRCodeService: Sendable {
  static let shared = QRCodeService()

  private init() {}

  /// Runs barcode detection on the OCR work queue so the synchronous Vision
  /// call never blocks the main thread or a Swift cooperative-pool thread.
  func detect(in image: CGImage) async throws -> QRCodeDetectionResult {
    try await OCRWorkQueue.run { try Self.detectSynchronously(in: image) }
  }

  private static func detectSynchronously(in image: CGImage) throws -> QRCodeDetectionResult {
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    var unsupportedPayloadCount = 0
    let detections = (request.results ?? []).compactMap { observation -> QRCodeDetection? in
      guard observation.symbology == .qr else { return nil }
      guard let payload = observation.payloadStringValue else {
        unsupportedPayloadCount += 1
        return nil
      }

      let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedPayload.isEmpty else { return nil }

      return QRCodeDetection(
        payload: payload,
        boundingBox: observation.boundingBox,
        classification: QRPayloadClassifier.classify(payload)
      )
    }

    return QRCodeDetectionResult(
      detections: sortInReadingOrder(deduplicate(detections)),
      unsupportedPayloadCount: unsupportedPayloadCount
    )
  }

  private static func deduplicate(_ detections: [QRCodeDetection]) -> [QRCodeDetection] {
    var seen = Set<String>()
    var unique: [QRCodeDetection] = []

    for detection in detections {
      if seen.insert(detection.payload).inserted {
        unique.append(detection)
      }
    }

    return unique
  }

  private static func sortInReadingOrder(_ detections: [QRCodeDetection]) -> [QRCodeDetection] {
    detections.sorted { lhs, rhs in
      let verticalDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
      let rowTolerance = max(lhs.boundingBox.height, rhs.boundingBox.height) * 0.6
      if verticalDelta > rowTolerance {
        return lhs.boundingBox.maxY > rhs.boundingBox.maxY
      }
      return lhs.boundingBox.minX < rhs.boundingBox.minX
    }
  }
}
