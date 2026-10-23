//
//  QuickAccessPinWindowDragDeciderTests.swift
//  SnapzyTests
//
//  Regression coverage for pin-window background drag ownership (PR #584,
//  issue #598).
//

import AppKit
import XCTest
@testable import Snapzy

final class QuickAccessPinWindowDragDeciderTests: XCTestCase {
  private let threshold = PinWindowDragDecider.movementThreshold
  private let fallbackDelay = PinWindowDragDecider.systemDragFallbackDelay

  func testIdleDeciderNeverMoves() {
    var decider = PinWindowDragDecider()

    let action = decider.dragged(
      screenPoint: NSPoint(x: 500, y: 500),
      currentFrameOrigin: NSPoint(x: 400, y: 400),
      timestamp: 0
    )

    XCTAssertEqual(action, .forward)
    XCTAssertEqual(decider.mode, .idle)
  }

  func testTrackingBelowThresholdDoesNotMoveAndKeepsTracking() {
    var decider = PinWindowDragDecider()
    decider.begin(
      startScreenPoint: NSPoint(x: 100, y: 100),
      grabOffset: NSPoint(x: 50, y: 50),
      initialFrameOrigin: NSPoint(x: 400, y: 400)
    )

    let action = decider.dragged(
      screenPoint: NSPoint(x: 100 + threshold - 1, y: 100),
      currentFrameOrigin: NSPoint(x: 400, y: 400),
      timestamp: 0
    )

    XCTAssertEqual(action, .forward)
    XCTAssertEqual(
      decider.mode,
      .tracking(
        startScreenPoint: NSPoint(x: 100, y: 100),
        grabOffset: NSPoint(x: 50, y: 50),
        initialFrameOrigin: NSPoint(x: 400, y: 400)
      )
    )
    XCTAssertFalse(decider.ownsGesture)
  }

  func testTrackingPastThresholdWithUnmovedFrameRequestsSystemDrag() {
    var decider = PinWindowDragDecider()
    decider.begin(
      startScreenPoint: NSPoint(x: 100, y: 100),
      grabOffset: NSPoint(x: 50, y: 50),
      initialFrameOrigin: NSPoint(x: 400, y: 400)
    )

    let action = decider.dragged(
      screenPoint: NSPoint(x: 100 + threshold + 10, y: 100),
      currentFrameOrigin: NSPoint(x: 400, y: 400),
      timestamp: 0
    )

    XCTAssertEqual(action, .beginSystemDrag)
    XCTAssertEqual(
      decider.mode,
      .systemDragRequested(
        requestTimestamp: 0,
        grabOffset: NSPoint(x: 50, y: 50),
        frameOrigin: NSPoint(x: 400, y: 400)
      )
    )
    XCTAssertTrue(decider.ownsGesture)
    // The window server may own the drag now and never send a mouse-up.
    XCTAssertFalse(decider.isWindowDriven)
  }

  func testAcceptedSystemDragCedesGestureToNative() {
    var decider = PinWindowDragDecider()
    requestSystemDrag(&decider)

    // The window server moved the frame after the request.
    let action = decider.dragged(
      screenPoint: NSPoint(x: 120, y: 100),
      currentFrameOrigin: NSPoint(x: 410, y: 400),
      timestamp: 0
    )

    XCTAssertEqual(action, .forward)
    XCTAssertEqual(decider.mode, .native)
  }

  /// Coalesced dragged events can cover a long distance before the window
  /// server reports its first move, so the fallback waits on time.
  func testSystemDragWaitsBeforeFallingBackToManual() {
    var decider = PinWindowDragDecider()
    requestSystemDrag(&decider)
    let requestMode = decider.mode

    let action = decider.dragged(
      screenPoint: NSPoint(x: 160, y: 100),
      currentFrameOrigin: NSPoint(x: 400, y: 400),
      timestamp: fallbackDelay / 2
    )

    XCTAssertEqual(action, .forward)
    XCTAssertEqual(decider.mode, requestMode)
  }

  func testSubToleranceFrameSnapKeepsSystemDragRequest() {
    var decider = PinWindowDragDecider()
    requestSystemDrag(&decider)
    let requestMode = decider.mode

    let action = decider.dragged(
      screenPoint: NSPoint(x: 112, y: 100),
      currentFrameOrigin: NSPoint(x: 400.5, y: 400),
      timestamp: fallbackDelay / 2
    )

    XCTAssertEqual(action, .forward)
    XCTAssertEqual(decider.mode, requestMode)
  }

  func testIgnoredSystemDragFallsBackToManualOwnership() {
    var decider = PinWindowDragDecider()
    requestSystemDrag(&decider)

    let action = decider.dragged(
      screenPoint: NSPoint(x: 160, y: 100),
      currentFrameOrigin: NSPoint(x: 400, y: 400),
      timestamp: fallbackDelay
    )

    XCTAssertEqual(action, .move(to: NSPoint(x: 110, y: 50)))
    XCTAssertTrue(decider.isManual)
    XCTAssertTrue(decider.ownsGesture)
    XCTAssertTrue(decider.isWindowDriven)
  }

