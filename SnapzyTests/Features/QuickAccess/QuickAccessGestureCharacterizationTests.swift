//
//  QuickAccessGestureCharacterizationTests.swift
//  SnapzyTests
//
//  Locks down the existing Quick Access swipe/drag rules, placement and stack
//  visibility before the edge-peek feature (#591) builds on top of them. Any
//  change in these expectations is a behavior change for current users.
//

import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Snapzy

@MainActor
final class QuickAccessGestureCharacterizationTests: XCTestCase {
  // Keep MainActor ObservableObjects alive for the test process (see QuickAccessCoreTests).
  private static var retainedSwipeStores: [QuickAccessSwipeActionStore] = []

  private let allActions = QuickAccessActionKind.allCases
  private let allEnabled: (QuickAccessActionKind) -> Bool = { _ in true }

  private func resolver(
    left: QuickAccessActionKind? = .dismiss,
    right: QuickAccessActionKind? = .dismiss,
    hideCardWhenWindowOpen: Bool = true
  ) -> QuickAccessSwipeResolver {
    QuickAccessSwipeResolver(
      leftAction: left,
      rightAction: right,
      hideCardWhenWindowOpen: hideCardWhenWindowOpen
    )
  }

  private func makeSwipeStore() -> (QuickAccessSwipeActionStore, UserDefaults) {
    let suiteName = "QuickAccessGestureCharacterizationTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let store = QuickAccessSwipeActionStore(defaults: defaults)
    Self.retainedSwipeStores.append(store)
    return (store, defaults)
  }

  // MARK: - Live swipe offset

  func testLiveTranslation_followsPointerWhenBothDirectionsHaveActions() {
    let resolver = resolver()

    XCTAssertEqual(resolver.liveTranslation(42), 42)
    XCTAssertEqual(resolver.liveTranslation(-42), -42)
    XCTAssertEqual(resolver.liveTranslation(0), 0)
  }

  func testLiveTranslation_staysStillTowardDirectionWithoutAction() {
    let rightOnly = resolver(left: nil, right: .dismiss)
    XCTAssertEqual(rightOnly.liveTranslation(-60), 0)
    XCTAssertEqual(rightOnly.liveTranslation(60), 60)

    let leftOnly = resolver(left: .copy, right: nil)
    XCTAssertEqual(leftOnly.liveTranslation(60), 0)
    XCTAssertEqual(leftOnly.liveTranslation(-60), -60)
  }

  // MARK: - Swipe end thresholds

  func testResolveEnd_snapsBackAtOrBelowDistanceAndVelocityThresholds() {
    let resolver = resolver()

    XCTAssertEqual(resolver.resolveEnd(translation: 80, velocity: 300, isActionEnabled: allEnabled), .snapBack)
    XCTAssertEqual(resolver.resolveEnd(translation: -80, velocity: -300, isActionEnabled: allEnabled), .snapBack)
    XCTAssertEqual(resolver.resolveEnd(translation: 0, velocity: 0, isActionEnabled: allEnabled), .snapBack)
  }

  func testResolveEnd_firesPastDistanceThreshold() {
    let resolver = resolver(left: .copy, right: .dismiss)

    XCTAssertEqual(
      resolver.resolveEnd(translation: 81, velocity: 0, isActionEnabled: allEnabled),
      .perform(.dismiss, hidesCard: true)
    )
    XCTAssertEqual(
      resolver.resolveEnd(translation: -81, velocity: 0, isActionEnabled: allEnabled),
      .perform(.copy, hidesCard: false)
    )
  }

  func testResolveEnd_firesOnFlickVelocityAndUsesTranslationForDirection() {
    let resolver = resolver(left: .copy, right: .dismiss)

    XCTAssertEqual(
      resolver.resolveEnd(translation: 10, velocity: 301, isActionEnabled: allEnabled),
      .perform(.dismiss, hidesCard: true)
    )
    // Direction comes from the translation sign, not the velocity sign.
    XCTAssertEqual(
      resolver.resolveEnd(translation: 10, velocity: -301, isActionEnabled: allEnabled),
      .perform(.dismiss, hidesCard: true)
    )
    // Zero translation with a fast flick resolves to the left action.
    XCTAssertEqual(
      resolver.resolveEnd(translation: 0, velocity: 400, isActionEnabled: allEnabled),
      .perform(.copy, hidesCard: false)
    )
  }

  func testResolveEnd_directionWithoutActionIgnoresDistanceAndVelocity() {
    let resolver = resolver(left: .dismiss, right: nil)

    XCTAssertEqual(resolver.resolveEnd(translation: 500, velocity: 5000, isActionEnabled: allEnabled), .snapBack)
  }

  func testResolveEnd_disabledActionSnapsBack() {
    let resolver = resolver(left: .dismiss, right: .uploadToCloud)

    XCTAssertEqual(
      resolver.resolveEnd(translation: 200, velocity: 0, isActionEnabled: { $0 != .uploadToCloud }),
      .snapBack
    )
    XCTAssertEqual(
      resolver.resolveEnd(translation: -200, velocity: 0, isActionEnabled: { $0 != .uploadToCloud }),
      .perform(.dismiss, hidesCard: true)
    )
  }

