//
//  OCRModelStoreTests.swift
//  SnapzyTests
//
//  Install-state transitions, persistence, and launch validation coverage.
//

import XCTest
@testable import Snapzy

/// Fake installer: writes dummy model files instead of downloading them.
private final class FakeOCRModelDownloader: OCRModelDownloading, @unchecked Sendable {
  var error: Error?

  func download(
    _ definition: OCRModelDefinition,
    to installDirectory: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    if let error { throw error }
    try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)
    for (index, file) in definition.files.enumerated() {
      try Data("fake \(file.name)".utf8).write(to: installDirectory.appendingPathComponent(file.name))
      progress(Double(index + 1) / Double(definition.files.count))
    }
  }
}

/// Fake installer that counts invocations and takes its time, so tests can
/// fire a second `download(modelID:)` while the first is in flight.
private final class CountingOCRModelDownloader: OCRModelDownloading, @unchecked Sendable {
  private let lock = NSLock()
  private var _downloadCount = 0

  var downloadCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return _downloadCount
  }

  func download(
    _ definition: OCRModelDefinition,
    to installDirectory: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    lock.lock()
    _downloadCount += 1
    lock.unlock()
    try await Task.sleep(nanoseconds: 200_000_000)
    try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)
    for file in definition.files {
      try Data("fake \(file.name)".utf8).write(to: installDirectory.appendingPathComponent(file.name))
    }
    progress(1.0)
  }
}

/// Fake installer that runs a callback after writing the files, simulating
/// the verify/move window where a remove can land.
private final class CallbackOCRModelDownloader: OCRModelDownloading, @unchecked Sendable {
  var beforeReturn: (@Sendable () async -> Void)?

  func download(
    _ definition: OCRModelDefinition,
    to installDirectory: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)
    for file in definition.files {
      try Data("fake \(file.name)".utf8).write(to: installDirectory.appendingPathComponent(file.name))
    }
    progress(1.0)
    await beforeReturn?()
  }
}

private let primaryID = OCRCatalogFixtures.primaryModelID
private let secondaryID = OCRCatalogFixtures.secondaryModelID

@MainActor
final class OCRModelStoreTests: XCTestCase {
  private var defaults: UserDefaults!
  private var installRoot: URL!
  private var downloader: FakeOCRModelDownloader!
  private var catalog: OCRModelCatalog!
  private var store: OCRModelStore!

