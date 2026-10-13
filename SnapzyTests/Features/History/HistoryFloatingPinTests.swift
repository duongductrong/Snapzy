//
//  HistoryFloatingPinTests.swift
//  SnapzyTests
//
//  Unit tests for History Floating Panel pin functionality (Issue #552).
//

import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Snapzy

@MainActor
final class HistoryFloatingPinTests: XCTestCase {

  override func setUp() async throws {
    try await super.setUp()
    HistoryFloatingManager.shared.hide()
  }

  override func tearDown() async throws {
    HistoryFloatingManager.shared.hide()
    try await super.tearDown()
  }

  // MARK: - Manager Pin State

  func testInitialPinState_isFalse() {
    XCTAssertFalse(HistoryFloatingManager.shared.isPinned)
  }

  func testTogglePin_togglesState() {
    let manager = HistoryFloatingManager.shared
    XCTAssertFalse(manager.isPinned)

    manager.togglePin()
    XCTAssertTrue(manager.isPinned)

    manager.togglePin()
    XCTAssertFalse(manager.isPinned)
  }

  func testHide_resetsPinnedState() {
    let manager = HistoryFloatingManager.shared
    manager.togglePin()
    XCTAssertTrue(manager.isPinned)

    manager.hide()
    XCTAssertFalse(manager.isPinned)
  }

  // MARK: - Panel Window Level

