//
//  AutomationStoreTests.swift
//  SnapzyTests
//
//  Seeding, persistence and CRUD of AutomationStore in isolated defaults.
//

import Carbon.HIToolbox
import XCTest
@testable import Snapzy

@MainActor
final class AutomationStoreTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suiteName = "AutomationStoreTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    super.tearDown()
  }

  func testSeedsPresetsOnce() {
    let store = AutomationStore(defaults: defaults)
    XCTAssertEqual(store.automations.compactMap(\.presetID), AutomationPreset.allCases.map(\.rawValue))

    store.automations.map(\.id).forEach { store.delete(id: $0) }
    let reloaded = AutomationStore(defaults: defaults)
    XCTAssertTrue(reloaded.automations.isEmpty, "Deleted presets must not be seeded again")
    XCTAssertEqual(reloaded.missingPresets, AutomationPreset.allCases)

    reloaded.restoreMissingPresets()
    XCTAssertEqual(reloaded.automations.count, AutomationPreset.allCases.count)
    XCTAssertTrue(reloaded.missingPresets.isEmpty)
  }

  func testUpdatePersistsAcrossInstances() {
    let store = AutomationStore(defaults: defaults)
    var automation = store.automations[0]
    automation.name = "Renamed"
    automation.hotkey = ShortcutConfig(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(controlKey | shiftKey))
    store.update(automation)

    let reloaded = AutomationStore(defaults: defaults)
    XCTAssertEqual(reloaded.automation(id: automation.id)?.name, "Renamed")
    XCTAssertEqual(reloaded.automation(id: automation.id)?.hotkey, automation.hotkey)
  }

  func testDuplicateClearsShortcutAndPreset() throws {
    let store = AutomationStore(defaults: defaults)
    let original = store.automations[0]
    store.setHotkey(ShortcutConfig(keyCode: 1, modifiers: UInt32(cmdKey)), id: original.id)

    let copy = try XCTUnwrap(store.duplicate(id: original.id))

    XCTAssertNotEqual(copy.id, original.id)
    XCTAssertNil(copy.hotkey)
    XCTAssertNil(copy.presetID)
    XCTAssertEqual(copy.activeActions, original.activeActions)
    XCTAssertEqual(store.automations.firstIndex { $0.id == copy.id }, 1)
    XCTAssertTrue(Set(copy.steps.map(\.id)).isDisjoint(with: original.steps.map(\.id)))
  }

  func testCapLimitsAdd() {
    let store = AutomationStore(defaults: defaults)
    while store.canAdd {
      XCTAssertTrue(store.add(AutomationPreset.quickCopy.makeAutomation()))
    }
    XCTAssertEqual(store.automations.count, AutomationStore.maxAutomations)
    XCTAssertFalse(store.add(AutomationPreset.quickCopy.makeAutomation()))
    XCTAssertNil(store.duplicate(id: store.automations[0].id))
  }

  func testMoveReorders() {
    let store = AutomationStore(defaults: defaults)
    let ids = store.automations.map(\.id)
    store.move(fromOffsets: IndexSet(integer: 0), toOffset: 2)
    XCTAssertEqual(Array(store.automations.map(\.id).prefix(2)), [ids[1], ids[0]])
  }

  func testReplaceAllCapsAndMarksSeeded() {
    let store = AutomationStore(defaults: defaults)
    let many = (0..<(AutomationStore.maxAutomations + 5)).map { _ in AutomationPreset.quickCopy.makeAutomation() }
    store.replaceAll(many)
    XCTAssertEqual(store.automations.count, AutomationStore.maxAutomations)

    store.replaceAll([])
    XCTAssertTrue(AutomationStore(defaults: defaults).automations.isEmpty)
  }

  func testUndecodableEntryDoesNotEraseOthers() throws {
    let good = AutomationPreset.quickCopy.makeAutomation()
    let goodJSON = try XCTUnwrap(String(data: JSONEncoder().encode(good), encoding: .utf8))
    let stored = "[\(goodJSON), {\"name\": \"broken, no id or source\"}]"
    defaults.set(Data(stored.utf8), forKey: PreferencesKeys.automations)
    defaults.set(true, forKey: PreferencesKeys.automationsSeeded)

    let store = AutomationStore(defaults: defaults)
    XCTAssertEqual(store.automations.map(\.id), [good.id])

    store.setEnabled(false, id: good.id)
    let raw = try XCTUnwrap(defaults.data(forKey: PreferencesKeys.automations))
    let entries = try JSONDecoder().decode([AutomationJSONValue].self, from: raw)
    XCTAssertEqual(entries.count, 2, "The undecodable entry is written back untouched")
  }
}
