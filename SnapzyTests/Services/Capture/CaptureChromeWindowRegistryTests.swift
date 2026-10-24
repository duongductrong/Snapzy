//
//  CaptureChromeWindowRegistryTests.swift
//  SnapzyTests
//
//  Unit tests for capture chrome window registration and role filtering.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class CaptureChromeWindowRegistryTests: XCTestCase {

  func testWindowIDs_filtersByRole() {
    let registry = CaptureChromeWindowRegistry()
    let overlay = makeWindow()
    let controls = makeWindow()
    defer { overlay.close(); controls.close() }

    registry.register(overlay, role: .captureOverlay)
    registry.register(controls, role: .recordingControls)

    XCTAssertEqual(registry.windowIDs(roles: [.captureOverlay]), [CGWindowID(overlay.windowNumber)])
    XCTAssertEqual(registry.windowIDs(roles: [.recordingControls]), [CGWindowID(controls.windowNumber)])
    XCTAssertEqual(
      registry.windowIDs(),
      [CGWindowID(overlay.windowNumber), CGWindowID(controls.windowNumber)]
    )
  }

  func testUnregister_removesWindowAndNotifies() {
    let registry = CaptureChromeWindowRegistry()
    let window = makeWindow()
    defer { window.close() }
    var changes = 0
    registry.onChange = { changes += 1 }

    registry.register(window, role: .captureOverlay)
    registry.unregister(window)
    registry.unregister(window)

    XCTAssertTrue(registry.windowIDs().isEmpty)
    XCTAssertEqual(changes, 2)
  }

  func testReleasedWindow_isDropped() {
    let registry = CaptureChromeWindowRegistry()
    autoreleasepool {
      let window = makeWindow()
      registry.register(window, role: .captureOverlay)
      XCTAssertEqual(registry.windowIDs().count, 1)
      window.close()
    }

    XCTAssertTrue(registry.windowIDs().isEmpty)
  }

  func testConfigure_registersWithSharedRegistry() throws {
    let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
    let window = AreaSelectionWindow(screen: screen, pooled: true)
    defer { window.close() }

    XCTAssertTrue(
      CaptureChromeWindowRegistry.shared.windowIDs(roles: [.captureOverlay])
        .contains(CGWindowID(window.windowNumber))
    )
  }

  func testAppWindowSharingType_visibleWhenEitherPrefIncludesOwnApp() {
    XCTAssertEqual(
      CaptureChromeWindowRegistry.appWindowSharingType(includeInScreenshots: false, includeInRecordings: false),
      .none
    )
    XCTAssertEqual(
      CaptureChromeWindowRegistry.appWindowSharingType(includeInScreenshots: true, includeInRecordings: false),
      .readOnly
    )
    XCTAssertEqual(
      CaptureChromeWindowRegistry.appWindowSharingType(includeInScreenshots: false, includeInRecordings: true),
      .readOnly
    )
  }

  func testRegister_sameRoleTwice_notifiesOnce() {
    let registry = CaptureChromeWindowRegistry()
    let window = makeWindow()
    defer { window.close() }
    var changes = 0
    registry.onChange = { changes += 1 }

    registry.register(window, role: .appWindow)
    registry.register(window, role: .appWindow)

    XCTAssertEqual(changes, 1)
  }

  func testConfigure_makesChromeVisibleToRecorders() throws {
    let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
    let window = SmartElementOverlayWindow(screen: screen)
    defer { window.close() }

    XCTAssertEqual(window.sharingType, .readOnly)
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    return window
  }
}
