//
//  ScrollingCaptureWindowSharingTests.swift
//  SnapzyTests
//
//  Unit tests for scrolling capture session chrome capture exclusion.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class ScrollingCaptureWindowSharingTests: XCTestCase {

  func testPreviewWindow_isExcludedFromScreenCapture() {
    let model = ScrollingCaptureSessionModel(selectedRect: sampleAnchorRect)
    let window = ScrollingCapturePreviewWindow(anchorRect: sampleAnchorRect, model: model)
    defer { window.close() }

    XCTAssertEqual(window.sharingType, NSWindow.SharingType.none)
  }

  func testHUDWindow_isExcludedFromScreenCapture() {
    let model = ScrollingCaptureSessionModel(selectedRect: sampleAnchorRect)
    let window = ScrollingCaptureHUDWindow(
      anchorRect: sampleAnchorRect,
      model: model,
      onStart: {},
      onDone: {},
      onCancel: {}
    )
    defer { window.close() }

    XCTAssertEqual(window.sharingType, NSWindow.SharingType.none)
  }

  private var sampleAnchorRect: CGRect {
    CGRect(x: 120, y: 120, width: 360, height: 480)
  }
}
