//
//  OCRUserCatalogStoreTests.swift
//  SnapzyTests
//
//  User-defined downloadable OCR catalog persistence and merge coverage.
//

@testable import Snapzy
import XCTest

@MainActor
final class OCRUserCatalogStoreTests: XCTestCase {
  private var defaults: UserDefaults!
  private var invalidatedIDs: [String]!
  private var store: OCRUserCatalogStore!

  override func setUp() {
    super.setUp()
    defaults = UserDefaultsFactory.make()
    invalidatedIDs = []
    store = OCRUserCatalogStore(
      defaults: defaults,
      reservedModelIDs: ["bundled-model"]
    ) { [weak self] ids in
      self?.invalidatedIDs.append(contentsOf: ids)
    }
  }

  func testAddPersistsCanonicalCatalogJSONAndReloads() throws {
    let model = makeManifest(id: "user-model")

    try store.add(model)

    let data = try XCTUnwrap(defaults.data(forKey: PreferencesKeys.ocrUserCatalogModels))
    let decoded = try OCRUserCatalogStore.decodePersistedData(
      data,
      reservedModelIDs: ["bundled-model"]
    )
    XCTAssertEqual(decoded, [model])
    XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"schema_version\" : 1"))

    let reloaded = OCRUserCatalogStore(
      defaults: defaults,
      reservedModelIDs: ["bundled-model"]
    )
    XCTAssertEqual(reloaded.models, [model])
    XCTAssertNil(reloaded.loadErrorDescription)
  }

  func testDuplicateAndBundledIDsAreRejectedWithoutMutation() throws {
    let model = makeManifest(id: "user-model")
    try store.add(model)

    XCTAssertThrowsError(try store.add(model)) { error in
      XCTAssertEqual(error as? OCRUserCatalogStoreError, .duplicateModelID("user-model"))
    }
    XCTAssertThrowsError(try store.add(makeManifest(id: "bundled-model"))) { error in
      XCTAssertEqual(error as? OCRUserCatalogStoreError, .reservedModelID("bundled-model"))
    }
    XCTAssertEqual(store.models, [model])
  }

  func testUpdateInvalidatesOldInstallAndResetsActiveSelection() throws {
    let original = makeManifest(id: "user-model", displayName: "Original")
    try store.add(original)
    defaults.set("dl:user-model", forKey: PreferencesKeys.ocrSelectedModel)

    try store.update(makeManifest(id: "user-model", displayName: "Updated"))

    XCTAssertEqual(store.models.first?.displayName, "Updated")
    XCTAssertEqual(invalidatedIDs, ["user-model"])
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.ocrSelectedModel), "builtin")
  }

  func testMergeReplacesInPlaceAndAppendsNewModels() throws {
    try store.add(makeManifest(id: "first", displayName: "Old"))
    try store.add(makeManifest(id: "second"))
    invalidatedIDs.removeAll()

    try store.merge([
      makeManifest(id: "first", displayName: "New"),
      makeManifest(id: "third"),
    ])

    XCTAssertEqual(store.models.map(\.id), ["first", "second", "third"])
    XCTAssertEqual(store.models.first?.displayName, "New")
    XCTAssertEqual(invalidatedIDs, ["first"])
  }

  func testReplaceAndRemoveInvalidateDroppedModels() throws {
    try store.replaceAll(with: [makeManifest(id: "first"), makeManifest(id: "second")])
    invalidatedIDs.removeAll()

    try store.replaceAll(with: [makeManifest(id: "second")])
    store.remove(id: "second")

    XCTAssertEqual(invalidatedIDs, ["first", "second"])
    XCTAssertTrue(store.models.isEmpty)
    XCTAssertNil(defaults.data(forKey: PreferencesKeys.ocrUserCatalogModels))
  }

  func testCorruptPersistedCatalogIsPreservedAndReported() {
    let corrupt = Data("{not-json}".utf8)
    defaults.set(corrupt, forKey: PreferencesKeys.ocrUserCatalogModels)

    let reloaded = OCRUserCatalogStore(
      defaults: defaults,
      reservedModelIDs: ["bundled-model"]
    )

    XCTAssertTrue(reloaded.models.isEmpty)
    XCTAssertNotNil(reloaded.loadErrorDescription)
    XCTAssertEqual(defaults.data(forKey: PreferencesKeys.ocrUserCatalogModels), corrupt)
  }

  private func makeManifest(
    id: String,
    displayName: String = "User Model"
  ) -> OCRModelManifest {
    let hash = String(repeating: "a", count: 64)
    return OCRModelManifest(
      id: id,
      displayName: displayName,
      parameterCountLabel: "1M",
      fp32SizeLabel: "10 MB",
      int8SizeLabel: "3 MB",
      adapter: .ppocrDBCTCV1,
      artifacts: [
        artifact(.detector, "https://example.com/det.onnx", 100, hash),
        artifact(.recognizer, "https://example.com/rec.onnx", 200, hash),
        artifact(.dictionary, "https://example.com/dict.txt", nil, nil),
      ]
    )
  }

  private func artifact(
    _ role: OCRModelArtifactRole,
    _ url: String,
    _ bytes: Int64?,
    _ hash: String?
  ) -> OCRModelArtifactManifest {
    OCRModelArtifactManifest(
      role: role,
      source: OCRModelArtifactSourceManifest(
        type: .url,
        url: url,
        repository: nil,
        revision: nil,
        file: nil
      ),
      expectedBytes: bytes,
      sha256: hash
    )
  }
}
