//
//  QuickAccessActionShortcutStoreTests.swift
//  SnapzyTests
//
//  Unit tests for Quick Access card action shortcut persistence and gating.
//

import Carbon.HIToolbox
import XCTest
@testable import Snapzy

@MainActor
final class QuickAccessActionShortcutStoreTests: XCTestCase {
  // Keep MainActor ObservableObjects alive for the test process; XCTest scope
  // cleanup can crash while deinitializing app-level observable stores.
  private static var retainedStores: [QuickAccessActionShortcutStore] = []

  private func makeStore(suiteName: String = UUID().uuidString) -> QuickAccessActionShortcutStore {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let store = QuickAccessActionShortcutStore(defaults: defaults)
    Self.retainedStores.append(store)
    return store
  }

  func testDefaults_bindEveryActionWithARequiredModifier() {
    let store = makeStore()

    for action in QuickAccessActionKind.allCases {
      let shortcut = try? XCTUnwrap(store.shortcut(for: action))
      XCTAssertNotNil(shortcut, "\(action.rawValue) should ship with a default binding")
      guard let shortcut else { continue }
      XCTAssertTrue(
        QuickAccessActionShortcutStore.hasRequiredModifier(shortcut),
        "\(action.rawValue) default must carry ⌘/⌥/⌃ — it consumes the key while hovering"
      )
      XCTAssertFalse(QuickAccessActionShortcutStore.containsFunctionModifier(shortcut))
    }

    XCTAssertEqual(
      store.shortcut(for: .copy),
      ShortcutConfig(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey))
    )
    XCTAssertEqual(store.activeBindings.count, QuickAccessActionKind.allCases.count)
  }

  func testDefaults_haveNoDuplicateBindings() {
    let store = makeStore()
    let bindings = store.activeBindings.map(\.shortcut)
    XCTAssertEqual(Set(bindings.map { "\($0.keyCode)-\($0.modifiers)" }).count, bindings.count)
  }

  func testClearedShortcut_persistsAsClearedRatherThanFallingBackToDefault() {
    let suiteName = UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = QuickAccessActionShortcutStore(defaults: defaults)
    Self.retainedStores.append(store)
    store.setShortcut(nil, for: .copy)

    let reloaded = QuickAccessActionShortcutStore(defaults: defaults)
    Self.retainedStores.append(reloaded)
    XCTAssertNil(reloaded.shortcut(for: .copy))
    XCTAssertNotNil(reloaded.shortcut(for: .delete))
  }

  func testActiveBindings_excludeDisabledActionsAndRespectMasterToggle() {
    let store = makeStore()

    store.setEnabled(false, for: .delete)
    XCTAssertFalse(store.activeBindings.contains { $0.action == .delete })
    XCTAssertTrue(store.activeBindings.contains { $0.action == .copy })

    store.isEnabled = false
    XCTAssertTrue(store.activeBindings.isEmpty)
  }

  func testActiveBindings_dropFnCombosCarbonCannotRegister() {
    let store = makeStore()
    store.setShortcut(
      ShortcutConfig(
        keyCode: UInt32(kVK_ANSI_C),
        modifiers: UInt32(cmdKey) | ShortcutConfig.functionCarbonModifier
      ),
      for: .copy
    )

    XCTAssertFalse(store.activeBindings.contains { $0.action == .copy })
  }

  func testActionMatching_resolvesConfigBackToAction() {
    let store = makeStore()
    let saveShortcut = ShortcutConfig(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey))

    XCTAssertEqual(store.action(matching: saveShortcut), .saveOrOpen)
    XCTAssertNil(
      store.action(matching: ShortcutConfig(keyCode: UInt32(kVK_ANSI_Z), modifiers: UInt32(cmdKey)))
    )
  }

  func testResetToDefaults_restoresClearedAndDisabledEntries() {
    let store = makeStore()
    store.setShortcut(nil, for: .copy)
    store.setEnabled(false, for: .edit)
    store.isEnabled = false

    store.resetToDefaults()

    XCTAssertTrue(store.isEnabled)
    XCTAssertTrue(store.isEnabled(for: .edit))
    XCTAssertEqual(
      store.shortcut(for: .copy),
      QuickAccessActionShortcutStore.defaultShortcuts[.copy]
    )
  }

  func testRequiredModifier_rejectsShiftOnlyCombos() {
    let shiftOnly = ShortcutConfig(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(shiftKey))
    let bare = ShortcutConfig(keyCode: UInt32(kVK_ANSI_C), modifiers: 0)
    let control = ShortcutConfig(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey))

    XCTAssertFalse(QuickAccessActionShortcutStore.hasRequiredModifier(shiftOnly))
    XCTAssertFalse(QuickAccessActionShortcutStore.hasRequiredModifier(bare))
    XCTAssertTrue(QuickAccessActionShortcutStore.hasRequiredModifier(control))
  }
}
