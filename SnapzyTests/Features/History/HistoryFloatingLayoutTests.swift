//
//  HistoryFloatingLayoutTests.swift
//  SnapzyTests
//
//  Unit tests for HistoryFloatingLayout math and HistoryFloatingTimeFilter.
//

import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Snapzy

final class HistoryFloatingLayoutTests: XCTestCase {

  // MARK: - clampedScale

  func testClampedScale_clampsBelowMinimum() {
    XCTAssertEqual(HistoryFloatingLayout.clampedScale(0.1), 0.8)
    XCTAssertEqual(HistoryFloatingLayout.clampedScale(-5), 0.8)
  }

  func testClampedScale_clampsAboveMaximum() {
    XCTAssertEqual(HistoryFloatingLayout.clampedScale(2.0), 1.4)
    XCTAssertEqual(HistoryFloatingLayout.clampedScale(99), 1.4)
  }

  func testClampedScale_passesThroughValidRange() {
    XCTAssertEqual(HistoryFloatingLayout.clampedScale(0.8), 0.8)
    XCTAssertEqual(HistoryFloatingLayout.clampedScale(1.0), 1.0)
    XCTAssertEqual(HistoryFloatingLayout.clampedScale(1.25), 1.25)
    XCTAssertEqual(HistoryFloatingLayout.clampedScale(1.4), 1.4)
  }

  // MARK: - storedScale

  func testStoredScale_readsPersistedValue() throws {
    let defaults = try makeDefaults()
    defaults.set(1.25, forKey: PreferencesKeys.historyFloatingScale)

    XCTAssertEqual(HistoryFloatingLayout.storedScale(userDefaults: defaults), 1.25, accuracy: 0.0001)
  }

  func testStoredScale_clampsPersistedValue() throws {
    let defaults = try makeDefaults()
    defaults.set(5.0, forKey: PreferencesKeys.historyFloatingScale)

    XCTAssertEqual(HistoryFloatingLayout.storedScale(userDefaults: defaults), 1.4, accuracy: 0.0001)
  }

  func testStoredScale_defaultsToOneWhenMissing() throws {
    let defaults = try makeDefaults()
    XCTAssertEqual(HistoryFloatingLayout.storedScale(userDefaults: defaults), 1.0, accuracy: 0.0001)
  }

  // MARK: - basePanelSize

  func testBasePanelSize_compact() {
    let size = HistoryFloatingLayout.basePanelSize(for: .compact)
    XCTAssertEqual(size, CGSize(width: 920, height: 316))
  }

  func testBasePanelSize_expanded() {
    let size = HistoryFloatingLayout.basePanelSize(for: .expanded)
    XCTAssertEqual(size, CGSize(width: 1040, height: 680))
  }

  // MARK: - baseCornerRadius

  func testBaseCornerRadius_compact() {
    XCTAssertEqual(HistoryFloatingLayout.baseCornerRadius(for: .compact), 30)
  }

  func testBaseCornerRadius_expanded() {
    XCTAssertEqual(HistoryFloatingLayout.baseCornerRadius(for: .expanded), 32)
  }

  // MARK: - HistoryFloatingTimeFilter

  func testTimeFilterAllIncludesAnyDate() {
    let now = Date()
    XCTAssertTrue(HistoryFloatingTimeFilter.all.includes(now.addingTimeInterval(-1_000_000), relativeTo: now))
    XCTAssertTrue(HistoryFloatingTimeFilter.all.includes(now.addingTimeInterval(100), relativeTo: now))
  }

  func testTimeFilterLast24HoursExcludesOlder() {
    let now = Date()
    XCTAssertTrue(HistoryFloatingTimeFilter.last24Hours.includes(now.addingTimeInterval(-3600), relativeTo: now))
    XCTAssertFalse(HistoryFloatingTimeFilter.last24Hours.includes(now.addingTimeInterval(-100_000), relativeTo: now))
  }

  func testTimeFilterLast7DaysExcludesOlder() {
    let now = Date()
    XCTAssertTrue(HistoryFloatingTimeFilter.last7Days.includes(now.addingTimeInterval(-100_000), relativeTo: now))
    XCTAssertFalse(HistoryFloatingTimeFilter.last7Days.includes(now.addingTimeInterval(-1_000_000), relativeTo: now))
  }

