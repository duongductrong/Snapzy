//
//  AreaSelectionOverlayMagnifierLayoutTests.swift
//  SnapzyTests
//
//  Unit tests for magnifier layout and rendering: corner-flip positioning,
//  contentsRect centering, overlay-setting compatibility, and empty-backdrop fallback.
//

import XCTest
import AppKit
@testable import Snapzy

final class AreaSelectionOverlayMagnifierLayoutTests: AreaSelectionOverlayTestCase {

  func testMagnifierZoom_flipsNearCorners() {
    // GIVEN: A valid backdrop
    let image = createSolidColorImage(color: .white, size: CGSize(width: 800, height: 600))
    let backdrop = AreaSelectionBackdrop(displayID: 0, image: image, scaleFactor: 1.0)
    overlayView.applyBackdrop(backdrop)

    // Set zoom manually to 5x to trigger magnifier setup
    overlayView.testScrollWheel(deltaY: 4.0, modifierFlags: .command)

    // WHEN: Cursor is near bottom-left (10, 10)
    overlayView.mouseMoved(with: NSEvent.mouseEvent(
      with: .mouseMoved,
      location: CGPoint(x: 10, y: 10),
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      eventNumber: 0,
      clickCount: 0,
      pressure: 0
    )!)

    // THEN: Magnifier is placed at top-right (x = 10 + 20 = 30)
    guard let containerLayer = overlayView.testMagnifierContainerLayer else {
      XCTFail("magnifierContainerLayer not found")
      return
    }
    XCTAssertEqual(containerLayer.frame.origin.x, 30.0)

    // WHEN: Cursor is near top-right (790, 590) - screen bounds 800x600
    overlayView.mouseMoved(with: NSEvent.mouseEvent(
      with: .mouseMoved,
      location: CGPoint(x: 790, y: 590),
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      eventNumber: 0,
      clickCount: 0,
      pressure: 0
    )!)

    // THEN: Magnifier flips to top-left/bottom. Height is derived from live font metrics
    // (via `testMagnifierTotalHeight`) rather than hardcoded, so this doesn't silently drift
    // whenever a font or row size in the panel layout changes.
    let expectedWidth: CGFloat = 160
    let expectedHeight = overlayView.testMagnifierTotalHeight
    XCTAssertEqual(containerLayer.frame.origin.x, 790 - 20 - expectedWidth)
    XCTAssertEqual(containerLayer.frame.origin.y, 590 - 20 - expectedHeight)
  }

  func testMagnifierZoom_worksWithShowSelectionAreaOverlaySetting() {
    let image = createSolidColorImage(color: .white, size: CGSize(width: 800, height: 600))
    let backdrop = AreaSelectionBackdrop(displayID: 0, image: image, scaleFactor: 1.0)

    // 1. GIVEN: Show selection area overlay is ON (true)
    UserDefaults.standard.set(true, forKey: PreferencesKeys.screenshotShowSelectionAreaOverlay)
    overlayView.clearBackdrop()
    overlayView.applyBackdrop(backdrop)

    // WHEN: Zooming
    overlayView.testScrollWheel(deltaY: 1.0, modifierFlags: .command)

    // THEN: Zoom works and magnifier container layer is shown
    XCTAssertGreaterThan(overlayView.testMagnifierZoom, 1.0)
    XCTAssertNotNil(overlayView.testMagnifierContainerLayer)
    XCTAssertFalse(overlayView.testMagnifierContainerLayer!.isHidden)

    // 2. GIVEN: Show selection area overlay is OFF (false)
    UserDefaults.standard.set(false, forKey: PreferencesKeys.screenshotShowSelectionAreaOverlay)
    overlayView.clearBackdrop()
    overlayView.applyBackdrop(backdrop)

    // WHEN: Zooming
    overlayView.testScrollWheel(deltaY: 1.0, modifierFlags: .command)

    // THEN: Zoom works and magnifier container layer is shown
    XCTAssertGreaterThan(overlayView.testMagnifierZoom, 1.0)
    XCTAssertNotNil(overlayView.testMagnifierContainerLayer)
    XCTAssertFalse(overlayView.testMagnifierContainerLayer!.isHidden)
  }

