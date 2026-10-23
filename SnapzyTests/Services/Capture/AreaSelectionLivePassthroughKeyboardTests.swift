//
//  AreaSelectionLivePassthroughKeyboardTests.swift
//  SnapzyTests
//
//  Regression coverage for https://github.com/duongductrong/Snapzy/issues/635: a passthrough
//  overlay that took key status resigned the key window of the app beneath, and Qt apps
//  (DaVinci Resolve) dismiss their tooltips on that deactivation — so OCR never saw them.
//  The overlay now stays non-key and keystrokes arrive through the capture event tap; these
//  tests pin which keys the session consumes so none reaches (and dismisses hover UI in)
//  the app beneath.
//

import AppKit
@testable import Snapzy
import XCTest

final class AreaSelectionLivePassthroughKeyboardTests: XCTestCase {
  override func tearDown() {
    AreaSelectionController.shared.cancelSelection()
    super.tearDown()
  }

  private func startSession(completion: @escaping AreaSelectionResultCompletion = { _ in }) throws -> AreaSelectionController {
    try skipIfRunningInCI(
      "Presents real overlay windows via the shared AreaSelectionController, which is flaky on headless CI runners"
    )
    let controller = AreaSelectionController.shared
    controller.startSelection(mode: .screenshot, backdrops: [:], completion: completion)
    guard !NSScreen.screens.isEmpty else {
      controller.cancelSelection()
      throw XCTSkip("no screens (headless host)")
    }
    return controller
  }

  private func keyEvent(_ keyCode: CGKeyCode, down: Bool = true, flags: CGEventFlags = []) throws -> CGEvent {
    let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down))
    event.flags = flags
    return event
  }

  func testEscape_isConsumedAndCancelsSession() throws {
    var cancelled = false
    let controller = try startSession { result in cancelled = result == nil }

    XCTAssertTrue(controller.testHandleLivePassthroughKey(try keyEvent(53)))
    XCTAssertTrue(cancelled)
    XCTAssertFalse(controller.isPresenting)
  }

  func testUnhandledPlainKeys_areConsumedSoTheAppBeneathNeverSeesThem() throws {
    let controller = try startSession()

    XCTAssertTrue(controller.testHandleLivePassthroughKey(try keyEvent(7)), "plain 'x' keyDown")
    XCTAssertTrue(controller.testHandleLivePassthroughKey(try keyEvent(7, down: false)), "plain 'x' keyUp")
    XCTAssertTrue(controller.testHandleLivePassthroughKey(try keyEvent(49)), "Space with no drag in progress")
    XCTAssertTrue(controller.testHandleLivePassthroughKey(try keyEvent(123)), "arrow key")
    XCTAssertTrue(controller.isPresenting, "unhandled keys must not end the session")
  }

  func testUnhandledCommandChords_passThrough() throws {
    let controller = try startSession()

    XCTAssertFalse(controller.testHandleLivePassthroughKey(try keyEvent(48, flags: .maskCommand)), "⌘Tab down")
    XCTAssertFalse(
      controller.testHandleLivePassthroughKey(try keyEvent(48, down: false, flags: .maskCommand)),
      "the keyUp of a passed-through keyDown follows it"
    )
    XCTAssertTrue(controller.isPresenting)
  }

  /// The capture hotkey's keyDown fires before the session (and its tap) exist, so its keyUp
  /// arrives with no keyDown seen. Swallowing it leaves the WindowServer treating the hotkey as
  /// held, and the next press of the same shortcut is dropped — every second press did nothing.
  func testHotkeyKeyUp_withoutKeyDownInSession_passesThrough() throws {
    let controller = try startSession()

    XCTAssertFalse(controller.testHandleLivePassthroughKey(try keyEvent(21, down: false, flags: [.maskCommand, .maskShift])))
    XCTAssertTrue(controller.isPresenting)
  }
}
