//
//  VideoEditorWindowInputTests.swift
//  SnapzyTests
//
//  Regression tests for editor-window key-equivalent routing.
//

import AppKit
@testable import Snapzy
import XCTest

@MainActor
final class VideoEditorWindowInputTests: XCTestCase {
  func testUnhandledCommandCIsConsumedWithoutFallingThroughToWindowKeyDown() {
    let window = VideoEditorWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 300)
    )
    guard let event = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [.command],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      characters: "c",
      charactersIgnoringModifiers: "c",
      isARepeat: false,
      keyCode: 8
    ) else {
      XCTFail("Could not create Command-C event")
      return
    }

    XCTAssertTrue(window.performKeyEquivalent(with: event))
  }
}
