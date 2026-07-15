//
//  AreaSelectionMultiMonitorReconciliationTests.swift
//  SnapzyTests
//
//  Regression test for the multi-monitor selectionEnabled reconciliation bug:
//  a pooled window on a secondary display whose backdrop hadn't arrived yet
//  kept a stale cached flag after another display's backdrop landed first.
//

import XCTest
import AppKit
@testable import Snapzy

final class AreaSelectionMultiMonitorReconciliationTests: AreaSelectionOverlayTestCase {

  /// Regression for the multi-monitor bug: area selection worked on the PRIMARY display but froze
  /// (no drag rectangle, coordinate indicator stuck) on a SECONDARY display when the capture session
  /// started with empty `selectionBackdrops` and an async backdrop later landed only on the primary.
  ///
  /// Root cause: `AreaSelectionOverlayView.selectionEnabled` is a view-local cached bool, set only via
  /// `setSelectionEnabled(_:)`. The controller's authoritative `selectionEnabled(for:)` is:
  ///   `selectionBackdrops.isEmpty || selectionBackdrops[displayID] != nil || liveFallbackDisplayIDs.contains(displayID)`
  /// The FIRST call to `applyBackdrop(_:for:)` flips `selectionBackdrops.isEmpty` from true to false,
  /// which changes the authoritative answer for EVERY OTHER display -- but before the fix, only the
  /// mutated display's pooled window had its cached flag refreshed. A secondary window's cached flag
  /// stayed stale `true`, so its `mouseDown` skipped the live-fallback rescue path, and the later
  /// authoritative re-check in `beginManualSelection` then correctly said "disabled" -- leaving
  /// `manualSelectionStartPoint` nil and no drag monitors installed. The fix added
  /// `reconcileSelectionEnabledAcrossPooledWindows()`, invoked from `applyBackdrop(_:for:)` right after
  /// `selectionBackdrops[displayID] = backdrop`, which loops EVERY pooled window (not just the one
  /// being mutated) and re-syncs its cached flag to the fresh `selectionEnabled(for:)` value.
  ///
  /// LIMITATION: `AreaSelectionController.windowPool` only ever contains one entry per currently
  /// connected `NSScreen`, and there is no public/internal seam to inject a synthetic secondary
  /// display's window into that private pool from a test running on a single-display machine (or CI
  /// runner). To still exercise the real fix end-to-end (not just re-derive its formula), this test
  /// uses the SINGLE real pooled window as the "secondary" stand-in: its cached flag is seeded to the
  /// stale `true` value a real secondary would have, then `applyBackdrop(_:for:)` is called for a
  /// DIFFERENT, synthetic displayID that has no pooled window (mirroring "the primary's backdrop
  /// arrived, but this window belongs to some other display"). Because
  /// `reconcileSelectionEnabledAcrossPooledWindows()` iterates ALL of `windowPool` regardless of which
  /// displayID was just mutated, this drives the exact same code path a real secondary window would
  /// go through. Without the fix, `applyBackdrop(_:for:)` for an unpooled displayID mutates
  /// `selectionBackdrops` and then hits `guard let window = windowPool[displayID] else { return }` --
  /// returning immediately WITHOUT ever touching the real window's cached flag, leaving it stuck on
  /// stale `true`. A true multi-window assertion (two independently pooled real windows) would require
  /// actual multi-monitor hardware, which is not available in this unit test environment.
  func testApplyBackdrop_reconcilesSelectionEnabledForOtherPooledDisplays() {
    let controller = AreaSelectionController.shared

    // GIVEN: a selection session starts with EMPTY backdrops (backdrop-less / lazy-backdrop mode,
    // e.g. recording-area selection), so every display's `selectionEnabled(for:)` starts out `true`
    // via the `selectionBackdrops.isEmpty` branch.
    let startExpectation = XCTestExpectation(description: "Session started and pool populated")
    controller.startSelection(mode: .recording) { _, _ in }
    DispatchQueue.main.async { startExpectation.fulfill() }
    wait(for: [startExpectation], timeout: 2.0)

    let mirror = Mirror(reflecting: controller)
    guard let windowPool = mirror.children.first(where: { $0.label == "windowPool" })?.value
      as? [CGDirectDisplayID: AreaSelectionWindow],
      let realDisplayID = windowPool.keys.first,
      let realWindow = windowPool[realDisplayID] else {
      XCTFail("Expected at least one pooled window for the current display")
      controller.cancelSelection()
      return
    }

    // Sanity: before any backdrop, the real pooled window's cached flag matches the "empty
    // backdrops" authoritative answer (true).
    XCTAssertTrue(
      selectionEnabledFlag(of: realWindow.overlayView),
      "Cached selectionEnabled must start true when selectionBackdrops is empty"
    )

    // Simulate this real window belonging to a "secondary" display that has NOT yet received its
    // own backdrop, by forcibly re-asserting the stale cached `true` right before the reconciling
    // call below (guards against any incidental prior mutation and makes the stale-value premise
    // explicit, matching the bug report's starting condition).
    realWindow.overlayView.setSelectionEnabled(true)
    XCTAssertTrue(selectionEnabledFlag(of: realWindow.overlayView))

    // A synthetic OTHER display ID -- standing in for "the primary display" in the bug, which is a
    // different display than the one `realWindow` belongs to. It intentionally has no pooled window,
    // so any assertion that depends on `windowPool[otherDisplayID]` being touched would be wrong;
    // what we're proving is that mutating a DIFFERENT display's backdrop still reconciles this one.
    let otherDisplayID = realDisplayID &+ 1

    // WHEN: a backdrop lands on the OTHER display only (async magnifier/luma backdrop capture
    // completing first on the primary while `realWindow`'s own display is still awaiting its
    // backdrop, exactly as in the bug report).
    let image = createSolidColorImage(color: .white, size: CGSize(width: 800, height: 600))
    let backdrop = AreaSelectionBackdrop(displayID: otherDisplayID, image: image, scaleFactor: 1.0)
    controller.applyBackdrop(backdrop, for: otherDisplayID)

    // THEN: `realWindow`'s cached selectionEnabled -- which was never the display being mutated --
    // must be reconciled to `false`, because `selectionBackdrops.isEmpty` is now false and
    // `realDisplayID` has neither its own backdrop nor a live-fallback entry. Before the fix, this
    // window's flag would still be the stale `true` set above, because `applyBackdrop(_:for:)`
    // returned early at `guard let window = windowPool[otherDisplayID]` without ever reaching
    // `realWindow`.
    XCTAssertFalse(
      selectionEnabledFlag(of: realWindow.overlayView),
      "A pooled window whose own display never received a backdrop must have its cached "
        + "selectionEnabled reconciled to false as soon as ANY other display gets one -- "
        + "otherwise its mouseDown skips the live-fallback path and the drag silently drops "
        + "(the multi-monitor freeze bug)"
    )

    controller.cancelSelection()
  }

