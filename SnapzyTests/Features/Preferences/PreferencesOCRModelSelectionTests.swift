//
//  PreferencesOCRModelSelectionTests.swift
//  SnapzyTests
//
//  Selection persistence rules for the OCR model list view model.
//

import XCTest
@testable import Snapzy

/// Fake installer: writes dummy model files instead of downloading them.
private final class FakeOCRModelDownloader: OCRModelDownloading, @unchecked Sendable {
  func download(
    _ definition: OCRModelDefinition,
    to installDirectory: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)
    for (index, file) in definition.files.enumerated() {
      try Data("fake \(file.name)".utf8).write(to: installDirectory.appendingPathComponent(file.name))
      progress(Double(index + 1) / Double(definition.files.count))
    }
  }
}

@MainActor
final class PreferencesOCRModelSelectionTests: XCTestCase {
  private var defaults: UserDefaults!
  private var installRoot: URL!
  private var modelStore: OCRModelStore!
  private var customStore: CustomOCRModelStore!
  private var userCatalogStore: OCRUserCatalogStore!
  private var catalog: OCRModelCatalog!
  private var viewModel: PreferencesOCRModelListViewModel!

  override func setUp() {
    super.setUp()
    defaults = UserDefaultsFactory.make()
    installRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("PreferencesOCRModelSelectionTests-\(UUID().uuidString)", isDirectory: true)
    customStore = CustomOCRModelStore(defaults: defaults, keychainStore: FakeOCRKeychainStore())
    userCatalogStore = OCRUserCatalogStore(defaults: defaults) { [weak self] ids in
      self?.modelStore?.invalidateCatalogModels(modelIDs: ids)
    }
    catalog = OCRModelCatalog(userStore: userCatalogStore)
    modelStore = OCRModelStore(
      defaults: defaults,
      installRootURL: installRoot,
      downloadService: FakeOCRModelDownloader(),
      catalog: catalog
    )
    viewModel = PreferencesOCRModelListViewModel(
      defaults: defaults,
      modelStore: modelStore,
      customModelStore: customStore,
      userCatalogStore: userCatalogStore,
      catalog: catalog
    )
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: installRoot)
    super.tearDown()
  }

  // MARK: - Helpers

  private func persistedSelection() -> String? {
    defaults.string(forKey: PreferencesKeys.ocrSelectedModel)
  }

  @discardableResult
  private func addCustomModel() -> CustomOCRModel {
    let model = CustomOCRModel(
      name: "Local Ollama",
      baseURL: "http://localhost:11434",
      modelIdentifier: "llava"
    )
    customStore.add(model)
    return model
  }

  // MARK: - Defaults

  func testDefaultSelectionIsBuiltIn() {
    XCTAssertEqual(viewModel.selection, .builtIn)
    XCTAssertNil(persistedSelection())
  }

  func testCorruptPersistedValueReadsAsBuiltIn() {
    defaults.set("bogus-value", forKey: PreferencesKeys.ocrSelectedModel)
    let viewModel = PreferencesOCRModelListViewModel(
      defaults: defaults,
      modelStore: modelStore,
      customModelStore: customStore
    )
    XCTAssertEqual(viewModel.selection, .builtIn)
  }

  // MARK: - Selection Rules

  func testSelectBuiltInPersistsImmediately() {
    viewModel.select(.builtIn)
    XCTAssertEqual(viewModel.selection, .builtIn)
    XCTAssertEqual(persistedSelection(), OCRModelSelection.builtIn.persistedValue)
  }

  func testSelectDownloadableWhileUninstalledIsNotPersisted() {
    viewModel.select(.downloadable("ppocrv6-tiny"))
    XCTAssertEqual(viewModel.selection, .builtIn)
    XCTAssertNil(persistedSelection())
  }

  func testSelectDownloadableOnceInstalledIsPersisted() async {
    await modelStore.download(modelID: "ppocrv6-tiny").value

    viewModel.select(.downloadable("ppocrv6-tiny"))

    XCTAssertEqual(viewModel.selection, .downloadable("ppocrv6-tiny"))
    XCTAssertEqual(persistedSelection(), "dl:ppocrv6-tiny")
  }

  func testSelectCustomModelIsPersisted() {
    let model = addCustomModel()

    viewModel.select(.custom(model.id))

    XCTAssertEqual(viewModel.selection, .custom(model.id))
    XCTAssertEqual(persistedSelection(), "custom:\(model.id.uuidString)")
  }

  func testSelectMissingCustomModelIsNotPersisted() {
    viewModel.select(.custom(UUID()))
    XCTAssertEqual(viewModel.selection, .builtIn)
    XCTAssertNil(persistedSelection())
  }

  // MARK: - Removal of the Active Model

  func testRemoveActiveDownloadableResetsSelectionToBuiltIn() async throws {
    await modelStore.download(modelID: "ppocrv6-tiny").value
    viewModel.select(.downloadable("ppocrv6-tiny"))
    let definition = try XCTUnwrap(OCRModelCatalog.definition(for: "ppocrv6-tiny"))

    viewModel.removeDownloadable(definition)

    XCTAssertEqual(viewModel.selection, .builtIn)
    XCTAssertEqual(persistedSelection(), OCRModelSelection.builtIn.persistedValue)
    XCTAssertEqual(modelStore.state(for: "ppocrv6-tiny"), .notInstalled)
  }

  func testRemoveInactiveDownloadableKeepsSelection() async throws {
    await modelStore.download(modelID: "ppocrv6-tiny").value
    let definition = try XCTUnwrap(OCRModelCatalog.definition(for: "ppocrv6-tiny"))

    viewModel.removeDownloadable(definition)

    XCTAssertEqual(viewModel.selection, .builtIn)
    XCTAssertNil(persistedSelection())
  }

  func testRemoveActiveCustomModelResetsSelectionToBuiltIn() {
    let model = addCustomModel()
    viewModel.select(.custom(model.id))

    viewModel.removeCustom(model)

    XCTAssertEqual(viewModel.selection, .builtIn)
    XCTAssertEqual(persistedSelection(), OCRModelSelection.builtIn.persistedValue)
    XCTAssertNil(customStore.model(for: model.id))
  }

  // MARK: - User Downloadable Catalog

  func testBundledCatalogEntriesRemainReadOnlyBySource() {
    XCTAssertFalse(catalog.entries.isEmpty)
    XCTAssertTrue(catalog.entries.allSatisfy { $0.source == .bundled })
  }

  func testImportYAMLAddsUserDownloadableModelAndExportsJSON() throws {
    let manifest = makeUserCatalogManifest(id: "community-model")
    let yaml = try OCRCatalogManifestCodec.encode(.singleModel(manifest), format: .yaml)

    XCTAssertEqual(try viewModel.importCatalog(yaml, fileExtension: "yml"), 1)
    XCTAssertEqual(userCatalogStore.models, [manifest])
    XCTAssertEqual(catalog.entry(for: manifest.id)?.source, .user)

    let exported = try viewModel.exportCatalog(format: .json)
    let document = try OCRCatalogManifestCodec.decode(exported, fileExtension: "json")
    XCTAssertEqual(document.models, [manifest])
  }

  func testRemoveUserDownloadableModelDeletesInstallAndResetsSelection() async throws {
    let manifest = makeUserCatalogManifest(id: "community-model")
    try userCatalogStore.add(manifest)
    await modelStore.download(modelID: manifest.id).value
    viewModel.select(.downloadable(manifest.id))
    let entry = try XCTUnwrap(catalog.entry(for: manifest.id))

    viewModel.removeUserCatalogModel(entry)

    XCTAssertNil(userCatalogStore.model(for: manifest.id))
    XCTAssertNil(catalog.entry(for: manifest.id))
    XCTAssertEqual(modelStore.state(for: manifest.id), .notInstalled)
    XCTAssertEqual(viewModel.selection, .builtIn)
    XCTAssertEqual(persistedSelection(), "builtin")
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: installRoot.appendingPathComponent(manifest.id).path
    ))
  }

  func testEditingUserDefinitionInvalidatesPreviouslyInstalledArtifacts() async throws {
    let manifest = makeUserCatalogManifest(id: "community-model", displayName: "Old")
    try userCatalogStore.add(manifest)
    await modelStore.download(modelID: manifest.id).value

    try userCatalogStore.update(makeUserCatalogManifest(
      id: manifest.id,
      displayName: "Updated"
    ))

    XCTAssertEqual(catalog.entry(for: manifest.id)?.definition.displayName, "Updated")
    XCTAssertEqual(modelStore.state(for: manifest.id), .notInstalled)
    XCTAssertEqual(defaults.stringArray(forKey: PreferencesKeys.ocrInstalledModels) ?? [], [])
  }

  private func makeUserCatalogManifest(
    id: String,
    displayName: String = "Community Model"
  ) -> OCRModelManifest {
    let hash = String(repeating: "d", count: 64)
    func artifact(
      _ role: OCRModelArtifactRole,
      _ path: String,
      _ bytes: Int64?,
      _ hash: String?
    ) -> OCRModelArtifactManifest {
      OCRModelArtifactManifest(
        role: role,
        source: OCRModelArtifactSourceManifest(
          type: .url,
          url: "https://example.com/\(path)",
          repository: nil,
          revision: nil,
          file: nil
        ),
        expectedBytes: bytes,
        sha256: hash
      )
    }
    return OCRModelManifest(
      id: id,
      displayName: displayName,
      parameterCountLabel: "2M",
      fp32SizeLabel: "12 MB",
      int8SizeLabel: "4 MB",
      adapter: .ppocrDBCTCV1,
      artifacts: [
        artifact(.detector, "det.onnx", 100, hash),
        artifact(.recognizer, "rec.onnx", 200, hash),
        artifact(.dictionary, "dict.txt", nil, nil),
      ]
    )
  }
}
