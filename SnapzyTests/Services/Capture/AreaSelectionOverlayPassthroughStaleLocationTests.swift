//
//  AreaSelectionOverlayPassthroughStaleLocationTests.swift
//  SnapzyTests
//
//  Regression tests for the live-passthrough stale-pointer bug: the event tap
//  consumes every mouse move, so `NSEvent.mouseLocation` stays frozen at the
//  session-start position for the whole session. A tap (mouseDown+Up with no
//  drag) funnels into `clearManualSelectionTracking(render: true)` →
//  `resetSelection()`, which used to re-initialize from that stale location —
//  the coordinate indicator jumped back to where the session started and the
//  drawn crosshair stayed hidden until the next physical mouse move. The
//  overlay must keep the tap-tracked pointer position instead.
//  See plans/260725-0325-passthrough-tap-stale-pointer.
//

import AppKit
@testable import Snapzy
import XCTest

final class AreaSelectionOverlayPassthroughStaleLocationTests: AreaSelectionOverlayTestCase {
  private var hostWindow: NSWindow!

  /// Host window frame in screen coordinates. The overlay fills it as the
  /// content view, so a screen point like (150,160) maps to local (50,60).
  private let hostWindowFrame = CGRect(x: 100, y: 100, width: 800, height: 600)

  override func setUp() {
    super.setUp()
    hostWindow = NSWindow(
      contentRect: hostWindowFrame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    hostWindow.contentView = overlayView
    hostWindow.setIsVisible(true)
  }

  override func tearDown() {
    hostWindow.contentView = nil
    hostWindow.setIsVisible(false)
    hostWindow = nil
    super.tearDown()
  }

  /// Mirror the controller's session-start order (`configureSessionWindow`):
  /// the passthrough flag goes on before overlay configuration.
  private func configurePassthroughSession() {
    overlayView.setInteractionMode(.manualRegion, resetSelection: false)
    overlayView.setSelectionEnabled(true)
    overlayView.setLivePassthroughInputEnabled(true)
    overlayView.resetSelection()
  }

  /// The tap recovery sequence as the controller drives it: tracked hover, the
  /// tap's mouseDown, the per-window `resetSelection()` from
  /// `clearManualSelectionTracking(render: true)`, then the hover-state restore
  /// at the tap point (`restoreLivePassthroughHoverAfterAbortedSelection`).
  private func driveTapRecovery(atScreenPoint screenPoint: CGPoint) {
    overlayView.handleLivePassthroughMouseMoved(atScreenPoint: screenPoint)
    overlayView.handleLivePassthroughMouseDown(atScreenPoint: screenPoint)
    overlayView.resetSelection()
    overlayView.handleLivePassthroughMouseMoved(atScreenPoint: screenPoint)
  }

  /// Core regression: after a tracked hover, the tap-style `resetSelection()`
  /// must not snap the pointer position back to the stale system location.
  func testTapStyleReset_afterTrackedHover_keepsTrackedPointerPosition() {
    configurePassthroughSession()

    overlayView.handleLivePassthroughMouseMoved(atScreenPoint: CGPoint(x: 150, y: 160))
    overlayView.handleLivePassthroughMouseDown(atScreenPoint: CGPoint(x: 150, y: 160))
    overlayView.resetSelection()

    XCTAssertEqual(
      overlayView.testCurrentMousePosition,
      CGPoint(x: 50, y: 60),
      "resetSelection() must keep the tap-tracked position, not the stale NSEvent.mouseLocation"
    )
  }

  /// Full recovery: after the tap reset and the controller's hover restore, the
  /// coordinate indicator shows the tap point and the drawn cursor proxy is
  /// visible again — the same end state an ordinary hover move produces.
  func testTapRecovery_coordinateIndicatorAndCursorProxyRestoredAtTapPoint() throws {
    try skipIfRunningInCI("Requires a visible host window which can fail on headless CI runners")
    configurePassthroughSession()

    driveTapRecovery(atScreenPoint: CGPoint(x: 150, y: 160))

    XCTAssertFalse(
      overlayView.testSizeIndicatorTextLayer.isHidden,
      "coordinate indicator must be visible again after the tap"
    )
    XCTAssertEqual(
      overlayView.testSizeIndicatorTextLayer.string as? String,
      "50, 540",
      "coordinate indicator must show the tap point (local 50,60 → label 50,540)"
    )
    XCTAssertFalse(
      overlayView.testCursorProxyLayer.isHidden,
      "the drawn crosshair must be visible again after the tap"
    )
  }

  /// The passthrough `isMouseOver` branch still honors frame containment: a
  /// tracked point outside this display's window keeps the indicator hidden.
  func testTapStyleReset_trackedPointOutsideWindowFrame_hidesIndicator() throws {
    try skipIfRunningInCI("Requires a visible host window which can fail on headless CI runners")
    configurePassthroughSession()

    overlayView.handleLivePassthroughMouseMoved(atScreenPoint: CGPoint(x: 50, y: 50))
    overlayView.resetSelection()

    XCTAssertTrue(
      overlayView.testSizeIndicatorTextLayer.isHidden,
      "tracked point outside the window frame must keep the indicator hidden"
    )
  }

  /// Session start (no tap-delivered position yet) still initializes from the
  /// real system mouse location — the flag must not break first paint.
  func testSessionStartReset_withoutTrackedPosition_readsSystemMouseLocation() throws {
    try skipIfRunningInCI("Reads the real NSEvent.mouseLocation which is nondeterministic on CI runners")
    configurePassthroughSession()

    let expected = overlayView.convert(
      hostWindow.convertPoint(fromScreen: NSEvent.mouseLocation),
      from: nil
    )
    overlayView.resetSelection()

    XCTAssertEqual(
      overlayView.testCurrentMousePosition,
      expected,
      "before the first tap-delivered position the overlay must keep reading NSEvent.mouseLocation"
    )
  }

  /// Leaving passthrough clears the flag: the next reset re-reads the system
  /// mouse location, restoring the legacy window-event behavior.
  func testReset_afterPassthroughFlagCleared_readsSystemMouseLocation() throws {
    try skipIfRunningInCI("Reads the real NSEvent.mouseLocation which is nondeterministic on CI runners")
    configurePassthroughSession()
    overlayView.handleLivePassthroughMouseMoved(atScreenPoint: CGPoint(x: 150, y: 160))

    overlayView.setLivePassthroughInputEnabled(false)
    let expected = overlayView.convert(
      hostWindow.convertPoint(fromScreen: NSEvent.mouseLocation),
      from: nil
    )
    overlayView.resetSelection()

    XCTAssertEqual(
      overlayView.testCurrentMousePosition,
      expected,
      "after the passthrough flag clears, resets must read NSEvent.mouseLocation again"
    )
  }
}