  /// Reads the private `selectionEnabled` cached bool off an `AreaSelectionOverlayView` via
  /// reflection. There is no `#if DEBUG` test accessor for it (unlike `testSnapshotLayer` etc.),
  /// and adding one is out of scope for this regression test per the fix's "no production
  /// visibility changes" constraint.
  private func selectionEnabledFlag(of overlayView: AreaSelectionOverlayView) -> Bool {
    let mirror = Mirror(reflecting: overlayView)
    guard let value = mirror.children.first(where: { $0.label == "selectionEnabled" })?.value as? Bool else {
      XCTFail("Expected AreaSelectionOverlayView to have a selectionEnabled stored property")
      return true
    }
    return value
  }

  // MARK: - Pointer-tracking (key-follows-pointer) lifecycle

  /// The cross-display crosshair fix installs a pointer-tracking `Timer` for non-activated LIVE
  /// sessions (empty `selectionBackdrops`). It moves keyboard/key ownership to the overlay under the
  /// pointer so that overlay's cursor rects render the crosshair while the app stays inactive. This
  /// verifies the timer is installed for a live session and torn down on cancel (leak-free). The
  /// actual OS-level cursor routing across displays cannot be reproduced in a unit test and requires
  /// manual dual-display verification.
  func testPointerTrackingTimer_installedForLiveSession_removedOnCancel() {
    let controller = AreaSelectionController.shared

    let started = XCTestExpectation(description: "Live session started")
    controller.startSelection(mode: .recording) { _, _ in }
    DispatchQueue.main.async { started.fulfill() }
    wait(for: [started], timeout: 2.0)

    XCTAssertNotNil(
      pointerTrackingTimer(of: controller),
      "A live (backdrop-less) session must install the pointer-tracking timer so the crosshair "
        + "can follow the pointer across displays while the app is inactive"
    )

    controller.cancelSelection()

    let torndown = XCTestExpectation(description: "Session cancelled")
    DispatchQueue.main.async { torndown.fulfill() }
    wait(for: [torndown], timeout: 2.0)

    XCTAssertNil(
      pointerTrackingTimer(of: controller),
      "Cancelling the session must invalidate and clear the pointer-tracking timer (no leak)"
    )
  }

