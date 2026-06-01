//
//  AnnotateImageRotationTests.swift
//  SnapzyTests
//
//  Unit tests for 90° point/rect rotation helpers used by the editor rotation tools.
//  Coordinate system is top-left origin (y-down), matching annotation storage.
//

import AppKit
import CoreGraphics
import XCTest
@testable import Snapzy

final class AnnotateImageRotationTests: XCTestCase {
  private let imageSize = CGSize(width: 400, height: 200)

  // MARK: - rotatePoint

  func testRotatePoint_clockwise_topLeftCornerMovesToTopRight() {
    let rotated = AnnotateImageRotation.rotatePoint(.zero, oldSize: imageSize, clockwise: true)
    XCTAssertEqual(rotated, CGPoint(x: imageSize.height, y: 0))
  }

  func testRotatePoint_clockwise_topRightCornerMovesToBottomRight() {
    let rotated = AnnotateImageRotation.rotatePoint(
      CGPoint(x: imageSize.width, y: 0),
      oldSize: imageSize,
      clockwise: true
    )
    XCTAssertEqual(rotated, CGPoint(x: imageSize.height, y: imageSize.width))
  }

  func testRotatePoint_clockwise_bottomRightCornerMovesToBottomLeft() {
    let rotated = AnnotateImageRotation.rotatePoint(
      CGPoint(x: imageSize.width, y: imageSize.height),
      oldSize: imageSize,
      clockwise: true
    )
    XCTAssertEqual(rotated, CGPoint(x: 0, y: imageSize.width))
  }

  func testRotatePoint_counterClockwise_topLeftCornerMovesToBottomLeft() {
    let rotated = AnnotateImageRotation.rotatePoint(.zero, oldSize: imageSize, clockwise: false)
    XCTAssertEqual(rotated, CGPoint(x: 0, y: imageSize.width))
  }

  func testRotatePoint_counterClockwise_topRightCornerMovesToTopLeft() {
    let rotated = AnnotateImageRotation.rotatePoint(
      CGPoint(x: imageSize.width, y: 0),
      oldSize: imageSize,
      clockwise: false
    )
    XCTAssertEqual(rotated, .zero)
  }

  func testRotatePoint_fourClockwiseRotationsReturnsToOriginal() {
    let point = CGPoint(x: 137, y: 92)
    let pass1 = AnnotateImageRotation.rotatePoint(point, oldSize: imageSize, clockwise: true)
    let pass2 = AnnotateImageRotation.rotatePoint(
      pass1,
      oldSize: CGSize(width: imageSize.height, height: imageSize.width),
      clockwise: true
    )
    let pass3 = AnnotateImageRotation.rotatePoint(pass2, oldSize: imageSize, clockwise: true)
    let pass4 = AnnotateImageRotation.rotatePoint(
      pass3,
      oldSize: CGSize(width: imageSize.height, height: imageSize.width),
      clockwise: true
    )
    XCTAssertEqual(pass4, point)
  }

  func testRotatePoint_clockwiseThenCounterClockwiseReturnsToOriginal() {
    let point = CGPoint(x: 137, y: 92)
    let forward = AnnotateImageRotation.rotatePoint(point, oldSize: imageSize, clockwise: true)
    let back = AnnotateImageRotation.rotatePoint(
      forward,
      oldSize: CGSize(width: imageSize.height, height: imageSize.width),
      clockwise: false
    )
    XCTAssertEqual(back, point)
  }

  // MARK: - rotateRect

  func testRotateRect_clockwise_swapsDimensionsAndRepositions() {
    let rect = CGRect(x: 10, y: 20, width: 80, height: 60)
    let rotated = AnnotateImageRotation.rotateRect(rect, oldSize: imageSize, clockwise: true)
    XCTAssertEqual(
      rotated,
      CGRect(
        x: imageSize.height - rect.minY - rect.height,
        y: rect.minX,
        width: rect.height,
        height: rect.width
      )
    )
  }

  func testRotateRect_counterClockwise_swapsDimensionsAndRepositions() {
    let rect = CGRect(x: 10, y: 20, width: 80, height: 60)
    let rotated = AnnotateImageRotation.rotateRect(rect, oldSize: imageSize, clockwise: false)
    XCTAssertEqual(
      rotated,
      CGRect(
        x: rect.minY,
        y: imageSize.width - rect.minX - rect.width,
        width: rect.height,
        height: rect.width
      )
    )
  }

  func testRotateRect_fullImageRectClockwiseProducesFullRotatedCanvas() {
    let fullRect = CGRect(origin: .zero, size: imageSize)
    let rotated = AnnotateImageRotation.rotateRect(fullRect, oldSize: imageSize, clockwise: true)
    XCTAssertEqual(rotated, CGRect(x: 0, y: 0, width: imageSize.height, height: imageSize.width))
  }

  func testRotateRect_handlesNonStandardRectByStandardising() {
    let nonStandard = CGRect(x: 100, y: 90, width: -40, height: -20)
    let expectedStandardised = nonStandard.standardized
    let rotated = AnnotateImageRotation.rotateRect(nonStandard, oldSize: imageSize, clockwise: true)
    XCTAssertEqual(rotated.width, expectedStandardised.height)
    XCTAssertEqual(rotated.height, expectedStandardised.width)
  }

  // MARK: - NSImage.rotated90

  func testNSImageRotated90Clockwise_swapsLogicalPointSize() {
    let image = makeImage(width: 200, height: 100)
    let rotated = image.rotated90(clockwise: true)
    XCTAssertNotNil(rotated)
    XCTAssertEqual(rotated?.size, NSSize(width: 100, height: 200))
  }

  func testNSImageRotated90CounterClockwise_swapsLogicalPointSize() {
    let image = makeImage(width: 200, height: 100)
    let rotated = image.rotated90(clockwise: false)
    XCTAssertNotNil(rotated)
    XCTAssertEqual(rotated?.size, NSSize(width: 100, height: 200))
  }

  func testNSImageRotated90Twice_preservesOriginalAspectRatio() {
    let image = makeImage(width: 300, height: 100)
    let rotated = image.rotated90(clockwise: true)?.rotated90(clockwise: true)
    XCTAssertEqual(rotated?.size, NSSize(width: 300, height: 100))
  }

  // MARK: - Helpers

  private func makeImage(width: CGFloat, height: CGFloat) -> NSImage {
    let size = NSSize(width: width, height: height)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.red.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    return image
  }
}
