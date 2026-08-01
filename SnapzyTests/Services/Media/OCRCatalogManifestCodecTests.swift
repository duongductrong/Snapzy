//
//  OCRCatalogManifestCodecTests.swift
//  SnapzyTests
//
//  Strict JSON/YAML OCR manifest parsing and validation coverage.
//

@testable import Snapzy
import XCTest

@MainActor
final class OCRCatalogManifestCodecTests: XCTestCase {
  private let sha256 = String(repeating: "a", count: 64)

  func testJSONYAMLAndYMLDecodeToEquivalentDocuments() throws {
    let yaml = validYAML()
    let yamlDocument = try decode(yaml, extension: "yaml")
    let ymlDocument = try decode(yaml, extension: "yml")
    let jsonData = try OCRCatalogManifestCodec.encode(yamlDocument, format: .json)
    let jsonDocument = try OCRCatalogManifestCodec.decode(jsonData, fileExtension: "json")

    XCTAssertEqual(yamlDocument, ymlDocument)
    XCTAssertEqual(yamlDocument, jsonDocument)
  }

  func testYAMLAndJSONEncodingRoundTrip() throws {
    let original = try decode(validYAML(), extension: "yaml")

    for format in OCRModelManifestFormat.allCases {
      let encoded = try OCRCatalogManifestCodec.encode(original, format: format)
      let decoded = try OCRCatalogManifestCodec.decode(
        encoded,
        fileExtension: format == .json ? "json" : "yaml"
      )
      XCTAssertEqual(decoded, original, format.rawValue)
    }
  }

  func testEmptyCatalogRoundTripsForConfigurationReplaceSemantics() throws {
    let document = OCRModelManifestDocument.catalog([])

    for format in OCRModelManifestFormat.allCases {
      let data = try OCRCatalogManifestCodec.encode(document, format: format)
      XCTAssertEqual(
        try OCRCatalogManifestCodec.decode(
          data,
          fileExtension: format == .json ? "json" : "yaml"
        ),
        document
      )
    }
  }

  func testQuotedTextContainingAmpersandIsNotMistakenForYAMLAnchor() throws {
    let source = validYAML().replacingOccurrences(
      of: "display_name: Test Model",
      with: "display_name: 'Bob''s R&D Model'"
    )

    XCTAssertEqual(try decode(source, extension: "yaml").model?.displayName, "Bob's R&D Model")
  }

  func testHuggingFaceSourceResolvesToDownloadURL() throws {
    let document = try decode(validYAML(source: """
    type: hugging_face
    repository: owner/model
    revision: main
    file: onnx/detector.onnx
    """), extension: "yaml")

    let manifest = try XCTUnwrap(document.model)
    let definition = try OCRCatalogManifestValidator.definition(from: manifest)
    XCTAssertEqual(
      definition.files.first?.url.absoluteString,
      "https://huggingface.co/owner/model/resolve/main/onnx/detector.onnx"
    )
  }

  func testUnknownKeyIsRejected() {
    assertInvalid(validYAML().replacingOccurrences(
      of: "display_name: Test Model",
      with: "display_name: Test Model\n  surprise: true"
    ), contains: "unknown key")
  }

  func testDuplicateKeyIsRejected() {
    assertInvalid(validYAML().replacingOccurrences(
      of: "display_name: Test Model",
      with: "display_name: Test Model\n  display_name: Duplicate"
    ), contains: "duplicate key")
  }

  func testAliasesAreRejected() {
    let source = validYAML().replacingOccurrences(
      of: "display_name: Test Model",
      with: "display_name: &name Test Model"
    ).replacingOccurrences(
      of: "parameter_count_label: 1M",
      with: "parameter_count_label: *name"
    )
    assertInvalid(source, contains: "alias")
  }

  func testCustomTagsAreRejected() {
    assertInvalid(validYAML().replacingOccurrences(
      of: "display_name: Test Model",
      with: "display_name: !custom Test Model"
    ), contains: "tag")
  }

  func testMultipleDocumentsAreRejected() {
    assertInvalid(validYAML() + "\n---\nformat: snapzy-ocr-model\n", contains: "single document")
  }

  func testUnsupportedSchemaIsRejected() {
    assertInvalid(
      validYAML().replacingOccurrences(of: "schema_version: 1", with: "schema_version: 2"),
      contains: "unsupported schema_version"
    )
  }