  func testSystemMovedFrameWhileTrackingCedesGestureToNative() {
    var decider = PinWindowDragDecider()
    decider.begin(
      startScreenPoint: NSPoint(x: 100, y: 100),
      grabOffset: NSPoint(x: 50, y: 50),
      initialFrameOrigin: NSPoint(x: 400, y: 400)
    )

    let action = decider.dragged(
      screenPoint: NSPoint(x: 100 + threshold + 10, y: 100),
      currentFrameOrigin: NSPoint(x: 460, y: 400),
      timestamp: 0
    )

    XCTAssertEqual(action, .forward)
    XCTAssertEqual(decider.mode, .native)
    XCTAssertFalse(decider.ownsGesture)
    XCTAssertFalse(decider.isWindowDriven)
    // Once ceded, the gesture stays native until mouse-up.
    XCTAssertEqual(
      decider.dragged(
        screenPoint: NSPoint(x: 200, y: 200),
        currentFrameOrigin: NSPoint(x: 500, y: 500),
        timestamp: 0
      ),
      .forward
    )
  }

  /// Issue #598: crossing displays, the system repositions the window under
  /// the manual path. The gesture must keep following the cursor instead of
  /// ceding to a native path that does not exist on macOS 27.
  func testManualKeepsOwnershipWhenSystemRepositionsFrame() {
    var decider = PinWindowDragDecider()
    makeManual(&decider)

    let action = decider.dragged(
      screenPoint: NSPoint(x: -20, y: 100),
      currentFrameOrigin: NSPoint(x: 0, y: 50),
      timestamp: 0
    )

    XCTAssertEqual(action, .move(to: NSPoint(x: -70, y: 50)))
    XCTAssertTrue(decider.isManual)
  }

  func testManualMoveUsesAbsolutePositionWithoutDrift() {
    var decider = PinWindowDragDecider()
    makeManual(&decider)

    let action = decider.dragged(
      screenPoint: NSPoint(x: 150, y: 130),
      currentFrameOrigin: NSPoint(x: 110, y: 50),
      timestamp: 0
    )

    XCTAssertEqual(action, .move(to: NSPoint(x: 100, y: 80)))
  }

  func testManualModeIsStableAcrossMoves() {
    var decider = PinWindowDragDecider()
    makeManual(&decider)
    let modeBefore = decider.mode

    _ = decider.dragged(
      screenPoint: NSPoint(x: 300, y: 300),
      currentFrameOrigin: NSPoint(x: 110, y: 50),
      timestamp: 0
    )

    // Equal modes keep the ownership-transition log quiet on every move.
    XCTAssertEqual(decider.mode, modeBefore)
  }

  func testEndResetsToIdle() {
    var decider = PinWindowDragDecider()
    makeManual(&decider)

    decider.end()

    XCTAssertEqual(decider.mode, .idle)
    XCTAssertFalse(decider.ownsGesture)
    XCTAssertEqual(
      decider.dragged(
        screenPoint: NSPoint(x: 500, y: 500),
        currentFrameOrigin: NSPoint(x: 110, y: 50),
        timestamp: 0
      ),
      .forward
    )
  }

  func testFreshBeginAfterMissedMouseUpDoesNotJump() {
    var decider = PinWindowDragDecider()
    makeManual(&decider)
    // No mouse-up arrives; the next mouse-down must reset the stale state.
    decider.begin(
      startScreenPoint: NSPoint(x: 200, y: 200),
      grabOffset: NSPoint(x: 60, y: 40),
      initialFrameOrigin: NSPoint(x: 500, y: 500)
    )

    XCTAssertEqual(
      decider.dragged(
        screenPoint: NSPoint(x: 200 + threshold + 10, y: 200),
        currentFrameOrigin: NSPoint(x: 500, y: 500),
        timestamp: 0
      ),
      .beginSystemDrag
    )
    let action = decider.dragged(
      screenPoint: NSPoint(x: 230, y: 200),
      currentFrameOrigin: NSPoint(x: 500, y: 500),
      timestamp: fallbackDelay
    )

    XCTAssertEqual(action, .move(to: NSPoint(x: 170, y: 160)))
    XCTAssertTrue(decider.isManual)
  }

  // MARK: - Helpers

  /// Tracking from (100, 100) with a (50, 50) grab offset on a frame at
  /// (400, 400), dragged to (110, 100) so the decider requests a system drag.
  private func requestSystemDrag(_ decider: inout PinWindowDragDecider) {
    decider.begin(
      startScreenPoint: NSPoint(x: 100, y: 100),
      grabOffset: NSPoint(x: 50, y: 50),
      initialFrameOrigin: NSPoint(x: 400, y: 400)
    )
    XCTAssertEqual(
      decider.dragged(
        screenPoint: NSPoint(x: 110, y: 100),
        currentFrameOrigin: NSPoint(x: 400, y: 400),
        timestamp: 0
      ),
      .beginSystemDrag
    )
  }

  /// Drives the decider into manual ownership, ending with the window moved
  /// to (110, 50) under a cursor at (160, 100).
  private func makeManual(_ decider: inout PinWindowDragDecider) {
    requestSystemDrag(&decider)
    XCTAssertEqual(
      decider.dragged(
        screenPoint: NSPoint(x: 160, y: 100),
        currentFrameOrigin: NSPoint(x: 400, y: 400),
        timestamp: fallbackDelay
      ),
      .move(to: NSPoint(x: 110, y: 50))
    )
    XCTAssertTrue(decider.isManual)
  }
}
