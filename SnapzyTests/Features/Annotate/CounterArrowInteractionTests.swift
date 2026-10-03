import AppKit
import SwiftUI
import XCTest
@testable import Snapzy

final class CounterArrowInteractionTests: XCTestCase {
  @MainActor private static var retainedStates: [AnnotateState] = []
  private let start = CGPoint(x: 80, y: 80)
  private let target = CGPoint(x: 220, y: 130)

  private func makeCounter(end: CGPoint, minimumDistance: CGFloat = 4) throws -> AnnotationItem {
    var properties = AnnotationProperties(strokeWidth: 2)
    // Creation must not inherit a target left in a tool's properties.
    properties.counterArrowTarget = CGPoint(x: 399, y: 299)
    return try XCTUnwrap(AnnotationFactory.createAnnotation(
      tool: .counter, from: start, to: end, path: [],
      context: AnnotationFactory.CreationContext(
        properties: properties, arrowStyle: .curvedLeft, arrowType: .classic,
        blurType: .pixelated, counterValue: 3, watermarkText: "Snapzy",
        activeAnnotationBounds: CGRect(x: 0, y: 0, width: 400, height: 300),
        counterArrowMinimumDragDistance: minimumDistance
      )
    ))
  }

  func testClickClearsInheritedTargetAndCreatesPlainCounter() throws {
    let item = try makeCounter(end: start)
    XCTAssertEqual(item.type, .counter(3))
    XCTAssertNil(item.properties.counterArrowTarget)
    XCTAssertNil(item.counterArrowGeometry)
    XCTAssertEqual(item.bounds.midX, start.x)
    XCTAssertEqual(item.bounds.midY, start.y)
  }

  func testDragCreatesOneCounterWithFixedStraightTaperedArrow() throws {
    let item = try makeCounter(end: target)
    let geometry = try XCTUnwrap(item.counterArrowGeometry)
    XCTAssertEqual(item.type, .counter(3))
    XCTAssertEqual(geometry.end, target)
    XCTAssertEqual(geometry.style, .straight)
    XCTAssertEqual(geometry.arrowType, .tapered)
    XCTAssertEqual(item.bounds.midX, start.x)
    XCTAssertEqual(item.bounds.midY, start.y)
  }

  func testDragInsideBadgeCreatesPlainCounter() throws {
    let item = try makeCounter(end: CGPoint(x: start.x + 5, y: start.y))
    XCTAssertNil(item.properties.counterArrowTarget)
  }

  func testScreenDistanceThresholdCanSuppressAnOutsideBadgeTarget() throws {
    let item = try makeCounter(end: target, minimumDistance: 200)
    XCTAssertNil(item.properties.counterArrowTarget)
  }

  func testCounterShiftSnapsEvenWhenArrowToolHasCurvedStyle() {
    let point = AnnotationDragConstraint.constrainedEndPoint(
      tool: .counter, arrowStyle: .curvedLeft, start: start,
      end: CGPoint(x: 180, y: 135), shiftHeld: true,
      bounds: CGRect(x: 0, y: 0, width: 400, height: 300)
    )
    XCTAssertEqual(point.x - start.x, point.y - start.y, accuracy: 0.0001)
    XCTAssertEqual(hypot(point.x - start.x, point.y - start.y), hypot(100, 55), accuracy: 0.0001)
  }

  @MainActor
  func testCounterTipRemovalAndUndoRestoreOneItem() throws {
    let state = makeState()
    let item = try makeCounter(end: target)
    state.annotations = [item]
    state.saveState()
    state.updateCounterArrowTarget(id: item.id, target: start)
    XCTAssertEqual(state.annotations.count, 1)
    XCTAssertNil(state.annotations[0].properties.counterArrowTarget)
    state.undo()
    XCTAssertEqual(state.annotations.count, 1)
    XCTAssertEqual(state.annotations[0].properties.counterArrowTarget, target)
  }

  @MainActor
  func testImageRotationMovesCounterTargetAndUndoRestoresIt() throws {
    let state = makeState()
    let item = try makeCounter(end: target)
    state.annotations = [item]
    state.rotateImage(clockwise: true)
    XCTAssertEqual(state.annotations[0].properties.counterArrowTarget, CGPoint(x: target.y, y: 400 - target.x))
    XCTAssertEqual(state.annotations[0].bounds.midX, start.y)
    XCTAssertEqual(state.annotations[0].bounds.midY, 400 - start.x)
    state.undo()
    XCTAssertEqual(state.annotations[0].properties.counterArrowTarget, target)
    XCTAssertEqual(state.annotations[0].bounds, item.bounds)
  }

  @MainActor
  func testDuplicateRetainsCounterNumberAndTranslatesBothParts() throws {
    let state = makeState()
    let item = try makeCounter(end: target)
    state.annotations = [item]
    state.selectedAnnotationId = item.id
    XCTAssertTrue(state.duplicateSelectedAnnotations())
    XCTAssertEqual(state.annotations.count, 2)
    let copy = state.annotations[1]
    let copiedTarget = try XCTUnwrap(copy.properties.counterArrowTarget)
    XCTAssertEqual(copy.type, .counter(3))
    XCTAssertNotEqual(copy.id, item.id)
    XCTAssertEqual(copiedTarget.x - target.x, copy.bounds.midX - start.x)
    XCTAssertEqual(copiedTarget.y - target.y, copy.bounds.midY - start.y)
  }

  @MainActor
  private func makeState() -> AnnotateState {
    let state = AnnotateState(defaults: UserDefaultsFactory.make())
    Self.retainedStates.append(state)
    let image = NSImage(size: NSSize(width: 400, height: 300))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 400, height: 300).fill()
    image.unlockFocus()
    state.loadImage(image)
    return state
  }
}