  func testPanelWindowLevel_elevatesWhenPinned() {
    let panel = HistoryFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200))
    XCTAssertEqual(panel.level, .floating)

    panel.updateWindowLevel(isPinned: true)
    let expectedPinnedLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
    XCTAssertEqual(panel.level, expectedPinnedLevel)

    // Higher than AnnotateWindow.activeEditorLevel (.floating + 1)
    let annotateActiveLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    XCTAssertGreaterThan(panel.level.rawValue, annotateActiveLevel.rawValue)

    panel.updateWindowLevel(isPinned: false)
    XCTAssertEqual(panel.level, .floating)
  }

  func testLocalArrowMonitorRoutesAppDispatchedPanelArrow() throws {
    let panel = HistoryFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200))
    panel.makeKeyAndOrderFront(nil)
    panel.installLocalArrowEventMonitor()
    defer {
      panel.removeLocalArrowEventMonitor()
      panel.close()
    }

    XCTAssertTrue(panel.isKeyWindow)
    let expectation = expectation(forNotification: .historyMoveFocus, object: panel) { notification in
      notification.userInfo?["keyCode"] as? UInt16 == 124 &&
        notification.userInfo?["extendsSelection"] as? Bool == false
    }

    NSApp.sendEvent(
      try makeArrowEvent(
        keyCode: 124,
        modifiers: [.numericPad, .function],
        windowNumber: panel.windowNumber
      )
    )
    wait(for: [expectation], timeout: 1.0)
  }

  func testLocalArrowMonitorRoutesShiftAppDispatchedPanelArrow() throws {
    let panel = HistoryFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200))
    panel.makeKeyAndOrderFront(nil)
    panel.installLocalArrowEventMonitor()
    defer {
      panel.removeLocalArrowEventMonitor()
      panel.close()
    }

    let expectation = expectation(forNotification: .historyMoveFocus, object: panel) { notification in
      notification.userInfo?["keyCode"] as? UInt16 == 125 &&
        notification.userInfo?["extendsSelection"] as? Bool == true
    }

    NSApp.sendEvent(
      try makeArrowEvent(
        keyCode: 125,
        modifiers: [.numericPad, .function, .shift],
        windowNumber: panel.windowNumber
      )
    )
    wait(for: [expectation], timeout: 1.0)
  }

  func testLocalArrowMonitorPassesSearchTextInputArrowThrough() throws {
    let panel = HistoryFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200))
    panel.makeKeyAndOrderFront(nil)
    let searchField = NSSearchField(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
    searchField.stringValue = "abcdef"
    panel.contentView?.addSubview(searchField)
    XCTAssertTrue(panel.makeFirstResponder(searchField))
    let fieldEditor = try XCTUnwrap(searchField.currentEditor() as? NSTextView)
    XCTAssertTrue(panel.firstResponder === fieldEditor)
    fieldEditor.setSelectedRange(NSRange(location: 3, length: 0))
    panel.installLocalArrowEventMonitor()
    defer {
      panel.removeLocalArrowEventMonitor()
      panel.close()
    }

    NSApp.sendEvent(
      try makeArrowEvent(
        keyCode: 123,
        modifiers: [.numericPad, .function],
        windowNumber: panel.windowNumber
      )
    )

    XCTAssertEqual(fieldEditor.selectedRange().location, 2)
  }

  func testLocalArrowMonitorDoesNotRouteArrowTargetedAtAnotherWindow() throws {
    let panel = HistoryFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200))
    let otherWindow = KeyableHistoryTestPanel(contentRect: NSRect(x: 300, y: 300, width: 100, height: 100))
    let otherWindowTextView = ArrowTrackingHistoryTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
    otherWindow.contentView?.addSubview(otherWindowTextView)
    panel.makeKeyAndOrderFront(nil)
    panel.installLocalArrowEventMonitor()
    otherWindow.makeKeyAndOrderFront(nil)
    defer {
      panel.removeLocalArrowEventMonitor()
      panel.close()
      otherWindow.close()
    }

    XCTAssertTrue(otherWindow.isKeyWindow)
    XCTAssertFalse(panel.isKeyWindow)
    XCTAssertTrue(otherWindow.makeFirstResponder(otherWindowTextView))
    XCTAssertTrue(otherWindow.firstResponder === otherWindowTextView)

    let unexpectedNotification = expectation(forNotification: .historyMoveFocus, object: panel, handler: nil)
    unexpectedNotification.isInverted = true

    NSApp.sendEvent(
      try makeArrowEvent(
        keyCode: 124,
        modifiers: [.numericPad, .function],
        windowNumber: otherWindow.windowNumber
      )
    )

    wait(for: [unexpectedNotification], timeout: 0.1)
    XCTAssertTrue(otherWindowTextView.didReceiveArrowKeyDown)
  }

  // MARK: - Shortcut Handling (⌘P)

  func testCmdPTogglesPin() {
    let manager = HistoryFloatingManager.shared
    let panel = HistoryFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200))

    XCTAssertFalse(manager.isPinned)

    let event = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: .command,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "p",
      charactersIgnoringModifiers: "p",
      isARepeat: false,
      keyCode: 35
    )

    guard let event else {
      XCTFail("Failed to create Cmd+P event")
      return
    }

    let handled = panel.performKeyEquivalent(with: event)
    XCTAssertTrue(handled)
    XCTAssertTrue(manager.isPinned)

    let handledSecond = panel.performKeyEquivalent(with: event)
    XCTAssertTrue(handledSecond)
    XCTAssertFalse(manager.isPinned)
  }

  func testCmdP_ignoredWhenTextInputActive() {
    let manager = HistoryFloatingManager.shared
    let panel = HistoryFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200))

    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
    panel.contentView?.addSubview(textView)
    let madeFirstResponder = panel.makeFirstResponder(textView)
    XCTAssertTrue(madeFirstResponder)

    XCTAssertFalse(manager.isPinned)

    let event = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: .command,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "p",
      charactersIgnoringModifiers: "p",
      isARepeat: false,
      keyCode: 35
    )

    guard let event else {
      XCTFail("Failed to create Cmd+P event")
      return
    }

    let handled = panel.performKeyEquivalent(with: event)
    XCTAssertFalse(handled)
    XCTAssertFalse(manager.isPinned)
  }

  // MARK: - Localization

  func testPinLocalizationKeys_existAndAreNonEmpty() {
    let pinTitle = L10n.PreferencesHistory.pinPanel
    let unpinTitle = L10n.PreferencesHistory.unpinPanel

    XCTAssertFalse(pinTitle.isEmpty)
    XCTAssertFalse(unpinTitle.isEmpty)
    XCTAssertTrue(pinTitle.contains("⌘P"))
    XCTAssertTrue(unpinTitle.contains("⌘P"))
  }

  private func makeArrowEvent(
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags,
    windowNumber: Int
  ) throws -> NSEvent {
    let characters: String
    switch keyCode {
    case 123: characters = "\u{F702}"
    case 124: characters = "\u{F703}"
    case 125: characters = "\u{F701}"
    case 126: characters = "\u{F700}"
    default: throw XCTSkip("Expected an arrow key code, got \(keyCode)")
    }

    return try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: 0,
        windowNumber: windowNumber,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: false,
        keyCode: keyCode
      )
    )
  }
}

@MainActor
private final class ArrowTrackingHistoryTextView: NSTextView {
  private(set) var didReceiveArrowKeyDown = false

  override func keyDown(with event: NSEvent) {
    if HistoryFloatingNavigationDirection(keyCode: event.keyCode) != nil {
      didReceiveArrowKeyDown = true
    }
    super.keyDown(with: event)
  }
}

@MainActor
private final class KeyableHistoryTestPanel: NSPanel {
  override var canBecomeKey: Bool { true }

  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
  }
}