  func testTimeFilterLast30DaysExcludesOlder() {
    let now = Date()
    XCTAssertTrue(HistoryFloatingTimeFilter.last30Days.includes(now.addingTimeInterval(-1_000_000), relativeTo: now))
    XCTAssertFalse(HistoryFloatingTimeFilter.last30Days.includes(now.addingTimeInterval(-10_000_000), relativeTo: now))
  }

  func testTimeFilterAllCasesAreUnique() {
    let all = HistoryFloatingTimeFilter.allCases
    XCTAssertEqual(Set(all).count, all.count)
  }

  // MARK: - HistoryFloatingPresentationMode

  func testPresentationModeEquality() {
    XCTAssertEqual(HistoryFloatingPresentationMode.compact, HistoryFloatingPresentationMode.compact)
    XCTAssertNotEqual(HistoryFloatingPresentationMode.compact, HistoryFloatingPresentationMode.expanded)
  }

  // MARK: - Toggle Mode Shortcut

  func testToggleModeShortcutDefaultAndCustomization() {
    let manager = HistoryFloatingManager.shared
    
    // Test default shortcut values
    XCTAssertEqual(HistoryFloatingManager.defaultToggleModeShortcut.keyCode, UInt32(kVK_ANSI_E))
    XCTAssertEqual(HistoryFloatingManager.defaultToggleModeShortcut.modifiers, UInt32(cmdKey))
    XCTAssertTrue(manager.isToggleModeShortcutEnabled)
    
    // Set custom shortcut
    let custom = ShortcutConfig(keyCode: UInt32(kVK_ANSI_X), modifiers: UInt32(cmdKey | shiftKey))
    manager.toggleModeShortcut = custom
    XCTAssertEqual(manager.toggleModeShortcut, custom)
    
    // Disable shortcut row (turn off)
    manager.isToggleModeShortcutEnabled = false
    XCTAssertFalse(manager.isToggleModeShortcutEnabled)
    // Custom shortcut config must remain intact when disabled
    XCTAssertEqual(manager.toggleModeShortcut, custom)
    
    // Check if it persists and can be loaded
    let savedData = UserDefaults.standard.data(forKey: "history.toggleModeShortcut")
    XCTAssertNotNil(savedData)
    if let savedData = savedData {
      let config = try? JSONDecoder().decode(ShortcutConfig.self, from: savedData)
      XCTAssertEqual(config, custom)
    }
    
    let savedEnabled = UserDefaults.standard.object(forKey: "history.isToggleModeShortcutEnabled") as? Bool
    XCTAssertEqual(savedEnabled, false)
    
    // Reset to default
    manager.resetToggleModeShortcut()
    XCTAssertEqual(manager.toggleModeShortcut, HistoryFloatingManager.defaultToggleModeShortcut)
    XCTAssertTrue(manager.isToggleModeShortcutEnabled)
  }

