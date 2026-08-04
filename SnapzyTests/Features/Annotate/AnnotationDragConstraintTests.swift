import CoreGraphics
import XCTest
@testable import Snapzy

final class AnnotationDragConstraintTests: XCTestCase {
  private let origin = CGPoint(x: 10, y: 10)
  private let unboundedTestArea = CGRect(x: -1_000, y: -1_000, width: 2_000, height: 2_000)

  func testRectangleMakesPositiveDragSquare() {
    let result = constrained(tool: .rectangle, end: CGPoint(x: 80, y: 40))

    assertPoint(result, equals: CGPoint(x: 80, y: 80))
  }

  func testRectanglePreservesNegativeQuadrant() {
    let result = constrained(tool: .rectangle, end: CGPoint(x: -60, y: -20))

    assertPoint(result, equals: CGPoint(x: -60, y: -60))
  }

  func testRectangleVerticalDownUsesPositiveHorizontalDirection() {
    let result = constrained(tool: .rectangle, end: CGPoint(x: 10, y: 80))

    assertPoint(result, equals: CGPoint(x: 80, y: 80))
  }

  func testOvalMakesSquareBounds() {
    let result = constrained(tool: .oval, end: CGPoint(x: 30, y: 70))

    assertPoint(result, equals: CGPoint(x: 70, y: 70))
  }

  func testOvalHorizontalLeftUsesNegativeVerticalDirection() {
    let result = constrained(tool: .oval, end: CGPoint(x: -60, y: 10))

    assertPoint(result, equals: CGPoint(x: -60, y: -60))
  }

  func testFilledRectangleMakesSquareBounds() {
    let result = constrained(tool: .filledRectangle, end: CGPoint(x: -10, y: 60))

    assertPoint(result, equals: CGPoint(x: -40, y: 60))
  }

  func testZeroLengthRectangleDragRemainsAtStart() {
    let result = constrained(tool: .rectangle, end: origin)

    assertPoint(result, equals: origin)
  }

  func testRectangleStopsAtRightBoundaryWithoutChangingAxisDirections() {
    let result = constrained(
      tool: .rectangle,
      start: CGPoint(x: 395, y: 100),
      end: CGPoint(x: 395, y: 140),
      bounds: CGRect(x: 0, y: 0, width: 400, height: 300)
    )

    assertPoint(result, equals: CGPoint(x: 400, y: 105))
  }

  func testFilledRectangleStopsAtLeftBoundary() {
    let result = constrained(
      tool: .filledRectangle,
      start: CGPoint(x: 5, y: 100),
      end: CGPoint(x: -20, y: 130),
      bounds: CGRect(x: 0, y: 0, width: 400, height: 300)
    )

    assertPoint(result, equals: CGPoint(x: 0, y: 105))
  }

  func testOvalStopsAtTopBoundary() {
    let result = constrained(
      tool: .oval,
      start: CGPoint(x: 100, y: 295),
      end: CGPoint(x: 130, y: 330),
      bounds: CGRect(x: 0, y: 0, width: 400, height: 300)
    )

    assertPoint(result, equals: CGPoint(x: 105, y: 300))
  }

  func testOvalStopsAtBottomBoundary() {
    let result = constrained(
      tool: .oval,
      start: CGPoint(x: 100, y: 5),
      end: CGPoint(x: 70, y: -30),
      bounds: CGRect(x: 0, y: 0, width: 400, height: 300)
    )

    assertPoint(result, equals: CGPoint(x: 95, y: 0))
  }

  func testLineSnapsToHorizontalWhilePreservingLength() {
    let end = CGPoint(x: 80, y: 15)
    let result = constrained(tool: .line, end: end)
    let expectedLength = hypot(end.x - origin.x, end.y - origin.y)

    XCTAssertEqual(result.x, origin.x + expectedLength, accuracy: 0.0001)
    XCTAssertEqual(result.y, origin.y, accuracy: 0.0001)
  }

  func testLineSnapsToFortyFiveDegreesWhilePreservingLength() {
    let end = CGPoint(x: 80, y: 60)
    let result = constrained(tool: .line, end: end)
    let expectedComponent = hypot(end.x - origin.x, end.y - origin.y) / sqrt(2)

    XCTAssertEqual(result.x, origin.x + expectedComponent, accuracy: 0.0001)
    XCTAssertEqual(result.y, origin.y + expectedComponent, accuracy: 0.0001)
  }

  func testZeroLengthLineDragRemainsAtStart() {
    let result = constrained(tool: .line, end: origin)

    assertPoint(result, equals: origin)
  }

  func testLineTrimsDiagonalAtRightBoundary() {
    let result = constrained(
      tool: .line,
      start: CGPoint(x: 395, y: 100),
      end: CGPoint(x: 400, y: 108),
      bounds: CGRect(x: 0, y: 0, width: 400, height: 300)
    )

    assertPoint(result, equals: CGPoint(x: 400, y: 105))
  }

  func testStraightArrowSnapsToFortyFiveDegrees() {
    let end = CGPoint(x: 80, y: 60)
    let result = constrained(tool: .arrow, arrowStyle: .straight, end: end)
    let expectedComponent = hypot(end.x - origin.x, end.y - origin.y) / sqrt(2)

    XCTAssertEqual(result.x, origin.x + expectedComponent, accuracy: 0.0001)
    XCTAssertEqual(result.y, origin.y + expectedComponent, accuracy: 0.0001)
  }

  func testStraightArrowTrimsDiagonalAtTopBoundary() {
    let result = constrained(
      tool: .arrow,
      arrowStyle: .straight,
      start: CGPoint(x: 100, y: 295),
      end: CGPoint(x: 108, y: 300),
      bounds: CGRect(x: 0, y: 0, width: 400, height: 300)
    )

    assertPoint(result, equals: CGPoint(x: 105, y: 300))
  }

  func testCurvedArrowDoesNotChange() {
    let end = CGPoint(x: 500, y: 600)
    let result = constrained(
      tool: .arrow,
      arrowStyle: .curvedRight,
      end: end,
      bounds: CGRect(x: 0, y: 0, width: 100, height: 100)
    )

    assertPoint(result, equals: end)
  }

  func testShiftNotHeldDoesNotChangeEndPoint() {
    let end = CGPoint(x: 500, y: 600)
    let result = constrained(
      tool: .line,
      end: end,
      shiftHeld: false,
      bounds: CGRect(x: 0, y: 0, width: 100, height: 100)
    )

    assertPoint(result, equals: end)
  }

  private func constrained(
    tool: AnnotationToolType,
    arrowStyle: ArrowStyle = .straight,
    start: CGPoint? = nil,
    end: CGPoint,
    shiftHeld: Bool = true,
    bounds: CGRect? = nil
  ) -> CGPoint {
    AnnotationDragConstraint.constrainedEndPoint(
      tool: tool,
      arrowStyle: arrowStyle,
      start: start ?? origin,
      end: end,
      shiftHeld: shiftHeld,
      bounds: bounds ?? unboundedTestArea
    )
  }

  private func assertPoint(
    _ actual: CGPoint,
    equals expected: CGPoint,
    accuracy: CGFloat = 0.0001,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
  }
}
