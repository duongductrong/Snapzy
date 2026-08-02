import CoreGraphics
import XCTest
@testable import Snapzy

final class AnnotationDragConstraintTests: XCTestCase {
  private let origin = CGPoint(x: 10, y: 10)

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

  func testStraightArrowSnapsToFortyFiveDegrees() {
    let end = CGPoint(x: 80, y: 60)
    let result = constrained(tool: .arrow, arrowStyle: .straight, end: end)
    let expectedComponent = hypot(end.x - origin.x, end.y - origin.y) / sqrt(2)

    XCTAssertEqual(result.x, origin.x + expectedComponent, accuracy: 0.0001)
    XCTAssertEqual(result.y, origin.y + expectedComponent, accuracy: 0.0001)
  }

  func testCurvedArrowDoesNotChange() {
    let end = CGPoint(x: 80, y: 60)
    let result = constrained(tool: .arrow, arrowStyle: .curvedRight, end: end)

    assertPoint(result, equals: end)
  }

  func testShiftNotHeldDoesNotChangeEndPoint() {
    let end = CGPoint(x: 80, y: 60)
    let result = constrained(tool: .line, end: end, shiftHeld: false)

    assertPoint(result, equals: end)
  }

  private func constrained(
    tool: AnnotationToolType,
    arrowStyle: ArrowStyle = .straight,
    end: CGPoint,
    shiftHeld: Bool = true
  ) -> CGPoint {
    AnnotationDragConstraint.constrainedEndPoint(
      tool: tool,
      arrowStyle: arrowStyle,
      start: origin,
      end: end,
      shiftHeld: shiftHeld
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
