//
//  CropEdgeSnappingTests.swift
//  SnapzyTests
//
//  Pure snap-math tests with a hand-built CropEdgeProfile (no image needed):
//  per-handle edge movement, tolerance behavior, opposite-edge anchoring,
//  corner independence, minSize / inversion guards, .body no-op.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class CropEdgeSnappingTests: XCTestCase {
  // Content borders at x 200/600 and y 150/450 (bottom-left image points).
  private let profile = CropEdgeProfile(
    verticalEdges: [0, 200, 600, 800],
    horizontalEdges: [0, 150, 450, 600],
    verticalStrengths: [0, 240, 240, 0],
    horizontalStrengths: [0, 240, 240, 0]
  )
  private let tolerance: CGFloat = 10

  private func resolve(
    _ handle: CropHandle, _ proposed: CGRect,
    profile: CropEdgeProfile? = nil, minSize: CGFloat = 20
  ) -> CGRect {
    CropEdgeSnapping.resolve(
      handle: handle, proposed: proposed,
      targets: profile ?? self.profile, tolerance: tolerance, minSize: minSize
    )
  }

  // MARK: - Edge handles

  func testLeftHandleSnapsWithinToleranceAndAnchorsRight() {
    let result = resolve(.left, CGRect(x: 195, y: 100, width: 405, height: 400))
    XCTAssertEqual(result, CGRect(x: 200, y: 100, width: 400, height: 400))
  }

  func testLeftHandleDoesNotSnapOutsideTolerance() {
    let proposed = CGRect(x: 185, y: 100, width: 415, height: 400)
    XCTAssertEqual(resolve(.left, proposed), proposed)
  }

  func testRightHandleSnapsWithinToleranceAndAnchorsLeft() {
    let result = resolve(.right, CGRect(x: 100, y: 100, width: 505, height: 400))
    XCTAssertEqual(result, CGRect(x: 100, y: 100, width: 500, height: 400))
  }

  func testBottomHandleSnapsWithinToleranceAndAnchorsTop() {
    let result = resolve(.bottom, CGRect(x: 100, y: 155, width: 500, height: 345))
    XCTAssertEqual(result, CGRect(x: 100, y: 150, width: 500, height: 350))
  }

  func testTopHandleSnapsWithinToleranceAndAnchorsBottom() {
    let result = resolve(.top, CGRect(x: 100, y: 100, width: 500, height: 355))
    XCTAssertEqual(result, CGRect(x: 100, y: 100, width: 500, height: 350))
  }

  func testTopHandleDoesNotSnapOutsideTolerance() {
    let proposed = CGRect(x: 100, y: 100, width: 500, height: 396)
    XCTAssertEqual(resolve(.top, proposed), proposed)
  }

  // MARK: - Corner handles

  func testCornerSnapsBothAxesIndependently() {
    let result = resolve(.topLeft, CGRect(x: 195, y: 100, width: 405, height: 355))
    XCTAssertEqual(result, CGRect(x: 200, y: 100, width: 400, height: 350))
  }

  func testCornerSnapsOnlyTheAxisWithinTolerance() {
    // bottomRight moves maxX and minY; here only maxX (605) is near a target.
    let result = resolve(.bottomRight, CGRect(x: 100, y: 407, width: 505, height: 93))
    XCTAssertEqual(result, CGRect(x: 100, y: 407, width: 500, height: 93))
  }

  func testSnapsToNearestOfTwoTargetsWithinTolerance() {
    let twoTargets = CropEdgeProfile(
      verticalEdges: [0, 190, 200, 800],
      horizontalEdges: [0, 600],
      verticalStrengths: [0, 240, 240, 0],
      horizontalStrengths: [0, 0]
    )
    let result = resolve(.left, CGRect(x: 193, y: 100, width: 407, height: 400), profile: twoTargets)
    XCTAssertEqual(result, CGRect(x: 190, y: 100, width: 410, height: 400))
  }

  // MARK: - Body

  func testBodyReturnsProposedUnchanged() {
    let proposed = CGRect(x: 123, y: 234, width: 345, height: 456)
    XCTAssertEqual(resolve(.body, proposed), proposed)
  }

  // MARK: - Guards

  func testSnapSkippedWhenItWouldViolateMinSize() {
    // minX 575 is 3 pt from target 578, but snapping leaves width 17 < 20.
    let tight = CropEdgeProfile(
      verticalEdges: [0, 578, 800],
      horizontalEdges: [0, 600],
      verticalStrengths: [0, 240, 0],
      horizontalStrengths: [0, 0]
    )
    let proposed = CGRect(x: 575, y: 100, width: 20, height: 400)
    XCTAssertEqual(resolve(.left, proposed, profile: tight), proposed)
  }

  func testSnapSkippedWhenItWouldInvertRect() {
    // minX 598 is 7 pt from target 605 beyond maxX - minSize; never invert.
    let inverted = CropEdgeProfile(
      verticalEdges: [0, 605, 800],
      horizontalEdges: [0, 600],
      verticalStrengths: [0, 240, 0],
      horizontalStrengths: [0, 0]
    )
    let proposed = CGRect(x: 598, y: 100, width: 20, height: 400)
    let result = resolve(.left, proposed, profile: inverted)
    XCTAssertEqual(result, proposed)
    XCTAssertGreaterThanOrEqual(result.width, 20)
  }

  func testUnsnappedHandleReturnsProposedWhenNoTargetsExist() {
    let empty = CropEdgeProfile(
      verticalEdges: [], horizontalEdges: [],
      verticalStrengths: [], horizontalStrengths: []
    )
    let proposed = CGRect(x: 195, y: 155, width: 405, height: 345)
    XCTAssertEqual(resolve(.topLeft, proposed, profile: empty), proposed.standardized)
  }
}
