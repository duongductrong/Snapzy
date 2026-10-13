import AppKit
import XCTest
@testable import Snapzy

final class CounterArrowCanvasTests: XCTestCase {
  @MainActor private static var retainedStates: [AnnotateState] = []

  @MainActor
  private func makeCanvas(scale: CGFloat = 1) -> (AnnotateState, DrawingCanvasNSView) {
    let size = CGSize(width: 400 / scale, height: 300 / scale)
    let state = AnnotateState(defaults: UserDefaultsFactory.make())
    Self.retainedStates.append(state)
    state.loadImage(NSImage(size: size))
    state.selectedTool = .counter
    let canvas = DrawingCanvasNSView(state: state)
    canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
    canvas.displayScale = scale
    canvas.canvasBounds = CGRect(origin: .zero, size: size)
    return (state, canvas)
  }

  private func event(_ type: NSEvent.EventType, at point: CGPoint, flags: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.mouseEvent(
      with: type, location: point, modifierFlags: flags, timestamp: 0,
      windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
    )!
  }

  @MainActor
  private func drag(_ canvas: DrawingCanvasNSView, from start: CGPoint, to end: CGPoint, flags: NSEvent.ModifierFlags = []) {
    canvas.mouseDown(with: event(.leftMouseDown, at: start))
    canvas.mouseDragged(with: event(.leftMouseDragged, at: end, flags: flags))
    canvas.mouseUp(with: event(.leftMouseUp, at: end, flags: flags))
  }

  @MainActor
  private func selectCounter(in state: AnnotateState, target: CGPoint = CGPoint(x: 280, y: 100)) -> AnnotationItem {
    let item = AnnotationItem(
      type: .counter(1), bounds: CGRect(x: 88, y: 88, width: 24, height: 24),
      properties: AnnotationProperties(counterArrowTarget: target)
    )
    state.annotations = [item]
    state.selectedTool = .selection
    state.selectedAnnotationId = item.id
    return item
  }

  @MainActor
  func testClickCreatesPlainCounterAndDragCreatesSingleCompoundCounter() throws {
    let (state, canvas) = makeCanvas()
    let click = CGPoint(x: 60, y: 60)
    canvas.mouseDown(with: event(.leftMouseDown, at: click))
    canvas.mouseUp(with: event(.leftMouseUp, at: click))
    XCTAssertEqual(state.annotations.count, 1)
    XCTAssertEqual(state.annotations[0].type, .counter(1))
    XCTAssertNil(state.annotations[0].properties.counterArrowTarget)

    drag(canvas, from: CGPoint(x: 100, y: 160), to: CGPoint(x: 300, y: 160))
    XCTAssertEqual(state.annotations.count, 2)
    let item = try XCTUnwrap(state.annotations.last)
    XCTAssertEqual(item.type, .counter(2))
    XCTAssertEqual(item.bounds.midX, 100)
    XCTAssertEqual(item.bounds.midY, 160)
    XCTAssertEqual(item.properties.counterArrowTarget, CGPoint(x: 300, y: 160))
    state.undo()
    XCTAssertEqual(state.annotations.count, 1)
    state.redo()
    XCTAssertEqual(state.annotations.last?.properties.counterArrowTarget, CGPoint(x: 300, y: 160))
  }

  @MainActor
  func testSmallScreenSpaceJitterRemainsPlainAtSmallFitScale() throws {
    let (state, canvas) = makeCanvas(scale: 0.05)
    // Three display points span 60 image points, beyond the badge's radius.
    drag(canvas, from: CGPoint(x: 60, y: 60), to: CGPoint(x: 63, y: 60))
    let item = try XCTUnwrap(state.annotations.first)
    XCTAssertNil(item.properties.counterArrowTarget)
    XCTAssertEqual(item.bounds.midX, 1200, accuracy: 0.001)
  }

  @MainActor
  func testShiftCounterDragSnapsToFortyFiveDegrees() throws {
    let (state, canvas) = makeCanvas()
    drag(canvas, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 210, y: 180), flags: .shift)
    let target = try XCTUnwrap(state.annotations.first?.properties.counterArrowTarget)
    XCTAssertEqual(target.x - 100, target.y - 100, accuracy: 0.001)
  }

  @MainActor
  func testMoveBadgeCarriesTargetAndUndoRestoresBoth() throws {
    let (state, canvas) = makeCanvas()
    let original = selectCounter(in: state)
    drag(canvas, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 130, y: 140))
    let moved = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(moved.bounds, original.bounds.offsetBy(dx: 30, dy: 40))
    XCTAssertEqual(moved.properties.counterArrowTarget, CGPoint(x: 310, y: 140))
    state.undo()
    XCTAssertEqual(state.annotations.first?.bounds, original.bounds)
    XCTAssertEqual(state.annotations.first?.properties.counterArrowTarget, original.properties.counterArrowTarget)
  }

  @MainActor
  func testCornerResizeKeepsArrowTargetFixed() throws {
    let (state, canvas) = makeCanvas()
    let original = selectCounter(in: state)
    drag(canvas, from: CGPoint(x: 112, y: 112), to: CGPoint(x: 140, y: 140))
    let resized = try XCTUnwrap(state.annotations.first)
    XCTAssertGreaterThan(resized.bounds.width, original.bounds.width)
    XCTAssertEqual(resized.properties.counterArrowTarget, original.properties.counterArrowTarget)
    state.undo()
    XCTAssertEqual(state.annotations.first?.bounds, original.bounds)
  }

  @MainActor
  func testTipDragCommitsOnceAndDroppingOnBadgeRemovesArrow() throws {
    let (state, canvas) = makeCanvas()
    let original = selectCounter(in: state)
    let tip = try XCTUnwrap(original.properties.counterArrowTarget)
    canvas.mouseDown(with: event(.leftMouseDown, at: tip))
    canvas.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 100, y: 100)))
    // Preview edits stay gesture-local until release.
    XCTAssertEqual(state.annotations.first?.properties.counterArrowTarget, tip)
    canvas.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 100, y: 100)))
    XCTAssertNil(state.annotations.first?.properties.counterArrowTarget)
    XCTAssertEqual(state.annotations.first?.bounds, original.bounds)
    state.undo()
    XCTAssertEqual(state.annotations.first?.properties.counterArrowTarget, tip)
    state.redo()
    XCTAssertNil(state.annotations.first?.properties.counterArrowTarget)
  }

  @MainActor
  func testShiftTipDragReaimsArrowWithoutMovingBadge() throws {
    let (state, canvas) = makeCanvas()
    let original = selectCounter(in: state)
    drag(canvas, from: CGPoint(x: 280, y: 100), to: CGPoint(x: 240, y: 220), flags: .shift)
    let updated = try XCTUnwrap(state.annotations.first)
    let target = try XCTUnwrap(updated.properties.counterArrowTarget)
    XCTAssertEqual(target.x - 100, target.y - 100, accuracy: 0.001)
    XCTAssertEqual(updated.bounds, original.bounds)
  }
}
