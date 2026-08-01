//
//  MenuBarCustomizationStoreTests.swift
//  SnapzyTests
//
//  Unit tests for menu bar item order/visibility and icon style persistence.
//

import XCTest
@testable import Snapzy

@MainActor
final class MenuBarCustomizationStoreTests: XCTestCase {
  // Keep MainActor ObservableObjects alive for the test process; XCTest scope
  // cleanup can crash while deinitializing app-level observable stores.
  private static var retainedStores: [MenuBarCustomizationStore] = []

  func testStore_usesDefaultOrderWithNothingHiddenAndDefaultIcon() {
    let store = makeStore(defaults: makeIsolatedDefaults())

    XCTAssertEqual(store.itemOrder, MenuBarItemKind.allCases.filter(\.isCustomizable))
    XCTAssertTrue(store.hiddenItems.isEmpty)
    XCTAssertEqual(store.iconStyle, .default)

    for group in MenuBarItemGroup.allCases {
      XCTAssertEqual(
        store.orderedVisibleItems(for: group),
        MenuBarItemKind.defaultOrder(for: group)
      )
    }
  }

  func testStore_filtersUnknownIdsAndAppendsMissingItems() {
    let defaults = makeIsolatedDefaults()
    defaults.set(
      [
        MenuBarItemKind.editVideo.rawValue,
        "future-item",
        MenuBarItemKind.captureArea.rawValue,
        MenuBarItemKind.captureArea.rawValue,
        MenuBarItemKind.checkForUpdates.rawValue,  // pinned: never part of the order list
      ],
      forKey: PreferencesKeys.menuBarItemOrder
    )

    let store = makeStore(defaults: defaults)

    XCTAssertEqual(store.itemOrder.first, .editVideo)
    XCTAssertEqual(store.itemOrder.count, MenuBarItemKind.allCases.filter(\.isCustomizable).count)
    XCTAssertFalse(store.itemOrder.contains(.checkForUpdates))
    XCTAssertTrue(store.itemOrder.contains(.captureOCR))  // missing items appended
    // Relative order within a group is preserved even across groups in the flat list.
    XCTAssertEqual(
      store.orderedItems(for: .capture).first,
      .captureArea
    )
  }

  func testStore_hidingItemRemovesItFromVisibleItemsOnly() {
    let defaults = makeIsolatedDefaults()
    let store = makeStore(defaults: defaults)

    store.setHidden(.captureArea, hidden: true)

    XCTAssertTrue(store.isHidden(.captureArea))
    XCTAssertFalse(store.orderedVisibleItems(for: .capture).contains(.captureArea))
    XCTAssertTrue(store.orderedItems(for: .capture).contains(.captureArea))

    store.setHidden(.captureArea, hidden: false)

    XCTAssertFalse(store.isHidden(.captureArea))
    XCTAssertTrue(store.orderedVisibleItems(for: .capture).contains(.captureArea))
  }

  func testStore_hidingPinnedEntryIsIgnored() {
    let defaults = makeIsolatedDefaults()
    defaults.set(
      ["quit", "preferences", "captureArea"],
      forKey: PreferencesKeys.menuBarHiddenItems
    )

    let store = makeStore(defaults: defaults)

    XCTAssertEqual(store.hiddenItems, [.captureArea])
  }

  func testStore_hidesFixedPositionCheckForUpdates() {
    let defaults = makeIsolatedDefaults()
    let store = makeStore(defaults: defaults)

    store.setHidden(.checkForUpdates, hidden: true)

    XCTAssertTrue(store.isHidden(.checkForUpdates))

    let reloaded = makeStore(defaults: defaults)
    XCTAssertTrue(reloaded.isHidden(.checkForUpdates))
  }

  func testStore_persistsHiddenItemsAcrossInstances() {
    let defaults = makeIsolatedDefaults()
    let store = makeStore(defaults: defaults)

    store.setHidden(.openHistory, hidden: true)
    store.setHidden(.recordScreen, hidden: true)

    let reloaded = makeStore(defaults: defaults)
    XCTAssertEqual(reloaded.hiddenItems, [.openHistory, .recordScreen])
    XCTAssertFalse(reloaded.orderedVisibleItems(for: .tools).contains(.openHistory))
    XCTAssertFalse(reloaded.orderedVisibleItems(for: .recording).contains(.recordScreen))
  }

