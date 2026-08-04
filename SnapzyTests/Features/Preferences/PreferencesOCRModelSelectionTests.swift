//
//  PreferencesOCRModelSelectionTests.swift
//  SnapzyTests
//
//  Selection persistence rules for the OCR provider list view model.
//

import XCTest
@testable import Snapzy

@MainActor
final class PreferencesOCRModelSelectionTests: XCTestCase {
  private var defaults: UserDefaults!
  private var customStore: CustomOCRModelStore!
  private var viewModel: PreferencesOCRModelListViewModel!

  override func setUp() {
    super.setUp()
    defaults = UserDefaultsFactory.make()
    customStore = CustomOCRModelStore(defaults: defaults, keychainStore: FakeOCRKeychainStore())
    viewModel = PreferencesOCRModelListViewModel(
      defaults: defaults,
      customModelStore: customStore
    )
  }

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

  func testDefaultSelectionIsBuiltIn() {
    XCTAssertEqual(viewModel.selection, .builtIn)
    XCTAssertNil(persistedSelection())
  }

  func testLegacyDownloadableSelectionIsCanonicalizedToBuiltIn() {
    defaults.set("dl:old-model", forKey: PreferencesKeys.ocrSelectedModel)

    let migrated = PreferencesOCRModelListViewModel(
      defaults: defaults,
      customModelStore: customStore
    )

    XCTAssertEqual(migrated.selection, .builtIn)
    XCTAssertEqual(persistedSelection(), "builtin")
  }

  func testSelectBuiltInPersistsImmediately() {
    viewModel.select(.builtIn)

    XCTAssertEqual(viewModel.selection, .builtIn)
    XCTAssertEqual(persistedSelection(), "builtin")
  }

  func testSelectCustomModelIsPersisted() {
    let model = addCustomModel()

    viewModel.select(.custom(model.id))

    XCTAssertEqual(viewModel.selection, .custom(model.id))
    XCTAssertEqual(persistedSelection(), "custom:\(model.id.uuidString)")
  }

  func testSelectMissingCustomModelIsIgnored() {
    viewModel.select(.custom(UUID()))

    XCTAssertEqual(viewModel.selection, .builtIn)
    XCTAssertNil(persistedSelection())
  }

  func testRemoveActiveCustomModelResetsSelectionToBuiltIn() {
    let model = addCustomModel()
    viewModel.select(.custom(model.id))

    viewModel.removeCustom(model)

    XCTAssertEqual(viewModel.selection, .builtIn)
    XCTAssertEqual(persistedSelection(), "builtin")
    XCTAssertNil(customStore.model(for: model.id))
  }
}