  func testMagnifierZoom_contentsRectCenteredOnCursor() {
    let image = createSolidColorImage(color: .white, size: CGSize(width: 800, height: 600))
    let backdrop = AreaSelectionBackdrop(displayID: 0, image: image, scaleFactor: 1.0)
    overlayView.applyBackdrop(backdrop)

    // Set zoom manually to 5x to trigger magnifier setup
    overlayView.testScrollWheel(deltaY: 4.0, modifierFlags: .command)

    // Move cursor to (200, 150)
    overlayView.mouseMoved(with: NSEvent.mouseEvent(
      with: .mouseMoved,
      location: CGPoint(x: 200, y: 150),
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      eventNumber: 0,
      clickCount: 0,
      pressure: 0
    )!)

    guard let imgLayer = overlayView.testMagnifierImageLayer else {
      XCTFail("magnifierImageLayer not found")
      return
    }

    let contentsRect = imgLayer.contentsRect
    let centerX = contentsRect.origin.x + contentsRect.size.width / 2.0
    let centerY = contentsRect.origin.y + contentsRect.size.height / 2.0

    XCTAssertEqual(centerX, 0.25, accuracy: 1e-5)
    XCTAssertEqual(centerY, 0.25, accuracy: 1e-5)
  }

  func testMagnifierGrid_hiddenAtLowZoom_visibleAtHighZoom() {
    let image = createSolidColorImage(color: .white, size: CGSize(width: 800, height: 600))
    let backdrop = AreaSelectionBackdrop(displayID: 0, image: image, scaleFactor: 1.0)
    overlayView.applyBackdrop(backdrop)

    // GIVEN: A zoom below the grid's visibility threshold
    overlayView.testMagnifierZoom = 2.0
    overlayView.testUpdateMagnifier(at: CGPoint(x: 200, y: 150))

    guard let gridLayer = overlayView.testMagnifierGridLayer else {
      XCTFail("magnifierGridLayer not found")
      return
    }
    XCTAssertTrue(gridLayer.isHidden)

    // WHEN: Zooming past the threshold
    overlayView.testMagnifierZoom = 8.0
    overlayView.testUpdateMagnifier(at: CGPoint(x: 200, y: 150))

    // THEN: The pixel grid becomes visible with a non-empty path
    XCTAssertFalse(gridLayer.isHidden)
    XCTAssertNotNil(gridLayer.path)
  }

  func testMagnifierGrid_thresholdIsZoomBased_notScreenResolutionDependent() {
    // A 2x backdrop (e.g. Retina) halves the on-screen pixel span for a given zoom — the grid
    // must still appear at the same zoom level as on a 1x backdrop, so ⌘+scroll feels the same
    // regardless of the display.
    let image = createSolidColorImage(color: .white, size: CGSize(width: 1600, height: 1200))
    let backdrop = AreaSelectionBackdrop(displayID: 0, image: image, scaleFactor: 2.0)
    overlayView.applyBackdrop(backdrop)

    overlayView.testMagnifierZoom = 6.0
    overlayView.testUpdateMagnifier(at: CGPoint(x: 200, y: 150))

    guard let gridLayer = overlayView.testMagnifierGridLayer else {
      XCTFail("magnifierGridLayer not found")
      return
    }
    XCTAssertFalse(gridLayer.isHidden)
  }

  func testMagnifierCrosshair_spansPreviewWhenActive() {
    let image = createSolidColorImage(color: .white, size: CGSize(width: 800, height: 600))
    let backdrop = AreaSelectionBackdrop(displayID: 0, image: image, scaleFactor: 1.0)
    overlayView.applyBackdrop(backdrop)

    overlayView.testMagnifierZoom = 5.0
    overlayView.testUpdateMagnifier(at: CGPoint(x: 200, y: 150))

    guard let crosshairLayer = overlayView.testMagnifierCrosshairLayer,
          let path = crosshairLayer.path else {
      XCTFail("magnifierCrosshairLayer not found")
      return
    }
    XCTAssertFalse(crosshairLayer.isHidden)
    XCTAssertFalse(path.isEmpty)
  }