  func testResolveEnd_hidesCardOnlyForActionsThatRemoveItFromStack() {
    let expectedWhenHidingOpenWindows: [QuickAccessActionKind: Bool] = [
      .copy: false,
      .saveOrOpen: false,
      .dismiss: true,
      .delete: true,
      .edit: true,
      .uploadToCloud: false,
      .pinToScreen: true,
      .optimize: false,
    ]
    let expectedWhenKeepingOpenWindows: [QuickAccessActionKind: Bool] = [
      .copy: false,
      .saveOrOpen: false,
      .dismiss: true,
      .delete: true,
      .edit: false,
      .uploadToCloud: false,
      .pinToScreen: false,
      .optimize: false,
    ]
    // Every pre-existing action; collapseToEdge (#591) resolves to `.collapse` instead.
    XCTAssertEqual(
      Set(expectedWhenHidingOpenWindows.keys),
      Set(allActions).subtracting([.collapseToEdge])
    )

    for action in expectedWhenHidingOpenWindows.keys {
      let hiding = resolver(left: nil, right: action, hideCardWhenWindowOpen: true)
      XCTAssertEqual(
        hiding.resolveEnd(translation: 120, velocity: 0, isActionEnabled: allEnabled),
        .perform(action, hidesCard: expectedWhenHidingOpenWindows[action]!),
        "\(action) with hideCardWhenWindowOpen"
      )

      let keeping = resolver(left: action, right: nil, hideCardWhenWindowOpen: false)
      XCTAssertEqual(
        keeping.resolveEnd(translation: -120, velocity: 0, isActionEnabled: allEnabled),
        .perform(action, hidesCard: expectedWhenKeepingOpenWindows[action]!),
        "\(action) without hideCardWhenWindowOpen"
      )
    }
  }

  // MARK: - Swipe action store

  func testSwipeActionStore_defaultsBothDirectionsToDismiss() {
    let (store, _) = makeSwipeStore()

    XCTAssertEqual(store.action(for: .left), .dismiss)
    XCTAssertEqual(store.action(for: .right), .dismiss)
  }

