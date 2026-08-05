//
//  AreaSelectionOverlayMagnifierTests.swift
//  SnapzyTests
//
//  Unit tests for magnifier zoom-state mechanics: scroll-wheel input, min/max
//  clamping, and reverse-direction setting.
//

import XCTest
import AppKit
@testable import Snapzy

final class AreaSelectionOverlayMagnifierTests: AreaSelectionOverlayTestCase {

  func testMagnifierZoom_scrollWheelAndLimits() {
    // GIVEN: A valid backdrop
    let image = createSolidColorImage(color: .white, size: CGSize(width: 800, height: 600))
    let backdrop = AreaSelectionBackdrop(displayID: 0, image: image, scaleFactor: 1.0)
    overlayView.applyBackdrop(backdrop)

    // WHEN: Scrolling with Command modifier
    overlayView.testScrollWheel(deltaY: 1.0, modifierFlags: .command)

    // THEN: Zoom should increase beyond 1.0 and magnifier layers should be created
    XCTAssertGreaterThan(overlayView.testMagnifierZoom, 1.0)

    guard let containerLayer = overlayView.testMagnifierContainerLayer else {
      XCTFail("magnifierContainerLayer not found")
      return
    }
    XCTAssertFalse(containerLayer.isHidden)

    // WHEN: Scrolling back down below 1.0
    overlayView.testScrollWheel(deltaY: -5.0, modifierFlags: .command)

    // THEN: Zoom clamps to 1.0 and magnifier layers are removed
    XCTAssertEqual(overlayView.testMagnifierZoom, 1.0)
    XCTAssertNil(overlayView.testMagnifierContainerLayer)
  }

  func testMagnifierZoom_reverseDirection() {
    let image = createSolidColorImage(color: .white, size: CGSize(width: 800, height: 600))
    let backdrop = AreaSelectionBackdrop(displayID: 0, image: image, scaleFactor: 1.0)
    overlayView.applyBackdrop(backdrop)

    // 1. GIVEN: Reverse zoom direction is OFF (false)
    overlayView.testReverseMagnifierZoomDirection = false
    overlayView.testScrollWheel(deltaY: 1.0, modifierFlags: .command)
    // Zoom should increase (1.0 + 1.0 = 2.0)
    XCTAssertEqual(overlayView.testMagnifierZoom, 2.0)

    // Reset zoom
    overlayView.clearBackdrop()
    overlayView.applyBackdrop(backdrop)

    // 2. GIVEN: Reverse zoom direction is ON (true)
    overlayView.testReverseMagnifierZoomDirection = true
    overlayView.testScrollWheel(deltaY: 1.0, modifierFlags: .command)
    // Zoom should decrease (but clamps at min zoom 1.0)
    XCTAssertEqual(overlayView.testMagnifierZoom, 1.0)

    // Scroll with negative delta (meaning zoom out under normal, so zoom in under reversed)
    overlayView.testScrollWheel(deltaY: -1.0, modifierFlags: .command)
    // Zoom should increase (1.0 + 1.0 = 2.0)
    XCTAssertEqual(overlayView.testMagnifierZoom, 2.0)
  }

  func testCopyColorToClipboard_copiesSampledHexWhenActive() {
    let image = createSolidColorImage(color: .black, size: CGSize(width: 800, height: 600))
    let backdrop = AreaSelectionBackdrop(displayID: 0, image: image, scaleFactor: 1.0)
    overlayView.applyBackdrop(backdrop)

    overlayView.testMagnifierZoom = 5.0
    overlayView.testUpdateMagnifier(at: CGPoint(x: 200, y: 150))

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("unchanged", forType: .string)

    XCTAssertTrue(overlayView.testCopyMagnifierColor())
    XCTAssertEqual(pasteboard.string(forType: .string), "#000000")
  }

