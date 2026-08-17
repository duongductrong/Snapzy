//
//  AreaSelectionMoveLogicTests.swift
//  SnapzyTests
//

import CoreGraphics
@testable import Snapzy
import XCTest

final class AreaSelectionMoveLogicTests: XCTestCase {
  private let anchors = AreaSelectionMoveAnchors(
    originStart: CGPoint(x: 100, y: 100),
    anchor: CGPoint(x: 300, y: 250)
  )

  private func size(_ moved: (start: CGPoint, current: CGPoint)) -> CGSize {
    CGSize(width: abs(moved.current.x - moved.start.x), height: abs(moved.current.y - moved.start.y))
  }

  func testPressSeamIsZero() {
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

  func testCurrentPointAlwaysTracksPointerExactly() {
    for pointer in [CGPoint(x: 301, y: 250), CGPoint(x: 12, y: 900), CGPoint(x: -400, y: -30)] {
      let moved = AreaSelectionMoveLogic.movedSelection(pointer: pointer, anchors: anchors)
      XCTAssertEqual(moved.current, pointer)
    }
  }

  func testIdempotentUnderRepeatedStaleAndOutOfOrderSamples() {
    let truth = AreaSelectionMoveLogic.movedSelection(pointer: CGPoint(x: 340, y: 220), anchors: anchors)

    let samples = [
      CGPoint(x: 340, y: 220),
      CGPoint(x: 339.4, y: 221.7),
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

  func testInterleavedSourcesLeaveNoAccumulatedDrift() {
    var moved = AreaSelectionMoveLogic.movedSelection(pointer: anchors.anchor, anchors: anchors)
    for step in 1...500 {
      let live = CGPoint(x: anchors.anchor.x + CGFloat(step), y: anchors.anchor.y)
      let lagged = CGPoint(x: live.x - 0.7, y: live.y + 0.3)
      moved = AreaSelectionMoveLogic.movedSelection(pointer: lagged, anchors: anchors)
      moved = AreaSelectionMoveLogic.movedSelection(pointer: live, anchors: anchors)
    }

    XCTAssertEqual(moved.start.x, anchors.originStart.x + 500, accuracy: 0.0001)
    XCTAssertEqual(moved.start.y, anchors.originStart.y, accuracy: 0.0001)
    XCTAssertEqual(size(moved), CGSize(width: 200, height: 150))
  }
}
