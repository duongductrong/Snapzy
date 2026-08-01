//
//  OCRCatalogModelDraftTests.swift
//  SnapzyTests
//
//  Manual downloadable-model form mapping coverage.
//

@testable import Snapzy
import XCTest

@MainActor
final class OCRCatalogModelDraftTests: XCTestCase {
  func testDraftBuildsValidatedDirectAndHuggingFaceSources() throws {
    let hash = String(repeating: "e", count: 64)
    var draft = OCRCatalogModelDraft()
    draft.id = "manual-model"
    draft.displayName = "Manual Model"
    draft.parameterCountLabel = "3M"
    draft.fp32SizeLabel = "14 MB"
    draft.int8SizeLabel = "5 MB"
    draft.detector = directArtifact(url: "https://example.com/det.onnx", bytes: "100", hash: hash)
    draft.recognizer = OCRCatalogArtifactDraft()
    draft.recognizer.sourceType = .huggingFace
    draft.recognizer.repository = "owner/model"
    draft.recognizer.revision = "main"
    draft.recognizer.file = "onnx/rec.onnx"
    draft.recognizer.expectedBytes = "200"
    draft.recognizer.sha256 = hash.uppercased()
    draft.dictionary = directArtifact(url: "https://example.com/dict.txt", bytes: "", hash: "")

    let model = try draft.manifest()
    let definition = try OCRCatalogManifestValidator.definition(from: model)

    XCTAssertEqual(model.id, "manual-model")
    XCTAssertEqual(model.artifacts[1].source.type, .huggingFace)
    XCTAssertEqual(model.artifacts[1].sha256, hash)
    XCTAssertEqual(
      definition.files[1].url.absoluteString,
      "https://huggingface.co/owner/model/resolve/main/onnx/rec.onnx"
    )
  }

  func testDraftRejectsInvalidExpectedBytesThroughSharedValidation() {
    let hash = String(repeating: "f", count: 64)
    var draft = OCRCatalogModelDraft()
    draft.id = "manual-model"
    draft.displayName = "Manual Model"
    draft.parameterCountLabel = "3M"
    draft.fp32SizeLabel = "14 MB"
    draft.int8SizeLabel = "5 MB"
    draft.detector = directArtifact(url: "https://example.com/det.onnx", bytes: "not-a-number", hash: hash)
    draft.recognizer = directArtifact(url: "https://example.com/rec.onnx", bytes: "200", hash: hash)
    draft.dictionary = directArtifact(url: "https://example.com/dict.txt", bytes: "", hash: "")

    XCTAssertThrowsError(try draft.manifest()) { error in
      XCTAssertTrue(error.localizedDescription.contains("expected_bytes"))
    }
  }

  private func directArtifact(
    url: String,
    bytes: String,
    hash: String
  ) -> OCRCatalogArtifactDraft {
    var artifact = OCRCatalogArtifactDraft()
    artifact.sourceType = .directURL
    artifact.url = url
    artifact.expectedBytes = bytes
    artifact.sha256 = hash
    return artifact
  }
}