  func testScrollingSelection_firstPhysicalMouseDownStartsManualSelection() throws {
    let controller = AreaSelectionController.shared
    controller.startSelection(mode: .scrollingCapture) { _, _ in }
    defer { controller.cancelSelection() }

    let timer = try XCTUnwrap(pointerTrackingTimer(of: controller))
    timer.fire()

    let windowPool = try XCTUnwrap(
      Mirror(reflecting: controller).children
        .first(where: { $0.label == "windowPool" })?.value
        as? [CGDirectDisplayID: AreaSelectionWindow]
    )
    let mouseLocation = NSEvent.mouseLocation
    let pointerWindow = try XCTUnwrap(
      windowPool.values.first(where: { $0.frame.contains(mouseLocation) })
    )
    let overlayView = pointerWindow.overlayView
    overlayView.setSelectionEnabled(true)
    overlayView.setInteractionMode(.manualRegion, resetSelection: false)
    overlayView.resetSelection()

    let mouseDown = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: CGPoint(x: 120, y: 120),
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: pointerWindow.windowNumber,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1
      )
    )
    overlayView.mouseDown(with: mouseDown)

    XCTAssertTrue(
      overlayView.isManualSelectionInProgress,
      "Pointer promotion must not reserve and swallow the user's first real mouse-down"
    )
  }

  /// Frozen sessions (non-empty `selectionBackdrops`) activate the app, which already routes cursor
  /// handling across displays, so the pointer-tracking timer must NOT be installed — avoiding
  /// redundant key churn.
  func testPointerTrackingTimer_notInstalledForFrozenSession() {
    let controller = AreaSelectionController.shared

    let image = createSolidColorImage(color: .white, size: CGSize(width: 400, height: 300))
    // A synthetic display id is enough to make `selectionBackdrops` non-empty (frozen branch).
    let backdrop = AreaSelectionBackdrop(displayID: 1, image: image, scaleFactor: 1.0)

    let started = XCTestExpectation(description: "Frozen session started")
    controller.startSelection(mode: .screenshot, backdrops: [1: backdrop]) { _ in }
    DispatchQueue.main.async { started.fulfill() }
    wait(for: [started], timeout: 2.0)

    XCTAssertNil(
      pointerTrackingTimer(of: controller),
      "A frozen (backdrop) session activates the app and must not start the pointer-tracking timer"
    )

    controller.cancelSelection()
  }

  /// Verifies that mouse exit properly hides the coordinate indicator and magnifier layers.
  func testMouseExited_hidesCoordinateIndicatorAndMagnifier() throws {
    try skipIfRunningInCI("Simulates interactive mouse exit which is ignored in CI environment")
    
    // 1. GIVEN: Manual region interaction mode with size indicator shown
    let image = createSolidColorImage(color: .white, size: CGSize(width: 800, height: 600))
    let backdrop = AreaSelectionBackdrop(displayID: 1, image: image, scaleFactor: 1.0)
    overlayView.applyBackdrop(backdrop)
    overlayView.setSelectionEnabled(true)
    overlayView.setInteractionMode(.manualRegion, resetSelection: false)
    overlayView.resetSelection()
    
    XCTAssertFalse(overlayView.testSizeIndicatorTextLayer.isHidden, "Size indicator should start visible")
    XCTAssertFalse(overlayView.testSizeIndicatorBackgroundLayer.isHidden, "Background layer should start visible")
    
    // Set magnifier zoom and trigger magnifier update
    overlayView.testMagnifierZoom = 2.0
    overlayView.testUpdateMagnifier(at: CGPoint(x: 100, y: 100))
    XCTAssertNotNil(overlayView.testMagnifierContainerLayer, "Magnifier container should be created")

    // 2. WHEN: mouseExited is called
    overlayView.mouseExited(with: NSEvent())

    // 3. THEN: The layers should be hidden/removed
    XCTAssertTrue(overlayView.testSizeIndicatorTextLayer.isHidden, "Size indicator should be hidden on mouse exit")
    XCTAssertTrue(overlayView.testSizeIndicatorBackgroundLayer.isHidden, "Background layer should be hidden on mouse exit")
    XCTAssertNil(overlayView.testMagnifierContainerLayer, "Magnifier container should be removed on mouse exit")
  }

  /// Verifies isMouseOver frame checks when a window is present
  func testIsMouseOver_evaluatesFrameAndVisibility() throws {
    try skipIfRunningInCI("Requires real window coordinates and mouse location which can fail on headless CI runners")
    
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 200, height: 200),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.contentView = overlayView
    overlayView.setSelectionEnabled(true)
    overlayView.setInteractionMode(.manualRegion, resetSelection: false)
    let mouseLoc = CGPoint(x: 1_000, y: 1_000)
    overlayView.testMouseLocationOverride = mouseLoc
    defer { overlayView.testMouseLocationOverride = nil }
    
    // GIVEN: window is not visible
    window.setIsVisible(false)
    overlayView.resetSelection() // calls updateCoordinateIndicator internally
    XCTAssertTrue(overlayView.testSizeIndicatorTextLayer.isHidden, "Should be hidden when window is not visible")
    
    // GIVEN: window is visible, but positioned away from the mouse
    window.setIsVisible(true)
    // Move window frame away from mouse location
    window.setFrame(CGRect(x: mouseLoc.x + 500, y: mouseLoc.y + 500, width: 200, height: 200), display: false)
    overlayView.resetSelection()
    XCTAssertTrue(overlayView.testSizeIndicatorTextLayer.isHidden, "Should be hidden when window does not contain mouse")
    
    // GIVEN: window contains the mouse location
    window.setFrame(CGRect(x: mouseLoc.x - 50, y: mouseLoc.y - 50, width: 200, height: 200), display: false)
    overlayView.resetSelection()
    XCTAssertFalse(overlayView.testSizeIndicatorTextLayer.isHidden, "Should be visible when window contains mouse")
    
    // Clean up
    window.contentView = nil
    window.close()
  }

  /// Reads the private `pointerTrackingTimer` off `AreaSelectionController` via reflection.
  private func pointerTrackingTimer(of controller: AreaSelectionController) -> Timer? {
    let mirror = Mirror(reflecting: controller)
    return mirror.children.first(where: { $0.label == "pointerTrackingTimer" })?.value as? Timer
  }
}
