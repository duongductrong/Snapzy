//
//  CustomOCRModelStoreTests.swift
//  SnapzyTests
//
//  CRUD, persistence, Keychain cleanup, and selection-reset coverage.
//

import XCTest
@testable import Snapzy

@MainActor
final class CustomOCRModelStoreTests: XCTestCase {
  private var defaults: UserDefaults!
  private var keychain: FakeOCRKeychainStore!
  private var store: CustomOCRModelStore!

  override func setUp() {
    super.setUp()
    defaults = UserDefaultsFactory.make()
    keychain = FakeOCRKeychainStore()
    store = CustomOCRModelStore(defaults: defaults, keychainStore: keychain)
  }

  private func makeModel(
    id: UUID = UUID(),
    name: String = "Test Model",
    baseURL: String = "https://api.example.com",
    modelIdentifier: String = "test-model",
    prompt: String? = nil,
    hasAPIKey: Bool = false,
    updatedAt: Date = Date()
  ) -> CustomOCRModel {
    CustomOCRModel(
      id: id,
      name: name,
      baseURL: baseURL,
      modelIdentifier: modelIdentifier,
      prompt: prompt,
      hasAPIKey: hasAPIKey,
      updatedAt: updatedAt
    )
  }

  // MARK: - CRUD

  func testAddPersistsModelToDefaults() throws {
    let model = makeModel()
    store.add(model)

    XCTAssertEqual(store.models, [model])
    let data = try XCTUnwrap(defaults.data(forKey: PreferencesKeys.ocrCustomModels))
    XCTAssertEqual(try JSONDecoder().decode([CustomOCRModel].self, from: data), [model])
  }

  func testUpdateRenamesModelAndBumpsUpdatedAt() throws {
    let model = makeModel(name: "Old Name", updatedAt: Date(timeIntervalSince1970: 1000))
    store.add(model)

    var renamed = model
    renamed.name = "New Name"
    store.update(renamed)

    let stored = try XCTUnwrap(store.model(for: model.id))
    XCTAssertEqual(stored.name, "New Name")
    XCTAssertGreaterThan(stored.updatedAt, model.updatedAt)
    XCTAssertEqual(store.models.count, 1)
  }

  func testUpdateIgnoresUnknownModel() {
    store.add(makeModel())
    store.update(makeModel(name: "Ghost"))
    XCTAssertEqual(store.models.count, 1)
    XCTAssertEqual(store.models.first?.name, "Test Model")
  }

  func testRemoveDeletesModelAndKeychainEntry() {
    let model = makeModel()
    store.add(model)
    keychain.seedKey("sk-secret", for: model.id)

    store.remove(id: model.id)

    XCTAssertTrue(store.models.isEmpty)
    XCTAssertEqual(keychain.deletedIDs, [model.id])
    XCTAssertNil(keychain.readKey(for: model.id))
  }

  // MARK: - Selection reset