  func testStore_moveItemReordersWithinGroupOnly() {
    let defaults = makeIsolatedDefaults()
    let store = makeStore(defaults: defaults)
    let captureBefore = store.orderedItems(for: .capture)
    let toolsBefore = store.orderedItems(for: .tools)

    // Move first capture item to the end of the capture group.
    store.moveItem(from: IndexSet(integer: 0), to: captureBefore.count, in: .capture)

    let captureAfter = store.orderedItems(for: .capture)
    XCTAssertEqual(captureAfter.last, captureBefore.first)
    XCTAssertEqual(Array(captureAfter.dropLast()), Array(captureBefore.dropFirst()))
    XCTAssertEqual(store.orderedItems(for: .tools), toolsBefore)
  }

  func testStore_moveItemHandlesHiddenItemsInIndexMath() {
    let defaults = makeIsolatedDefaults()
    let store = makeStore(defaults: defaults)
    store.setHidden(.captureAreaAnnotate, hidden: true)  // index 1 in capture group

    // Move captureArea (index 0) past captureFullscreen — indices address the
    // full group list including the hidden row, matching the settings UI.
    store.moveItem(from: IndexSet(integer: 0), to: 3, in: .capture)

    let captureOrder = store.orderedItems(for: .capture)
    XCTAssertEqual(
      captureOrder,
      [.captureAreaAnnotate, .captureApplication, .captureArea, .captureFullscreen,
       .captureActiveWindow, .scrollingCapture, .captureOCR, .captureSmartElement,
       .captureObjectCutout]
    )
    XCTAssertTrue(store.isHidden(.captureAreaAnnotate))
  }

  func testStore_resetToDefaultsRestoresOrderVisibilityAndIcon() {
    let defaults = makeIsolatedDefaults()
    let store = makeStore(defaults: defaults)
    store.setHidden(.captureArea, hidden: true)
    store.moveItem(from: IndexSet(integer: 0), to: 2, in: .capture)
    store.setIconStyle(.scissors)

    store.resetToDefaults()

    XCTAssertEqual(store.itemOrder, MenuBarItemKind.allCases.filter(\.isCustomizable))
    XCTAssertTrue(store.hiddenItems.isEmpty)
    XCTAssertEqual(store.iconStyle, .default)
  }

  func testStore_applyConfigurationNormalizesImportedValues() {
    let defaults = makeIsolatedDefaults()
    let store = makeStore(defaults: defaults)

    store.applyConfiguration(
      order: [.shortcutList, .captureOCR],
      hiddenItems: [.captureOCR],
      iconStyle: .cameraFill
    )

    XCTAssertEqual(store.orderedItems(for: .tools).first, .shortcutList)
    XCTAssertEqual(store.orderedItems(for: .capture).first, .captureOCR)
    XCTAssertTrue(store.isHidden(.captureOCR))
    XCTAssertEqual(store.iconStyle, .cameraFill)
    XCTAssertEqual(store.itemOrder.count, MenuBarItemKind.allCases.filter(\.isCustomizable).count)
  }

  func testStore_iconStyleFallsBackToDefaultForUnknownRawValue() {
    let defaults = makeIsolatedDefaults()
    defaults.set("future-style", forKey: PreferencesKeys.menuBarIconStyle)

    let store = makeStore(defaults: defaults)

    XCTAssertEqual(store.iconStyle, .default)
  }

  func testStore_persistsIconStyleAcrossInstances() {
    let defaults = makeIsolatedDefaults()
    let store = makeStore(defaults: defaults)

    store.setIconStyle(.cameraViewfinder)

    let reloaded = makeStore(defaults: defaults)
    XCTAssertEqual(reloaded.iconStyle, .cameraViewfinder)
  }

  // MARK: - Helpers

  private func makeIsolatedDefaults() -> UserDefaults {
    let suiteName = "SnapzyTests.MenuBar.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }

  private func makeStore(defaults: UserDefaults) -> MenuBarCustomizationStore {
    let store = MenuBarCustomizationStore(defaults: defaults)
    Self.retainedStores.append(store)
    return store
  }
}