  func testHistoryFloatingPanelCmdAPostNotification() {
    let panel = HistoryFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100))
    let expectation = expectation(forNotification: .historySelectAll, object: panel, handler: nil)
    
    let event = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: .command,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "a",
      charactersIgnoringModifiers: "a",
      isARepeat: false,
      keyCode: 0
    )
    
    guard let event = event else {
      XCTFail("Failed to create Cmd+A event")
      return
    }
    
    let handled = panel.performKeyEquivalent(with: event)
    XCTAssertTrue(handled)
    
    wait(for: [expectation], timeout: 1.0)
  }

  func testHistoryFloatingPanelCmdANoNotificationWhenTextInputActive() {
    let panel = HistoryFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100))
    
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
    panel.contentView?.addSubview(textView)
    let madeFirstResponder = panel.makeFirstResponder(textView)
    XCTAssertTrue(madeFirstResponder)
    
    let observer = NotificationCenter.default.addObserver(
      forName: .historySelectAll,
      object: panel,
      queue: nil
    ) { _ in
      XCTFail("Notification should not be posted when text input is active")
    }
    defer {
      NotificationCenter.default.removeObserver(observer)
    }
    
    let event = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: .command,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "a",
      charactersIgnoringModifiers: "a",
      isARepeat: false,
      keyCode: 0
    )
    
    guard let event = event else {
      XCTFail("Failed to create Cmd+A event")
      return
    }
    
    let handled = panel.performKeyEquivalent(with: event)
    XCTAssertFalse(handled)
  }

  func testHistoryFloatingPanelRoutesPlainArrowToFloatingContent() throws {
    let panel = HistoryFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100))
    let expectation = expectation(forNotification: .historyMoveFocus, object: panel) { notification in
      notification.userInfo?["keyCode"] as? UInt16 == 124 &&
        notification.userInfo?["extendsSelection"] as? Bool == false
    }
    let event = try XCTUnwrap(
      makeArrowEvent(
        keyCode: 124,
        modifiers: [.numericPad, .function, .capsLock],
        windowNumber: panel.windowNumber
      )
    )

    panel.sendEvent(event)
    wait(for: [expectation], timeout: 1.0)
  }

  func testHistoryFloatingPanelRoutesShiftArrowToFloatingContent() throws {
    let panel = HistoryFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100))
    let expectation = expectation(forNotification: .historyMoveFocus, object: panel) { notification in
      notification.userInfo?["keyCode"] as? UInt16 == 125 &&
        notification.userInfo?["extendsSelection"] as? Bool == true
    }
    let event = try XCTUnwrap(
      makeArrowEvent(
        keyCode: 125,
        modifiers: [.numericPad, .function, .shift],
        windowNumber: panel.windowNumber
      )
    )

    panel.sendEvent(event)
    wait(for: [expectation], timeout: 1.0)
  }

  func testHistoryFloatingPanelDoesNotRouteArrowsWhileTextInputIsActive() throws {
    let panel = HistoryFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100))
    let textView = ArrowTrackingTextView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
    panel.contentView?.addSubview(textView)
    XCTAssertTrue(panel.makeFirstResponder(textView))

    let observer = NotificationCenter.default.addObserver(
      forName: .historyMoveFocus,
      object: panel,
      queue: nil
    ) { _ in
      XCTFail("Arrow events should remain with the active text input")
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    panel.sendEvent(
      try XCTUnwrap(
        makeArrowEvent(
          keyCode: 123,
          modifiers: [.numericPad, .function],
          windowNumber: panel.windowNumber
        )
      )
    )
    XCTAssertTrue(textView.didReceiveArrowKeyDown)
  }

  func testHistoryFloatingPanelKeepsEnterCopyAndDeleteRoutes() throws {
    let panel = HistoryFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100))
    let activation = expectation(forNotification: .historyActivateSelection, object: panel, handler: nil)
    panel.keyDown(with: try XCTUnwrap(makeArrowEvent(keyCode: 36, modifiers: [])))

    let deletion = expectation(forNotification: .historyDeleteSelection, object: panel, handler: nil)
    panel.keyDown(with: try XCTUnwrap(makeArrowEvent(keyCode: 51, modifiers: [])))

    let copying = expectation(forNotification: .historyCopySelection, object: panel, handler: nil)
    let copyEvent = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: .command,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "c",
      charactersIgnoringModifiers: "c",
      isARepeat: false,
      keyCode: 8
    )
    XCTAssertTrue(panel.performKeyEquivalent(with: try XCTUnwrap(copyEvent)))
    wait(for: [activation, deletion, copying], timeout: 1.0)
  }

  // MARK: - Helpers

  private func makeDefaults(
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws -> UserDefaults {
    let suiteName = "SnapzyTests.HistoryFloatingLayoutTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName), file: file, line: line)
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }

  private func makeArrowEvent(
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags,
    windowNumber: Int = 0
  ) -> NSEvent? {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: modifiers,
      timestamp: 0,
      windowNumber: windowNumber,
      context: nil,
      characters: "",
      charactersIgnoringModifiers: "",
      isARepeat: false,
      keyCode: keyCode
    )
  }
}

private final class ArrowTrackingTextView: NSTextView {
  private(set) var didReceiveArrowKeyDown = false

  override func keyDown(with event: NSEvent) {
    if HistoryFloatingNavigationDirection(keyCode: event.keyCode) != nil {
      didReceiveArrowKeyDown = true
    }
    super.keyDown(with: event)
  }
}