  func testMagnifierPanel_showsSampledColor() {
    let image = createSolidColorImage(color: .black, size: CGSize(width: 800, height: 600))
    let backdrop = AreaSelectionBackdrop(displayID: 0, image: image, scaleFactor: 1.0)
    overlayView.applyBackdrop(backdrop)

    overlayView.testMagnifierZoom = 5.0
    overlayView.testUpdateMagnifier(at: CGPoint(x: 200, y: 150))

    guard let panelLayer = overlayView.testMagnifierPanelLayer else {
      XCTFail("magnifierPanelLayer not found")
      return
    }
    XCTAssertFalse(panelLayer.isHidden)
    XCTAssertEqual(overlayView.testMagnifierColorTextLayer?.string as? String, "#000000")
    XCTAssertEqual(overlayView.testMagnifierLastHexColor, "#000000")
  }

  func testMagnifierPanel_hiddenWhenColorPanelPreferenceOff() {
    let image = createSolidColorImage(color: .black, size: CGSize(width: 800, height: 600))
    let backdrop = AreaSelectionBackdrop(displayID: 0, image: image, scaleFactor: 1.0)
    overlayView.applyBackdrop(backdrop)
    overlayView.testMagnifierShowsColorPanel = false

    overlayView.testMagnifierZoom = 5.0
    overlayView.testUpdateMagnifier(at: CGPoint(x: 200, y: 150))

    guard let panelLayer = overlayView.testMagnifierPanelLayer,
          let containerLayer = overlayView.testMagnifierContainerLayer else {
      XCTFail("magnifier layers not found")
      return
    }
    // The magnifier itself (grid/crosshair preview) still shows...
    XCTAssertFalse(containerLayer.isHidden)
    // ...but the color picker panel underneath does not, and the container shrinks to just
    // the preview square (no panel, no gap).
    XCTAssertTrue(panelLayer.isHidden)
    XCTAssertEqual(containerLayer.frame.height, overlayView.testMagnifierTotalHeight)
  }

  func testMagnifierImageOuterBorder_visibleWhenActive() {
    let image = createSolidColorImage(color: .white, size: CGSize(width: 800, height: 600))
    let backdrop = AreaSelectionBackdrop(displayID: 0, image: image, scaleFactor: 1.0)
    overlayView.applyBackdrop(backdrop)

    overlayView.testMagnifierZoom = 5.0
    overlayView.testUpdateMagnifier(at: CGPoint(x: 200, y: 150))

    // A dark outer ring behind the preview keeps its edge visible against light backdrops,
    // where the preview's own light border would otherwise blend in.
    guard let outerBorder = overlayView.testMagnifierImageOuterBorderLayer else {
      XCTFail("magnifierImageOuterBorderLayer not found")
      return
    }
    XCTAssertFalse(outerBorder.isHidden)
    XCTAssertNotNil(outerBorder.backgroundColor)
  }

  func testMagnifierZoom_worksWithEmptyBackdropsInitially() throws {
    try skipIfRunningInCI("Drives the shared AreaSelectionController with real overlay windows and async screen capture, which is flaky on headless CI runners")

    let controller = AreaSelectionController.shared

    // GIVEN: Starting selection session with empty backdrops (backdrop-less mode)
    let expectation = XCTestExpectation(description: "Backdrop snapshot automatically generated")

    controller.startSelection(mode: .recording) { _, _ in }

    // Wait a brief moment for async CGWindowListCreateImage task to finish and apply the backdrop
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      // Find active window in pool
      let targetDisplayID = ScreenUtility.activeDisplayID()
      let mirror = Mirror(reflecting: controller)
      if let pool = mirror.children.first(where: { $0.label == "windowPool" })?.value as? [CGDirectDisplayID: AreaSelectionWindow],
         let window = pool[targetDisplayID] {
        XCTAssertNotNil(window.overlayView.testSnapshotLayer.contents)
      }
      controller.cancelSelection()
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 3.0)
  }
}
