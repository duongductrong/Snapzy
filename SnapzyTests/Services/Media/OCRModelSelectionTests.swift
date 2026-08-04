//
//  OCRModelSelectionTests.swift
//  SnapzyTests
//
//  Selection persistence, resolution, and fallback coverage.
//

import XCTest
@testable import Snapzy

@MainActor
final class OCRModelSelectionTests: XCTestCase {
  func testPersistedValueUsesStableFormats() {
    XCTAssertEqual(OCRModelSelection.builtIn.persistedValue, "builtin")
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    XCTAssertEqual(OCRModelSelection.custom(id).persistedValue, "custom:00000000-0000-0000-0000-000000000001")
  }

  func testCustomPersistedValueRoundTrips() {
    let selection = OCRModelSelection.custom(UUID())
    XCTAssertEqual(OCRModelSelection(persistedValue: selection.persistedValue), selection)
  }

  func testLegacyDownloadableAndCorruptValuesFallBackToBuiltIn() {
    let values = ["", "vision", "dl", "dl:", "dl:old-model", "custom", "custom:", "custom:not-a-uuid", "unknown:value"]

    for value in values {
      XCTAssertEqual(OCRModelSelection(persistedValue: value), .builtIn, value)
    }
  }

  func testCodableRoundTripUsesPersistedString() throws {
    let selection = OCRModelSelection.custom(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    let data = try JSONEncoder().encode(selection)
    XCTAssertEqual(String(data: data, encoding: .utf8), "\"custom:00000000-0000-0000-0000-000000000001\"")
    XCTAssertEqual(try JSONDecoder().decode(OCRModelSelection.self, from: data), selection)
  }

  func testResolverReturnsBuiltInWhenNothingPersisted() {
    let defaults = UserDefaultsFactory.make()
    let resolution = OCRModelResolver(defaults: defaults).resolveStoredSelection()

    XCTAssertEqual(resolution.selection, .builtIn)
    XCTAssertEqual(resolution.provider.engine, .vision)
  }

  func testResolverCanonicalizesLegacyDownloadableSelection() {
    let defaults = UserDefaultsFactory.make()
    defaults.set("dl:old-model", forKey: PreferencesKeys.ocrSelectedModel)

    let resolution = OCRModelResolver(defaults: defaults).resolveStoredSelection()

    XCTAssertEqual(resolution.selection, .builtIn)
    XCTAssertEqual(resolution.provider.engine, .vision)
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.ocrSelectedModel), "builtin")
  }

  func testResolverReturnsBuiltInForCorruptPersistedValue() {
    let defaults = UserDefaultsFactory.make()
    defaults.set("garbage", forKey: PreferencesKeys.ocrSelectedModel)

    let resolution = OCRModelResolver(defaults: defaults).resolveStoredSelection()

    XCTAssertEqual(resolution.selection, .builtIn)
    XCTAssertEqual(resolution.provider.engine, .vision)
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.ocrSelectedModel), "builtin")
  }

  func testCustomSelectionResolvesToRemoteProviderWhenModelExists() throws {
    let defaults = UserDefaultsFactory.make()
    let model = CustomOCRModel(name: "Local", baseURL: "http://localhost:11434", modelIdentifier: "vision")
    defaults.set(try JSONEncoder().encode([model]), forKey: PreferencesKeys.ocrCustomModels)
    defaults.set(OCRModelSelection.custom(model.id).persistedValue, forKey: PreferencesKeys.ocrSelectedModel)

    let resolution = OCRModelResolver(defaults: defaults).resolveStoredSelection()

    XCTAssertEqual(resolution.selection, .custom(model.id))
    XCTAssertEqual(resolution.provider.engine, .remote)
  }

  func testMissingCustomSelectionFallsBackAndPersistsBuiltIn() {
    let defaults = UserDefaultsFactory.make()
    defaults.set(OCRModelSelection.custom(UUID()).persistedValue, forKey: PreferencesKeys.ocrSelectedModel)

    let resolution = OCRModelResolver(defaults: defaults).resolveStoredSelection()

    XCTAssertEqual(resolution.selection, .builtIn)
    XCTAssertEqual(resolution.provider.engine, .vision)
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.ocrSelectedModel), "builtin")
  }
}