  override func setUp() {
    super.setUp()
    defaults = UserDefaultsFactory.make()
    installRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("OCRModelStoreTests-\(UUID().uuidString)", isDirectory: true)
    downloader = FakeOCRModelDownloader()
    // The bundled catalog ships empty, so these tests supply their own models.
    catalog = OCRCatalogFixtures.catalog(defaults: defaults)
    store = OCRModelStore(
      defaults: defaults,
      installRootURL: installRoot,
      downloadService: downloader,
      catalog: catalog
    )
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: installRoot)
    super.tearDown()
  }

  // MARK: - Download

  func testInitialStateIsNotInstalled() {
    XCTAssertEqual(store.state(for: primaryID), .notInstalled)
  }

  func testDownloadInstallsModelAndPersistsInstalledID() async {
    await store.download(modelID: primaryID).value

    XCTAssertEqual(store.state(for: primaryID), .installed)
    XCTAssertEqual(defaults.stringArray(forKey: PreferencesKeys.ocrInstalledModels), [primaryID])
    for file in ["det.onnx", "rec.onnx", "dict.txt"] {
      let url = installRoot.appendingPathComponent("\(primaryID)/\(file)")
      XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), file)
    }
  }

  func testFailedDownloadStoresFailureState() async {
    downloader.error = OCRModelDownloadError.network("offline")

    await store.download(modelID: primaryID).value

    guard case .failed = store.state(for: primaryID) else {
      return XCTFail("expected failed state")
    }
    XCTAssertEqual(defaults.stringArray(forKey: PreferencesKeys.ocrInstalledModels) ?? [], [])
  }

  func testCancelledDownloadResetsToNotInstalled() async {
    downloader.error = OCRModelDownloadError.cancelled

    await store.download(modelID: primaryID).value

    XCTAssertEqual(store.state(for: primaryID), .notInstalled)
    XCTAssertEqual(defaults.stringArray(forKey: PreferencesKeys.ocrInstalledModels) ?? [], [])
  }

  // MARK: - Download Races

  func testDuplicateDownloadInvocationRunsDownloadOnce() async {
    let counting = CountingOCRModelDownloader()
    let countingStore = OCRModelStore(
      defaults: defaults,
      installRootURL: installRoot,
      downloadService: counting,
      catalog: catalog
    )

    let first = countingStore.download(modelID: primaryID)
    let second = countingStore.download(modelID: primaryID)
    await first.value
    await second.value

    XCTAssertEqual(counting.downloadCount, 1)
    XCTAssertEqual(countingStore.state(for: primaryID), .installed)
  }

  func testRemoveDuringFinalizeWinsOverMarkInstalled() async {
    let callback = CallbackOCRModelDownloader()
    let callbackStore = OCRModelStore(
      defaults: defaults,
      installRootURL: installRoot,
      downloadService: callback,
      catalog: catalog
    )
    callback.beforeReturn = { @MainActor in
      callbackStore.removeModel(modelID: primaryID)
    }

    await callbackStore.download(modelID: primaryID).value

    XCTAssertEqual(callbackStore.state(for: primaryID), .notInstalled)
    XCTAssertEqual(defaults.stringArray(forKey: PreferencesKeys.ocrInstalledModels) ?? [], [])
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: installRoot.appendingPathComponent(primaryID).path)
    )
  }

  // MARK: - Removal

  func testRemoveModelDeletesDirectoryAndUpdatesState() async {
    await store.download(modelID: primaryID).value

    store.removeModel(modelID: primaryID)

    XCTAssertEqual(store.state(for: primaryID), .notInstalled)
    XCTAssertEqual(defaults.stringArray(forKey: PreferencesKeys.ocrInstalledModels) ?? [], [])
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: installRoot.appendingPathComponent(primaryID).path)
    )
  }

  // MARK: - Launch Validation

  func testValidateOnLaunchPrunesMissingInstallAndResetsSelection() {
    defaults.set([primaryID], forKey: PreferencesKeys.ocrInstalledModels)
    defaults.set("dl:\(primaryID)", forKey: PreferencesKeys.ocrSelectedModel)

    store.validateInstalledModelsOnLaunch()

    XCTAssertEqual(store.state(for: primaryID), .notInstalled)
    XCTAssertEqual(defaults.stringArray(forKey: PreferencesKeys.ocrInstalledModels) ?? [], [])
    XCTAssertEqual(
      defaults.string(forKey: PreferencesKeys.ocrSelectedModel),
      OCRModelSelection.builtIn.persistedValue
    )
  }

  func testValidateOnLaunchKeepsCompleteInstallAndSelection() async {
    await store.download(modelID: primaryID).value
    defaults.set("dl:\(primaryID)", forKey: PreferencesKeys.ocrSelectedModel)

    store.validateInstalledModelsOnLaunch()

    XCTAssertEqual(store.state(for: primaryID), .installed)
    XCTAssertEqual(defaults.stringArray(forKey: PreferencesKeys.ocrInstalledModels), [primaryID])
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.ocrSelectedModel), "dl:\(primaryID)")
  }

  func testValidateOnLaunchPrunesPartiallyDownloadedInstall() throws {
    let directory = installRoot.appendingPathComponent(primaryID, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("partial".utf8).write(to: directory.appendingPathComponent("det.onnx"))
    defaults.set([primaryID], forKey: PreferencesKeys.ocrInstalledModels)

    store.validateInstalledModelsOnLaunch()

    XCTAssertEqual(defaults.stringArray(forKey: PreferencesKeys.ocrInstalledModels) ?? [], [])
    XCTAssertEqual(store.state(for: primaryID), .notInstalled)
  }

  func testValidateOnLaunchPrunesUnknownCatalogIDs() {
    defaults.set(["retired-model"], forKey: PreferencesKeys.ocrInstalledModels)

    store.validateInstalledModelsOnLaunch()

    XCTAssertEqual(defaults.stringArray(forKey: PreferencesKeys.ocrInstalledModels) ?? [], [])
  }

  func testValidateOnLaunchPrunesOnlyIncompleteInstalls() async {
    await store.download(modelID: primaryID).value
    defaults.set([primaryID, secondaryID], forKey: PreferencesKeys.ocrInstalledModels)

    store.validateInstalledModelsOnLaunch()

    XCTAssertEqual(defaults.stringArray(forKey: PreferencesKeys.ocrInstalledModels), [primaryID])
    XCTAssertEqual(store.state(for: primaryID), .installed)
    XCTAssertEqual(store.state(for: secondaryID), .notInstalled)
  }

  // MARK: - Missing Files Recovery

  /// Pins the recognition-time fallback path: `OCRService` marks the failed
  /// model missing, then the resolver falls the selection back to built-in.
  func testMarkMissingPrunesInstallAndResolvesFallbackToBuiltIn() async {
    await store.download(modelID: primaryID).value
    defaults.set("dl:\(primaryID)", forKey: PreferencesKeys.ocrSelectedModel)

    store.markMissing(modelID: primaryID)

    XCTAssertEqual(store.state(for: primaryID), .notInstalled)
    XCTAssertEqual(defaults.stringArray(forKey: PreferencesKeys.ocrInstalledModels) ?? [], [])
    let resolution = OCRModelResolver(defaults: defaults).resolve(.downloadable(primaryID))
    XCTAssertEqual(resolution.selection, .builtIn)
    XCTAssertEqual(resolution.provider.engine, .vision)
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.ocrSelectedModel), "builtin")
  }

  // MARK: - External Reload

  func testReloadFromDefaultsSyncsStatesAndPrunesMissingInstalls() async {
    await store.download(modelID: primaryID).value
    // External rewrite (config import): drops tiny, adds small (not on disk).
    defaults.set([secondaryID], forKey: PreferencesKeys.ocrInstalledModels)

    store.reloadFromDefaults()

    XCTAssertEqual(store.state(for: primaryID), .notInstalled)
    XCTAssertEqual(store.state(for: secondaryID), .notInstalled)
    XCTAssertEqual(defaults.stringArray(forKey: PreferencesKeys.ocrInstalledModels) ?? [], [])
  }

  func testReloadFromDefaultsMarksExternallyInstalledModels() async {
    await store.download(modelID: primaryID).value
    // A store created while defaults hold no installs starts with empty state.
    defaults.removeObject(forKey: PreferencesKeys.ocrInstalledModels)
    let freshStore = OCRModelStore(
      defaults: defaults,
      installRootURL: installRoot,
      downloadService: downloader,
      catalog: catalog
    )
    XCTAssertEqual(freshStore.state(for: primaryID), .notInstalled)

    // External write (config import) restores the id; files are still on disk.
    defaults.set([primaryID], forKey: PreferencesKeys.ocrInstalledModels)
    freshStore.reloadFromDefaults()

    XCTAssertEqual(freshStore.state(for: primaryID), .installed)
    XCTAssertEqual(defaults.stringArray(forKey: PreferencesKeys.ocrInstalledModels), [primaryID])
  }
}
