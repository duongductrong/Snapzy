//
//  CropDragSelectionTests.swift
//  SnapzyTests
//
//  Pure geometry tests for drag-to-draw crop: anchor/pointer normalization in
//  every direction, clamping to image bounds, aspect-ratio fitting, moving
//  handle mapping, and when a press draws instead of moving the crop.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class CropDragSelectionTests: XCTestCase {
  private let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)

  // MARK: - rect

  func testDragUpRightSpansAnchorToPointer() {
    let rect = CropDragSelection.rect(
      anchor: CGPoint(x: 100, y: 100), current: CGPoint(x: 300, y: 250), bounds: bounds
    )
    XCTAssertEqual(rect, CGRect(x: 100, y: 100, width: 200, height: 150))
  }

  func testDragDownLeftNormalizesToPositiveSize() {
    let rect = CropDragSelection.rect(
      anchor: CGPoint(x: 300, y: 250), current: CGPoint(x: 100, y: 100), bounds: bounds
    )
    XCTAssertEqual(rect, CGRect(x: 100, y: 100, width: 200, height: 150))
  }

  func testPointerOutsideImageIsClampedToBounds() {
    let rect = CropDragSelection.rect(
      anchor: CGPoint(x: 700, y: 50), current: CGPoint(x: 1000, y: -200), bounds: bounds
    )
    XCTAssertEqual(rect, CGRect(x: 700, y: 0, width: 100, height: 50))
  }

  func testAnchorOutsideImageIsClampedToBounds() {
    let rect = CropDragSelection.rect(
      anchor: CGPoint(x: -50, y: 700), current: CGPoint(x: 200, y: 400), bounds: bounds
    )
    XCTAssertEqual(rect, CGRect(x: 0, y: 400, width: 200, height: 200))
  }

  func testSquareRatioShrinksLongerSideTowardAnchor() {
    let rect = CropDragSelection.rect(
      anchor: CGPoint(x: 400, y: 300), current: CGPoint(x: 100, y: 200),
      bounds: bounds, aspectRatio: 1
    )
    XCTAssertEqual(rect, CGRect(x: 300, y: 200, width: 100, height: 100))
  }

  func testWideRatioShrinksHeightWhenTooTall() {
    let rect = CropDragSelection.rect(
      anchor: CGPoint(x: 0, y: 0), current: CGPoint(x: 160, y: 400),
      bounds: bounds, aspectRatio: 16.0 / 9.0
    )
    XCTAssertEqual(rect.origin, .zero)
    XCTAssertEqual(rect.width, 160, accuracy: 0.001)
    XCTAssertEqual(rect.height, 90, accuracy: 0.001)
  }

  func testRatioResultStaysInsideBounds() {
    let rect = CropDragSelection.rect(
      anchor: CGPoint(x: 700, y: 500), current: CGPoint(x: 5000, y: 5000),
      bounds: bounds, aspectRatio: 1
    )
    XCTAssertTrue(bounds.contains(rect))
    XCTAssertEqual(rect, CGRect(x: 700, y: 500, width: 100, height: 100))
  }

  func testZeroLengthDragKeepsAnchorAndZeroSize() {
    let anchor = CGPoint(x: 120, y: 80)
    let rect = CropDragSelection.rect(anchor: anchor, current: anchor, bounds: bounds, aspectRatio: 1)
    XCTAssertEqual(rect, CGRect(origin: anchor, size: .zero))
  }

  // MARK: - movingHandle

  func testMovingHandleFollowsPointerQuadrant() {
    let anchor = CGPoint(x: 100, y: 100)
    XCTAssertEqual(CropDragSelection.movingHandle(anchor: anchor, current: CGPoint(x: 200, y: 200)), .topRight)
    XCTAssertEqual(CropDragSelection.movingHandle(anchor: anchor, current: CGPoint(x: 0, y: 200)), .topLeft)
    XCTAssertEqual(CropDragSelection.movingHandle(anchor: anchor, current: CGPoint(x: 200, y: 0)), .bottomRight)
    XCTAssertEqual(CropDragSelection.movingHandle(anchor: anchor, current: CGPoint(x: 0, y: 0)), .bottomLeft)
  }

  func testMovingHandleSnapsOnlyDrawnEdges() {
    let profile = CropEdgeProfile(
      verticalEdges: [0, 200, 800],
      horizontalEdges: [0, 150, 600],
      verticalStrengths: [0, 240, 0],
      horizontalStrengths: [0, 240, 0]
    )
    let anchor = CGPoint(x: 400, y: 400)
    let current = CGPoint(x: 205, y: 155)
    let proposed = CropDragSelection.rect(anchor: anchor, current: current, bounds: bounds)
    let snapped = CropEdgeSnapping.resolve(
      handle: CropDragSelection.movingHandle(anchor: anchor, current: current),
      proposed: proposed, targets: profile, tolerance: 10
    )
    XCTAssertEqual(snapped, CGRect(x: 200, y: 150, width: 200, height: 250))
  }

  // MARK: - shouldBeginDrawing

  func testPressOnUntouchedFullImageCropDraws() {
    XCTAssertTrue(CropDragSelection.shouldBeginDrawing(
      at: CGPoint(x: 400, y: 300), cropRect: bounds, imageBounds: bounds
    ))
  }

  func testPressInsideChosenCropMoves() {
    XCTAssertFalse(CropDragSelection.shouldBeginDrawing(
      at: CGPoint(x: 300, y: 300),
      cropRect: CGRect(x: 200, y: 200, width: 200, height: 200),
      imageBounds: bounds
    ))
  }

  func testPressOutsideChosenCropDraws() {
    XCTAssertTrue(CropDragSelection.shouldBeginDrawing(
      at: CGPoint(x: 50, y: 50),
      cropRect: CGRect(x: 200, y: 200, width: 200, height: 200),
      imageBounds: bounds
    ))
  }

  func testPressInsideExpandedCropMoves() {
    XCTAssertFalse(CropDragSelection.shouldBeginDrawing(
      at: CGPoint(x: 400, y: 300),
      cropRect: CGRect(x: -100, y: -100, width: 1000, height: 800),
      imageBounds: bounds
    ))
  }
}
