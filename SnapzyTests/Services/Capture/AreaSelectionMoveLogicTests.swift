//
//  AreaSelectionMoveLogicTests.swift
//  SnapzyTests
//
//  Space-to-move geometry. These pin the regression where the move accumulated a per-event delta,
//  so the differing pointer samples from each event source were baked into the selection's
//  position one event at a time and the rect crept away from the pointer.
//

import CoreGraphics
@testable import Snapzy
import XCTest

final class AreaSelectionMoveLogicTests: XCTestCase {
  /// A selection dragged from (100, 100) to (300, 250), with Space pressed at the current point.
  private let anchors = AreaSelectionMoveAnchors(
    originStart: CGPoint(x: 100, y: 100),
    anchor: CGPoint(x: 300, y: 250)
  )

  private func size(_ moved: (start: CGPoint, current: CGPoint)) -> CGSize {
    CGSize(width: abs(moved.current.x - moved.start.x), height: abs(moved.current.y - moved.start.y))
  }

  func testPressSeamIsZero() {
    // Space goes down and nothing moves yet: the selection must not shift at all.
    let moved = AreaSelectionMoveLogic.movedSelection(pointer: anchors.anchor, anchors: anchors)
    XCTAssertEqual(moved.start, anchors.originStart)
    XCTAssertEqual(moved.current, anchors.anchor)
  }

  func testTranslatesByPointerDeltaAndPreservesSize() {
    let moved = AreaSelectionMoveLogic.movedSelection(pointer: CGPoint(x: 340, y: 220), anchors: anchors)
    XCTAssertEqual(moved.start, CGPoint(x: 140, y: 70))
    XCTAssertEqual(moved.current, CGPoint(x: 340, y: 220))
    XCTAssertEqual(size(moved), CGSize(width: 200, height: 150))
  }

  /// The release seam: `current` must equal the pointer throughout, so when Space comes up and
  /// the caller resumes absolute assignment (`current = pointer`) the selection does not snap.
  func testCurrentPointAlwaysTracksPointerExactly() {
    for pointer in [CGPoint(x: 301, y: 250), CGPoint(x: 12, y: 900), CGPoint(x: -400, y: -30)] {
      let moved = AreaSelectionMoveLogic.movedSelection(pointer: pointer, anchors: anchors)
      XCTAssertEqual(moved.current, pointer)
    }
  }

  /// The core invariant. Replaying the same sample, an out-of-order stale sample, or a duplicate
  /// from a second event source must all land on the identical rect.
  func testIdempotentUnderRepeatedStaleAndOutOfOrderSamples() {
    let truth = AreaSelectionMoveLogic.movedSelection(pointer: CGPoint(x: 340, y: 220), anchors: anchors)

    let samples = [
      CGPoint(x: 340, y: 220),
      CGPoint(x: 339.4, y: 221.7), // a stale sample from the other monitor
      CGPoint(x: 512, y: 33),
      CGPoint(x: 340, y: 220),
    ]
    var last = truth
    for sample in samples {
      last = AreaSelectionMoveLogic.movedSelection(pointer: sample, anchors: anchors)
    }
    XCTAssertEqual(last.start, truth.start)
    XCTAssertEqual(last.current, truth.current)
  }

  /// Interleaving two event sources that sample the pointer a fraction apart must leave no
  /// residue: the selection depends only on the final sample, never on the path taken to it.
  func testInterleavedSourcesLeaveNoAccumulatedDrift() {
    var moved = AreaSelectionMoveLogic.movedSelection(pointer: anchors.anchor, anchors: anchors)
    for step in 1...500 {
      let live = CGPoint(x: anchors.anchor.x + CGFloat(step), y: anchors.anchor.y)
      let lagged = CGPoint(x: live.x - 0.7, y: live.y + 0.3) // second source, sampled slightly earlier
      moved = AreaSelectionMoveLogic.movedSelection(pointer: lagged, anchors: anchors)
      moved = AreaSelectionMoveLogic.movedSelection(pointer: live, anchors: anchors)
    }

    let expectedTranslation = CGFloat(500)
    XCTAssertEqual(moved.start.x, anchors.originStart.x + expectedTranslation, accuracy: 0.0001)
    XCTAssertEqual(moved.start.y, anchors.originStart.y, accuracy: 0.0001)
    XCTAssertEqual(size(moved), CGSize(width: 200, height: 150))
  }
}
