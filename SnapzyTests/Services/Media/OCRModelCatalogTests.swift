//
//  OCRModelCatalogTests.swift
//  SnapzyTests
//
//  Bundled catalog defaults, manifest loading, and fail-closed coverage.
//

@testable import Snapzy
import XCTest

final class OCRModelCatalogTests: XCTestCase {
  func testBundledYAMLCatalogLoadsSuccessfully() {
    XCTAssertTrue(
      OCRModelCatalog.isBundledCatalogAvailable,
      OCRModelCatalog.bundledCatalogError ?? "Bundled catalog unavailable"
    )
  }

  /// Snapzy bundles no model vendor: downloadable models only exist once the
  /// user supplies a manifest.
  func testBundledCatalogShipsEmpty() {
    XCTAssertTrue(OCRModelCatalog.bundledDefinitions.isEmpty)
    XCTAssertTrue(OCRModelCatalog.bundledModelIDs.isEmpty)
  }

  func testEmptyBundledCatalogIsAvailableAndNotAnError() {
    let result = OCRModelCatalog.load(
      Data("format: snapzy-ocr-catalog\nschema_version: 1\nmodels: []".utf8),
      fileExtension: "yaml"
    )

    XCTAssertTrue(result.isAvailable)
    XCTAssertNil(result.errorDescription)
    XCTAssertTrue(result.definitions.isEmpty)
    XCTAssertTrue(result.manifests.isEmpty)
  }

  func testCatalogYAMLWithModelsLoadsIntoDefinitions() {
    let result = OCRModelCatalog.load(
      Data(OCRCatalogFixtures.yaml(ids: ["first-model", "second-model"]).utf8),
      fileExtension: "yaml"
    )

    XCTAssertTrue(result.isAvailable, result.errorDescription ?? "")
    XCTAssertEqual(result.definitions.map(\.id), ["first-model", "second-model"])
    for definition in result.definitions {
      XCTAssertEqual(definition.files.map(\.name), ["det.onnx", "rec.onnx", "dict.txt"], definition.id)
      XCTAssertEqual(definition.adapterID, .ppocrDBCTCV1, definition.id)
      XCTAssertTrue(definition.files.allSatisfy { $0.url.scheme == "https" }, definition.id)
      XCTAssertEqual(definition.totalDownloadBytes, 300, definition.id)
    }
  }

  func testInvalidCatalogFailsClosedWithoutPartialDefinitions() {
    let source = "\(OCRCatalogFixtures.yaml(ids: ["good-model"]))\n\(Self.invalidTrailingModel)"
    let result = OCRModelCatalog.load(Data(source.utf8), fileExtension: "yaml")

    XCTAssertFalse(result.isAvailable)
    XCTAssertTrue(result.definitions.isEmpty)
    XCTAssertTrue(result.manifests.isEmpty)
    XCTAssertNotNil(result.errorDescription)
  }

  func testSingleModelDocumentIsRejectedAsBundledCatalog() {
    let source = OCRCatalogFixtures.yaml(ids: ["single-model"])
      .replacingOccurrences(of: "format: snapzy-ocr-catalog", with: "format: snapzy-ocr-model")
    let result = OCRModelCatalog.load(Data(source.utf8), fileExtension: "yaml")

    XCTAssertFalse(result.isAvailable)
    XCTAssertTrue(result.definitions.isEmpty)
  }

  func testDefinitionLookupMissReturnsNil() {
    XCTAssertNil(OCRModelCatalog.definition(for: "not-a-model"))
    XCTAssertNil(OCRModelCatalog.definition(for: ""))
  }

  private static let invalidTrailingModel = """
    - id: broken-model
      display_name: Broken Model
      parameter_count_label: 1M
      fp32_size_label: 10 MB
      int8_size_label: 3 MB
      adapter: ppocr-db-ctc-v1
      artifacts:
        - role: detector
          source:
            type: url
            url: "https://example.com/det.onnx"
          expected_bytes: 100
  """
}
