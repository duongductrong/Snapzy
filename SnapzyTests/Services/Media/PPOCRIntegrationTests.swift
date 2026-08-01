//
//  PPOCRIntegrationTests.swift
//  SnapzyTests
//
//  Real-model end-to-end PP-OCR inference, gated by SNAPZY_PPOCR_MODEL_DIR.
//

import XCTest
@testable import Snapzy

/// Runs the full det+rec pipeline against real ONNX artifacts. Skipped unless
/// `SNAPZY_PPOCR_MODEL_DIR` points to a directory containing `det.onnx`,
/// `rec.onnx` and `dict.txt` — no network access when skipped.
final class PPOCRIntegrationTests: XCTestCase {

  private func modelDirectory() throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    guard let path = environment["SNAPZY_PPOCR_MODEL_DIR"], !path.isEmpty else {
      throw XCTSkip("SNAPZY_PPOCR_MODEL_DIR not set; skipping real-model PP-OCR test")
    }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    for file in ["det.onnx", "rec.onnx", "dict.txt"] {
      let fileURL = directory.appendingPathComponent(file)
      guard FileManager.default.fileExists(atPath: fileURL.path) else {
        throw XCTSkip("SNAPZY_PPOCR_MODEL_DIR is missing \(file); skipping")
      }
    }
    return directory
  }

  func testRecognizesRenderedHelloWorld() async throws {
    let directory = try modelDirectory()
    let image = try OCRTestImageRenderer.renderImage(text: "Hello World")
    // Unique modelID so the shared session cache never collides with other
    // tests or with an installed model of the same catalog id.
    let provider = PPOCRProvider(
      modelID: "integration-\(UUID().uuidString)",
      modelDirectory: directory
    )

    let result = try await provider.recognize(OCRRequest(image: image))

    XCTAssertEqual(result.engine, .ppOCR)
    XCTAssertFalse(result.lines.isEmpty)
    XCTAssertGreaterThan(result.averageConfidence, 0.5)
    XCTAssertTrue(
      result.text.localizedCaseInsensitiveContains("Hello"),
      "Expected recognized text to contain 'Hello', got: \(result.text)"
    )
  }
}
