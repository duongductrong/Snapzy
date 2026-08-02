//
//  OCRDynamicCatalogIntegrationTests.swift
//  SnapzyTests
//
//  Dynamic catalog download and failure-safe pruning coverage.
//

@testable import Snapzy
import XCTest

private final class DynamicCatalogDownloader: OCRModelDownloading, @unchecked Sendable {
  private(set) var downloadedModelID: String?

  func download(
    _ definition: OCRModelDefinition,
    to installDirectory: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    downloadedModelID = definition.id
    try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)
    for file in definition.files {
      try Data(file.name.utf8).write(to: installDirectory.appendingPathComponent(file.name))
    }
    progress(1)
  }
}

@MainActor
final class OCRDynamicCatalogIntegrationTests: XCTestCase {
  func testUserModelMergesAfterBundledModelsAndDownloadsThroughExistingStore() async throws {
    let defaults = UserDefaultsFactory.make()
    let userStore = OCRUserCatalogStore(defaults: defaults, reservedModelIDs: [])
    // Stock builds bundle no models; this fixture pins bundled-before-user order.
    let catalog = OCRCatalogFixtures.catalog(userStore: userStore)
    let downloader = DynamicCatalogDownloader()
    let installRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("OCRDynamicCatalogIntegrationTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: installRoot) }

    let manifest = makeManifest(id: "community-model")
    try userStore.add(manifest)

    XCTAssertEqual(catalog.entries.first?.source, .bundled)
    XCTAssertEqual(catalog.entries.last?.id, "community-model")
    XCTAssertEqual(catalog.entries.last?.source, .user)
    let modelStore = OCRModelStore(
      defaults: defaults,
      installRootURL: installRoot,
      downloadService: downloader,
      catalog: catalog
    )
    await modelStore.download(modelID: manifest.id).value

    XCTAssertEqual(downloader.downloadedModelID, manifest.id)
    XCTAssertEqual(modelStore.state(for: manifest.id), .installed)
    XCTAssertEqual(defaults.stringArray(forKey: PreferencesKeys.ocrInstalledModels), [manifest.id])
  }

  func testUnavailableBundledCatalogSkipsDestructiveInstallPruning() {
    let defaults = UserDefaultsFactory.make()
    defaults.set(["existing-model"], forKey: PreferencesKeys.ocrInstalledModels)
    defaults.set("dl:existing-model", forKey: PreferencesKeys.ocrSelectedModel)
    let userStore = OCRUserCatalogStore(defaults: defaults, reservedModelIDs: [])
    let failedLoad = OCRModelCatalogLoadResult(
      manifests: [],
      definitions: [],
      errorDescription: "fixture failure"
    )
    let catalog = OCRModelCatalog(bundledLoadResult: failedLoad, userStore: userStore)
    let store = OCRModelStore(defaults: defaults, installRootURL: nil, catalog: catalog)

    store.validateInstalledModelsOnLaunch()

    XCTAssertEqual(defaults.stringArray(forKey: PreferencesKeys.ocrInstalledModels), ["existing-model"])
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.ocrSelectedModel), "dl:existing-model")
    XCTAssertEqual(store.state(for: "existing-model"), .installed)
  }

  private func makeManifest(id: String) -> OCRModelManifest {
    let hash = String(repeating: "b", count: 64)
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
      displayName: "Community Model",
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