  func testDuplicateModelIDsAreRejected() throws {
    let model = try XCTUnwrap(try decode(validYAML(), extension: "yaml").model)

    XCTAssertThrowsError(
      try OCRCatalogManifestValidator.validate(.catalog([model, model]))
    ) { error in
      XCTAssertTrue(error.localizedDescription.contains("duplicate model id"))
    }
  }

  func testUnsupportedAdapterIsRejected() {
    assertInvalid(
      validYAML().replacingOccurrences(of: "ppocr-db-ctc-v1", with: "unknown-adapter"),
      contains: "unknown-adapter"
    )
  }

  func testHTTPSourceIsRejected() {
    assertInvalid(
      validYAML().replacingOccurrences(of: "https://example.com", with: "http://example.com"),
      contains: "HTTPS"
    )
  }

  func testInvalidHashIsRejected() {
    assertInvalid(
      validYAML().replacingOccurrences(of: sha256, with: "ABC123"),
      contains: "SHA-256"
    )
  }

  func testMissingArtifactRoleIsRejected() {
    let source = validYAML()
    let dictionaryStart = source.range(of: "\n    - role: dictionary")
    let missingDictionary = dictionaryStart.map { String(source[..<$0.lowerBound]) } ?? source
    assertInvalid(
      missingDictionary,
      contains: "requires one detector"
    )
  }

  func testUnsafeHuggingFacePathIsRejected() {
    let source = """
    type: hugging_face
    repository: owner/model
    revision: main
    file: ../detector.onnx
    """
    assertInvalid(validYAML(source: source), contains: "safe relative file path")
  }

  func testUnsafeHuggingFaceRevisionIsRejected() {
    let source = """
    type: hugging_face
    repository: owner/model
    revision: ..
    file: detector.onnx
    """
    assertInvalid(validYAML(source: source), contains: "repository, revision")
  }

  func testUnsupportedExtensionAndOversizedFileAreRejected() {
    XCTAssertThrowsError(
      try OCRCatalogManifestCodec.decode(Data("{}".utf8), fileExtension: "toml")
    ) { error in
      XCTAssertEqual(error as? OCRModelManifestError, .unsupportedFileType("toml"))
    }

    let oversized = Data(repeating: 0, count: OCRCatalogManifestValidator.maximumManifestBytes + 1)
    XCTAssertThrowsError(
      try OCRCatalogManifestCodec.decode(oversized, fileExtension: "yaml")
    ) { error in
      XCTAssertEqual(error as? OCRModelManifestError, .fileTooLarge)
    }
  }

  func testURLDecodeStopsReadingAtManifestSizeLimit() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("oversized-ocr-manifest-\(UUID().uuidString).yaml")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(
      repeating: 0x61,
      count: OCRCatalogManifestValidator.maximumManifestBytes + 10_000
    ).write(to: url)

    XCTAssertThrowsError(try OCRCatalogManifestCodec.decode(contentsOf: url)) { error in
      XCTAssertEqual(error as? OCRModelManifestError, .fileTooLarge)
    }
  }

  private func decode(_ source: String, extension fileExtension: String) throws
    -> OCRModelManifestDocument {
    try OCRCatalogManifestCodec.decode(Data(source.utf8), fileExtension: fileExtension)
  }

  private func assertInvalid(
    _ source: String,
    extension fileExtension: String = "yaml",
    contains expectedText: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(
      try decode(source, extension: fileExtension),
      file: file,
      line: line
    ) { error in
      XCTAssertTrue(
        error.localizedDescription.localizedCaseInsensitiveContains(expectedText),
        "Expected \(error.localizedDescription) to contain \(expectedText)",
        file: file,
        line: line
      )
    }
  }

  private func validYAML(source: String? = nil) -> String {
    let detectorSource = source ?? """
    type: url
    url: https://example.com/det.onnx
    """
    return """
    format: snapzy-ocr-model
    schema_version: 1
    model:
      id: test-model
      display_name: Test Model
      parameter_count_label: 1M
      fp32_size_label: 12 MB
      int8_size_label: 4 MB
      adapter: ppocr-db-ctc-v1
      artifacts:
        - role: detector
          source:
    \(detectorSource.split(separator: "\n").map { "        " + $0 }.joined(separator: "\n"))
          expected_bytes: 123
          sha256: \(sha256)
        - role: recognizer
          source:
            type: url
            url: https://example.com/rec.onnx
          expected_bytes: 456
          sha256: \(sha256)
        - role: dictionary
          source:
            type: url
            url: https://example.com/dict.txt
    """
  }
}