  func testCopyColorToClipboard_returnsFalseWhenInactive() {
    let image = createSolidColorImage(color: .black, size: CGSize(width: 800, height: 600))
    let backdrop = AreaSelectionBackdrop(displayID: 0, image: image, scaleFactor: 1.0)
    overlayView.applyBackdrop(backdrop)

    // Magnifier never activated (zoom stays at 1.0) — nothing to copy
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("unchanged", forType: .string)

    XCTAssertFalse(overlayView.testCopyMagnifierColor())
    XCTAssertEqual(pasteboard.string(forType: .string), "unchanged")
  }

  func testCopyMagnifierColorIfActive_plainCKeyCopiesColor() {
    let image = createSolidColorImage(color: .black, size: CGSize(width: 800, height: 600))
    let backdrop = AreaSelectionBackdrop(displayID: 0, image: image, scaleFactor: 1.0)
    overlayView.applyBackdrop(backdrop)
    overlayView.testMagnifierZoom = 5.0
    overlayView.testUpdateMagnifier(at: CGPoint(x: 200, y: 150))

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("unchanged", forType: .string)

    let event = try! XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "c",
      charactersIgnoringModifiers: "c",
      isARepeat: false,
      keyCode: 8 // kVK_ANSI_C
    ))

    XCTAssertTrue(overlayView.copyMagnifierColorIfActive(for: event))
    XCTAssertEqual(pasteboard.string(forType: .string), "#000000")
  }

  func testResetMagnifierZoomForNewSession_respectsShowByDefaultPreference() {
    let originalValue = UserDefaults.standard.object(forKey: PreferencesKeys.screenshotShowMagnifierByDefault)
    defer {
      if let originalValue {
        UserDefaults.standard.set(originalValue, forKey: PreferencesKeys.screenshotShowMagnifierByDefault)
      } else {
        UserDefaults.standard.removeObject(forKey: PreferencesKeys.screenshotShowMagnifierByDefault)
      }
    }

    // GIVEN: The preference is off (the default) — a window newly entering a session
    // (whether via `clearBackdrop` or, for a frozen session, `applyBackdrop`) starts deactivated
    UserDefaults.standard.set(false, forKey: PreferencesKeys.screenshotShowMagnifierByDefault)
    overlayView.resetMagnifierZoomForNewSession()
    XCTAssertEqual(overlayView.testMagnifierZoom, 1.0)

    // WHEN: The preference is turned on and a new session starts
    UserDefaults.standard.set(true, forKey: PreferencesKeys.screenshotShowMagnifierByDefault)
    overlayView.resetMagnifierZoomForNewSession()

    // THEN: The magnifier starts already active — this must hold even for a frozen session
    // (e.g. screenshot-and-annotate) whose backdrop is already prepared before the window
    // shows, so this can't rely on `clearBackdrop` ever running.
    XCTAssertGreaterThan(overlayView.testMagnifierZoom, 1.0)
  }

  func testCopyMagnifierColorIfActive_ignoresOtherKeysAndModifiedC() {
    let image = createSolidColorImage(color: .black, size: CGSize(width: 800, height: 600))
    let backdrop = AreaSelectionBackdrop(displayID: 0, image: image, scaleFactor: 1.0)
    overlayView.applyBackdrop(backdrop)
    overlayView.testMagnifierZoom = 5.0
    overlayView.testUpdateMagnifier(at: CGPoint(x: 200, y: 150))

    // A different key entirely
    let otherKeyEvent = try! XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "v",
      charactersIgnoringModifiers: "v",
      isARepeat: false,
      keyCode: 9 // kVK_ANSI_V
    ))
    XCTAssertFalse(overlayView.copyMagnifierColorIfActive(for: otherKeyEvent))

    // Cmd+C should be left alone (e.g. so system copy semantics elsewhere aren't shadowed)
    let commandCEvent = try! XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [.command],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "c",
      charactersIgnoringModifiers: "c",
      isARepeat: false,
      keyCode: 8
    ))
    XCTAssertFalse(overlayView.copyMagnifierColorIfActive(for: commandCEvent))
  }
}