  func testRemoveResetsSelectionWhenRemovedModelWasActive() {
    let model = makeModel()
    store.add(model)
    defaults.set("custom:\(model.id.uuidString)", forKey: PreferencesKeys.ocrSelectedModel)

    store.remove(id: model.id)

    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.ocrSelectedModel), "builtin")
  }

  func testRemoveKeepsSelectionWhenOtherModelIsActive() {
    let model = makeModel()
    store.add(model)
    defaults.set("dl:ppocrv6-tiny", forKey: PreferencesKeys.ocrSelectedModel)

    store.remove(id: model.id)

    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.ocrSelectedModel), "dl:ppocrv6-tiny")
  }

  // MARK: - Persistence

  func testModelsPersistAcrossStoreInstances() {
    store.add(makeModel(name: "Alpha"))
    store.add(makeModel(name: "Beta"))

    let reloaded = CustomOCRModelStore(defaults: defaults, keychainStore: keychain)

    XCTAssertEqual(reloaded.models.map(\.name), ["Alpha", "Beta"])
  }

  func testCorruptPersistedJSONLoadsEmptyAndClearsKey() {
    defaults.set(Data("not json".utf8), forKey: PreferencesKeys.ocrCustomModels)

    let corruptStore = CustomOCRModelStore(defaults: defaults, keychainStore: keychain)

    XCTAssertTrue(corruptStore.models.isEmpty)
    XCTAssertNil(defaults.data(forKey: PreferencesKeys.ocrCustomModels))
  }

  /// The Phase 1 availability checker decodes stored models by their `"id"`
  /// key — the JSON encoding must keep it stable.
  func testStoredJSONKeepsIDKeyForAvailabilityChecker() throws {
    let model = makeModel()
    store.add(model)

    let data = try XCTUnwrap(defaults.data(forKey: PreferencesKeys.ocrCustomModels))
    let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    XCTAssertEqual(entries.first?["id"] as? String, model.id.uuidString)
    XCTAssertTrue(UserDefaultsOCRModelAvailability(defaults: defaults).customModelExists(id: model.id))
  }

  // MARK: - API key sync

  func testSetAPIKeyStoresKeyAndUpdatesFlag() throws {
    let model = makeModel()
    store.add(model)

    try store.setAPIKey("sk-live", for: model.id)

    XCTAssertEqual(keychain.readKey(for: model.id), "sk-live")
    XCTAssertEqual(store.model(for: model.id)?.hasAPIKey, true)
  }

  func testSetAPIKeyNilDeletesKeyAndClearsFlag() throws {
    let model = makeModel(hasAPIKey: true)
    store.add(model)
    keychain.seedKey("sk-live", for: model.id)

    try store.setAPIKey(nil, for: model.id)

    XCTAssertEqual(keychain.deletedIDs, [model.id])
    XCTAssertNil(keychain.readKey(for: model.id))
    XCTAssertEqual(store.model(for: model.id)?.hasAPIKey, false)
  }

  // MARK: - Keychain failure

  func testSetAPIKeyFailureKeepsFlagFalseAndModelIntact() {
    let model = makeModel()
    store.add(model)
    keychain.saveError = OCRKeychainError.saveFailed(-25299)

    XCTAssertThrowsError(try store.setAPIKey("sk-live", for: model.id))

    XCTAssertEqual(store.model(for: model.id)?.hasAPIKey, false)
    XCTAssertNil(keychain.readKey(for: model.id))
    XCTAssertEqual(store.models.count, 1)

    // The store stays consistent, so a retry after recovery succeeds.
    keychain.saveError = nil
    XCTAssertNoThrow(try store.setAPIKey("sk-live", for: model.id))
    XCTAssertEqual(store.model(for: model.id)?.hasAPIKey, true)
    XCTAssertEqual(keychain.readKey(for: model.id), "sk-live")
  }

  /// Pins the add-sheet rollback: add → key save throws → remove rolls back,
  /// so a Save retry cannot pile up duplicate models.
  func testAddRollbackAfterKeychainFailureLeavesNoDuplicate() throws {
    let model = makeModel()
    keychain.saveError = OCRKeychainError.saveFailed(-25299)

    store.add(model)
    XCTAssertThrowsError(try store.setAPIKey("sk-live", for: model.id))
    store.remove(id: model.id)

    XCTAssertTrue(store.models.isEmpty)

    keychain.saveError = nil
    store.add(model)
    try store.setAPIKey("sk-live", for: model.id)

    XCTAssertEqual(store.models.count, 1)
    XCTAssertEqual(store.model(for: model.id)?.hasAPIKey, true)
  }

  // MARK: - External reload

  func testReloadFromDefaultsPicksUpExternallyWrittenModels() throws {
    let external = makeModel(name: "External")
    defaults.set(try JSONEncoder().encode([external]), forKey: PreferencesKeys.ocrCustomModels)
    XCTAssertTrue(store.models.isEmpty)

    store.reloadFromDefaults()

    XCTAssertEqual(store.models, [external])
  }

  // MARK: - Router wiring

  func testResolverBuildsRemoteProviderForStoredCustomModel() {
    let model = makeModel()
    store.add(model)
    defaults.set("custom:\(model.id.uuidString)", forKey: PreferencesKeys.ocrSelectedModel)

    let resolution = OCRModelResolver(defaults: defaults).resolveStoredSelection()

    XCTAssertEqual(resolution.selection, .custom(model.id))
    XCTAssertEqual(resolution.provider.engine, .remote)
  }
}
