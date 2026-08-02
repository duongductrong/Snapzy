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

  // MARK: - String persistence

  func testPersistedValueUsesStableFormats() {
    XCTAssertEqual(OCRModelSelection.builtIn.persistedValue, "builtin")
    XCTAssertEqual(OCRModelSelection.downloadable("demo-model").persistedValue, "dl:demo-model")
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    XCTAssertEqual(OCRModelSelection.custom(id).persistedValue, "custom:00000000-0000-0000-0000-000000000001")
  }

  func testPersistedValueRoundTripsAllCases() {
    let id = UUID()
    let cases: [OCRModelSelection] = [
      .builtIn,
      .downloadable("other-model"),
      .custom(id),
    ]

    for selection in cases {
      XCTAssertEqual(OCRModelSelection(persistedValue: selection.persistedValue), selection)
    }
  }

  func testCorruptPersistedValueFallsBackToBuiltIn() {
    let corruptValues = ["", "vision", "dl", "dl:", "custom", "custom:", "custom:not-a-uuid", "unknown:value"]

    for rawValue in corruptValues {
      XCTAssertEqual(OCRModelSelection(persistedValue: rawValue), .builtIn, rawValue)
    }
  }

  func testCodableRoundTripUsesPersistedString() throws {
    let selection = OCRModelSelection.downloadable("other-model")
    let data = try JSONEncoder().encode(selection)
    XCTAssertEqual(String(data: data, encoding: .utf8), "\"dl:other-model\"")
    XCTAssertEqual(try JSONDecoder().decode(OCRModelSelection.self, from: data), selection)
  }

  // MARK: - Resolution

  func testResolverReturnsBuiltInWhenNothingPersisted() {
    let defaults = UserDefaultsFactory.make()
    let resolution = OCRModelResolver(defaults: defaults).resolveStoredSelection()

    XCTAssertEqual(resolution.selection, .builtIn)
    XCTAssertEqual(resolution.provider.engine, .vision)
  }

  func testResolverReturnsBuiltInForCorruptPersistedValue() {
    let defaults = UserDefaultsFactory.make()
    defaults.set("garbage", forKey: PreferencesKeys.ocrSelectedModel)

    let resolution = OCRModelResolver(defaults: defaults).resolveStoredSelection()

    XCTAssertEqual(resolution.selection, .builtIn)
    XCTAssertEqual(resolution.provider.engine, .vision)
  }

  func testDownloadableSelectionResolvesWhenModelInstalled() {
    let defaults = UserDefaultsFactory.make()
    defaults.set(["demo-model"], forKey: PreferencesKeys.ocrInstalledModels)
    defaults.set("dl:demo-model", forKey: PreferencesKeys.ocrSelectedModel)

    let resolution = OCRModelResolver(defaults: defaults).resolveStoredSelection()

    XCTAssertEqual(resolution.selection, .downloadable("demo-model"))
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.ocrSelectedModel), "dl:demo-model")
  }

  func testDownloadableSelectionFallsBackAndPersistsBuiltInWhenNotInstalled() {
    let defaults = UserDefaultsFactory.make()
    defaults.set("dl:demo-model", forKey: PreferencesKeys.ocrSelectedModel)

    let resolution = OCRModelResolver(defaults: defaults).resolveStoredSelection()

    XCTAssertEqual(resolution.selection, .builtIn)
    XCTAssertEqual(resolution.provider.engine, .vision)
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.ocrSelectedModel), "builtin")
  }

  func testCustomSelectionResolvesWhenModelExists() throws {
    let defaults = UserDefaultsFactory.make()
    let id = UUID()
    let data = try JSONSerialization.data(withJSONObject: [["id": id.uuidString]])
    defaults.set(data, forKey: PreferencesKeys.ocrCustomModels)
    defaults.set("custom:\(id.uuidString)", forKey: PreferencesKeys.ocrSelectedModel)

    let resolution = OCRModelResolver(defaults: defaults).resolveStoredSelection()

    XCTAssertEqual(resolution.selection, .custom(id))
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.ocrSelectedModel), "custom:\(id.uuidString)")
  }

  func testCustomSelectionFallsBackAndPersistsBuiltInWhenModelMissing() {
    let defaults = UserDefaultsFactory.make()
    let id = UUID()
    defaults.set("custom:\(id.uuidString)", forKey: PreferencesKeys.ocrSelectedModel)

    let resolution = OCRModelResolver(defaults: defaults).resolveStoredSelection()

    XCTAssertEqual(resolution.selection, .builtIn)
    XCTAssertEqual(resolution.provider.engine, .vision)
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.ocrSelectedModel), "builtin")
  }

  func testCustomSelectionFallsBackWhenStoredModelsAreCorrupt() {
    let defaults = UserDefaultsFactory.make()
    let id = UUID()
    defaults.set(Data("not json".utf8), forKey: PreferencesKeys.ocrCustomModels)
    defaults.set("custom:\(id.uuidString)", forKey: PreferencesKeys.ocrSelectedModel)

    let resolution = OCRModelResolver(defaults: defaults).resolveStoredSelection()

    XCTAssertEqual(resolution.selection, .builtIn)
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.ocrSelectedModel), "builtin")
  }

  func testBuiltInSelectionResolvesWithoutRewritingDefaults() {
    let defaults = UserDefaultsFactory.make()
    defaults.set("builtin", forKey: PreferencesKeys.ocrSelectedModel)

    let resolution = OCRModelResolver(defaults: defaults).resolveStoredSelection()

    XCTAssertEqual(resolution.selection, .builtIn)
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.ocrSelectedModel), "builtin")
  }
}
