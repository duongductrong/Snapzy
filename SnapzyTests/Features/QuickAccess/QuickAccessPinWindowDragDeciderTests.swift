//
//  QuickAccessPinWindowDragDeciderTests.swift
//  SnapzyTests
//
//  Regression coverage for pin-window background drag ownership (PR #584).
//

import AppKit
import XCTest
@testable import Snapzy

final class QuickAccessPinWindowDragDeciderTests: XCTestCase {
  private let threshold = PinWindowDragDecider.movementThreshold

  func testIdleDeciderNeverMoves() {
    var decider = PinWindowDragDecider()

    let target = decider.dragged(
      screenPoint: NSPoint(x: 500, y: 500),
      currentFrameOrigin: NSPoint(x: 400, y: 400)
    )

    XCTAssertNil(target)
    XCTAssertEqual(decider.mode, .idle)
  }

  func testTrackingBelowThresholdDoesNotMoveAndKeepsTracking() {
    var decider = PinWindowDragDecider()
    decider.begin(
      startScreenPoint: NSPoint(x: 100, y: 100),
      grabOffset: NSPoint(x: 50, y: 50),
      initialFrameOrigin: NSPoint(x: 400, y: 400)
    )

    let target = decider.dragged(
      screenPoint: NSPoint(x: 100 + threshold - 1, y: 100),
      currentFrameOrigin: NSPoint(x: 400, y: 400)
    )

    XCTAssertNil(target)
    XCTAssertEqual(
      decider.mode,
      .tracking(
        startScreenPoint: NSPoint(x: 100, y: 100),
        grabOffset: NSPoint(x: 50, y: 50),
        initialFrameOrigin: NSPoint(x: 400, y: 400)
      )
    )
  }

  func testTrackingPastThresholdWithUnmovedFrameTakesManualOwnership() {
    var decider = PinWindowDragDecider()
    decider.begin(
      startScreenPoint: NSPoint(x: 100, y: 100),
      grabOffset: NSPoint(x: 50, y: 50),
      initialFrameOrigin: NSPoint(x: 400, y: 400)
    )

    let target = decider.dragged(
      screenPoint: NSPoint(x: 100 + threshold + 10, y: 100),
      currentFrameOrigin: NSPoint(x: 400, y: 400)
    )

    XCTAssertEqual(target, NSPoint(x: threshold + 60, y: 50))
    XCTAssertTrue(decider.isManual)
  }

  func testSystemMovedFrameCedesGestureToNative() {
    var decider = PinWindowDragDecider()
    decider.begin(
      startScreenPoint: NSPoint(x: 100, y: 100),
      grabOffset: NSPoint(x: 50, y: 50),
      initialFrameOrigin: NSPoint(x: 400, y: 400)
    )

    let target = decider.dragged(
      screenPoint: NSPoint(x: 100 + threshold + 10, y: 100),
      currentFrameOrigin: NSPoint(x: 460, y: 400)
    )

    XCTAssertNil(target)
    XCTAssertEqual(decider.mode, .native)
    // Once ceded, the gesture stays native until mouse-up.
    XCTAssertNil(
      decider.dragged(
        screenPoint: NSPoint(x: 200, y: 200),
        currentFrameOrigin: NSPoint(x: 500, y: 500)
      )
    )
  }

  func testManualBacksOffWhenFrameMovesWithoutUs() {
    var decider = PinWindowDragDecider()
    decider.begin(
      startScreenPoint: NSPoint(x: 100, y: 100),
      grabOffset: NSPoint(x: 50, y: 50),
      initialFrameOrigin: NSPoint(x: 400, y: 400)
    )

    let first = decider.dragged(
      screenPoint: NSPoint(x: 160, y: 100),
      currentFrameOrigin: NSPoint(x: 400, y: 400)
    )
    XCTAssertEqual(first, NSPoint(x: 110, y: 50))

    // A future macOS update restores native dragging mid-gesture: the frame
    // is somewhere we did not put it, so the decider must cede ownership.
    let second = decider.dragged(
      screenPoint: NSPoint(x: 170, y: 100),
      currentFrameOrigin: NSPoint(x: 118, y: 50)
    )
    XCTAssertNil(second)
    XCTAssertEqual(decider.mode, .native)
  }

  func testManualMoveUsesAbsolutePositionWithoutDrift() {
    var decider = PinWindowDragDecider()
    decider.begin(
      startScreenPoint: NSPoint(x: 100, y: 100),
      grabOffset: NSPoint(x: 50, y: 50),
      initialFrameOrigin: NSPoint(x: 400, y: 400)
    )

    _ = decider.dragged(
      screenPoint: NSPoint(x: 160, y: 100),
      currentFrameOrigin: NSPoint(x: 400, y: 400)
    )
    let second = decider.dragged(
      screenPoint: NSPoint(x: 150, y: 130),
      currentFrameOrigin: NSPoint(x: 110, y: 50)
    )

    XCTAssertEqual(second, NSPoint(x: 100, y: 80))
  }

  func testSubToleranceFrameSnapKeepsManualOwnership() {
    var decider = PinWindowDragDecider()
    decider.begin(
      startScreenPoint: NSPoint(x: 100, y: 100),
      grabOffset: NSPoint(x: 50, y: 50),
      initialFrameOrigin: NSPoint(x: 400, y: 400)
    )

    _ = decider.dragged(
      screenPoint: NSPoint(x: 160, y: 100),
      currentFrameOrigin: NSPoint(x: 400, y: 400)
    )
    // AppKit snapped the origin by a fraction of a point after we moved the
    // window: within tolerance, so the manual path must keep ownership.
    let target = decider.dragged(
      screenPoint: NSPoint(x: 170, y: 100),
      currentFrameOrigin: NSPoint(x: 110.5, y: 50)
    )

    XCTAssertEqual(target, NSPoint(x: 120, y: 50))
    XCTAssertTrue(decider.isManual)
  }

  func testEndResetsToIdle() {
    var decider = PinWindowDragDecider()
    decider.begin(
      startScreenPoint: NSPoint(x: 100, y: 100),
      grabOffset: NSPoint(x: 50, y: 50),
      initialFrameOrigin: NSPoint(x: 400, y: 400)
    )
    _ = decider.dragged(
      screenPoint: NSPoint(x: 160, y: 100),
      currentFrameOrigin: NSPoint(x: 400, y: 400)
    )
    XCTAssertTrue(decider.isManual)

    decider.end()

    XCTAssertEqual(decider.mode, .idle)
    XCTAssertNil(
      decider.dragged(
        screenPoint: NSPoint(x: 500, y: 500),
        currentFrameOrigin: NSPoint(x: 110, y: 50)
      )
    )
  }

  func testFreshBeginAfterMissedMouseUpDoesNotJump() {
    var decider = PinWindowDragDecider()
    decider.begin(
      startScreenPoint: NSPoint(x: 100, y: 100),
      grabOffset: NSPoint(x: 50, y: 50),
      initialFrameOrigin: NSPoint(x: 400, y: 400)
    )
    // No mouse-up arrives; the next mouse-down must reset the stale state.
    decider.begin(
      startScreenPoint: NSPoint(x: 200, y: 200),
      grabOffset: NSPoint(x: 60, y: 40),
      initialFrameOrigin: NSPoint(x: 500, y: 500)
    )

    let target = decider.dragged(
      screenPoint: NSPoint(x: 200 + threshold + 10, y: 200),
      currentFrameOrigin: NSPoint(x: 500, y: 500)
    )

    XCTAssertEqual(target, NSPoint(x: threshold + 150, y: 160))
    XCTAssertTrue(decider.isManual)
  }
}