  func testSwipeActionStore_persistsNoneAndExplicitActions() {
    let (store, defaults) = makeSwipeStore()

    store.setAction(.left, action: nil)
    store.setAction(.right, action: .copy)

    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.quickAccessSwipeLeftAction), "none")
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.quickAccessSwipeRightAction), "copy")

    let reloaded = QuickAccessSwipeActionStore(defaults: defaults)
    Self.retainedSwipeStores.append(reloaded)
    XCTAssertNil(reloaded.action(for: .left))
    XCTAssertEqual(reloaded.action(for: .right), .copy)
  }

  func testSwipeActionStore_unknownSavedValueLoadsAsNoAction() {
    let (_, defaults) = makeSwipeStore()
    defaults.set("doesNotExist", forKey: PreferencesKeys.quickAccessSwipeLeftAction)

    let store = QuickAccessSwipeActionStore(defaults: defaults)
    Self.retainedSwipeStores.append(store)

    XCTAssertNil(store.action(for: .left))
    XCTAssertEqual(store.action(for: .right), .dismiss)
  }

  func testSwipeActionStore_resetRestoresDismiss() {
    let (store, _) = makeSwipeStore()
    store.setAction(.left, action: .edit)
    store.setAction(.right, action: nil)

    store.resetToDefaults()

    XCTAssertEqual(store.action(for: .left), .dismiss)
    XCTAssertEqual(store.action(for: .right), .dismiss)
  }

  // MARK: - Placement

  func testPosition_sideAndDismissDirection() {
    XCTAssertTrue(QuickAccessPosition.topLeft.isLeftSide)
    XCTAssertTrue(QuickAccessPosition.bottomLeft.isLeftSide)
    XCTAssertFalse(QuickAccessPosition.topRight.isLeftSide)
    XCTAssertFalse(QuickAccessPosition.bottomRight.isLeftSide)

    XCTAssertEqual(QuickAccessPosition.topLeft.dismissDirection, -1)
    XCTAssertEqual(QuickAccessPosition.bottomLeft.dismissDirection, -1)
    XCTAssertEqual(QuickAccessPosition.topRight.dismissDirection, 1)
    XCTAssertEqual(QuickAccessPosition.bottomRight.dismissDirection, 1)

    XCTAssertEqual(QuickAccessPosition.fromSide(true), .bottomLeft)
    XCTAssertEqual(QuickAccessPosition.fromSide(true, preferTop: true), .topLeft)
    XCTAssertEqual(QuickAccessPosition.fromSide(false), .bottomRight)
    XCTAssertEqual(QuickAccessPosition.fromSide(false, preferTop: true), .topRight)
  }

  func testPosition_originsHugTheirCornerWithPadding() throws {
    let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first, "No screen available")
    let frame = screen.visibleFrame
    let size = CGSize(width: 204, height: 620)

    XCTAssertEqual(
      QuickAccessPosition.bottomRight.calculateOrigin(for: size, on: screen, padding: 20),
      CGPoint(x: frame.maxX - 204 - 20, y: frame.minY + 20)
    )
    XCTAssertEqual(
      QuickAccessPosition.bottomLeft.calculateOrigin(for: size, on: screen, padding: 20),
      CGPoint(x: frame.minX + 20, y: frame.minY + 20)
    )
    XCTAssertEqual(
      QuickAccessPosition.topRight.calculateOrigin(for: size, on: screen, padding: 20),
      CGPoint(x: frame.maxX - 204 - 20, y: frame.maxY - 620 - 20)
    )
    XCTAssertEqual(
      QuickAccessPosition.topLeft.calculateOrigin(for: size, on: screen, padding: 20),
      CGPoint(x: frame.minX + 20, y: frame.maxY - 620 - 20)
    )
  }

  func testPosition_offscreenOriginsSitFullyPastTheirEdge() throws {
    let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first, "No screen available")
    let frame = screen.visibleFrame
    let size = CGSize(width: 204, height: 620)

    for position in QuickAccessPosition.allCases {
      let onscreen = position.calculateOrigin(for: size, on: screen, padding: 20)
      let offscreen = position.offscreenOrigin(for: size, on: screen, padding: 20)
      XCTAssertEqual(offscreen.y, onscreen.y, "\(position) slides horizontally only")
      if position.isLeftSide {
        XCTAssertLessThanOrEqual(offscreen.x + size.width, frame.minX, "\(position)")
      } else {
        XCTAssertGreaterThanOrEqual(offscreen.x, frame.maxX, "\(position)")
      }
    }
  }

  // MARK: - Stack visibility

  func testItemShownInPanel_hidesOnlyOpenWindowsWhenPreferenceIsOn() {
    var item = QuickAccessItem(
      url: URL(fileURLWithPath: "/tmp/demo.png"),
      thumbnail: NSImage(size: CGSize(width: 16, height: 16))
    )

    XCTAssertTrue(item.isShownInPanel(hideCardWhenWindowOpen: true))
    XCTAssertTrue(item.isShownInPanel(hideCardWhenWindowOpen: false))

    item.isWindowOpen = true
    XCTAssertFalse(item.isShownInPanel(hideCardWhenWindowOpen: true))
    XCTAssertTrue(item.isShownInPanel(hideCardWhenWindowOpen: false))

    item.isPinned = true
    XCTAssertFalse(item.isShownInPanel(hideCardWhenWindowOpen: true))
  }

  // MARK: - Card actions and shortcuts (locked before adding collapse-to-edge)

  func testActionDefaults_existingShortcutsAreUnchanged() {
    let expected: [QuickAccessActionKind: ShortcutConfig] = [
      .copy: ShortcutConfig(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey)),
      .saveOrOpen: ShortcutConfig(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey)),
      .edit: ShortcutConfig(keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(cmdKey)),
      .uploadToCloud: ShortcutConfig(keyCode: UInt32(kVK_ANSI_U), modifiers: UInt32(cmdKey)),
      .pinToScreen: ShortcutConfig(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey)),
      .optimize: ShortcutConfig(keyCode: UInt32(kVK_ANSI_O), modifiers: UInt32(cmdKey)),
      .delete: ShortcutConfig(keyCode: UInt32(kVK_Delete), modifiers: UInt32(cmdKey)),
      .dismiss: ShortcutConfig(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(cmdKey)),
    ]

    for (action, shortcut) in expected {
      XCTAssertEqual(QuickAccessActionShortcutStore.defaultShortcuts[action], shortcut, "\(action)")
    }
  }

  func testActionDefaults_existingOrderSlotsAndPlacementAreUnchanged() {
    XCTAssertEqual(
      Array(QuickAccessActionKind.defaultOrder.prefix(8)),
      [.copy, .saveOrOpen, .dismiss, .delete, .edit, .uploadToCloud, .pinToScreen, .optimize]
    )
    XCTAssertEqual(QuickAccessActionSlot.defaultAssignments, [
      .centerTop: .copy,
      .centerBottom: .saveOrOpen,
      .topTrailing: .dismiss,
      .topLeading: .delete,
      .bottomLeading: .edit,
      .bottomTrailing: .uploadToCloud,
    ])
    XCTAssertEqual(QuickAccessActionKind.copy.displayStyle, .primary)
    XCTAssertEqual(QuickAccessActionKind.saveOrOpen.displayStyle, .primary)
    for action in [QuickAccessActionKind.dismiss, .delete, .edit, .uploadToCloud, .pinToScreen, .optimize] {
      XCTAssertEqual(action.displayStyle, .corner, "\(action)")
    }
    XCTAssertEqual(
      QuickAccessActionKind.allCases.filter(\.isContextMenuDestructiveGroup),
      [.dismiss, .delete]
    )
  }
}
