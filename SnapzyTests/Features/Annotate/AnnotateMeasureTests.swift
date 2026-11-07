//
//  AnnotateMeasureTests.swift
//  SnapzyTests
//
//  Annotate Measure tool: image-space mapping, geometry and labels, editing transforms,
//  sidecar persistence, and click/drag gestures on the canvas.
//

import AppKit
import SnapzyMeasureCore
import XCTest
@testable import Snapzy

@MainActor
final class AnnotateMeasureTests: XCTestCase {
  private static var retainedStates: [AnnotateState] = []

  /// 200×120 px white image with a black 1px-bordered box at px x 40…119, y 20…79 (top-left).
  /// At `scale` 2 that is 100×60 pt, the box spanning pt x 20…60, y (bottom-left) 20…50.
  private func boxedImage(scale: CGFloat = 2) -> NSImage {
    let cgImage = ColorPickerTestImages.image(width: 200, height: 120, colorSpace: ColorPickerTestImages.sRGB) { x, y in
      let onBorder = (x == 40 || x == 119) && (20...79).contains(y)
        || (y == 20 || y == 79) && (40...119).contains(x)
      return onBorder ? (0, 0, 0) : (255, 255, 255)
    }
    return NSImage(cgImage: cgImage, size: CGSize(width: 200 / scale, height: 120 / scale))
  }

  private func mapper(scale: CGFloat = 2) throws -> AnnotateMeasureMapper {
    let image = boxedImage(scale: scale)
    let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    return try XCTUnwrap(AnnotateMeasureMapper(raster: try XCTUnwrap(MeasureRaster(image: cgImage)), imageSize: image.size))
  }

  // MARK: - Mapper

  func testMapper_pixelUsesBottomLeftImagePoints() throws {
    let mapper = try mapper()
    XCTAssertEqual(mapper.pixel(at: CGPoint(x: 0.1, y: 59.9)), MeasurePixel(x: 0, y: 0))
    XCTAssertEqual(mapper.pixel(at: CGPoint(x: 99.9, y: 0.1)), MeasurePixel(x: 199, y: 119))
    XCTAssertNil(mapper.pixel(at: CGPoint(x: 100.5, y: 10)))
  }

  func testMapper_spanInsideBoxMeasuresInnerGapInPoints() throws {
    let mapper = try mapper()
    // Inside the box: px x 41…118 (78 px = 39 pt), px y 21…78 (58 px = 29 pt).
    let span = try XCTUnwrap(mapper.span(at: CGPoint(x: 40, y: 30), axis: .both, tolerance: 8, unit: .points))
    XCTAssertEqual(span.bounds.minX, 20.5, accuracy: 0.001)
    XCTAssertEqual(span.bounds.width, 39, accuracy: 0.001)
    XCTAssertEqual(span.bounds.height, 29, accuracy: 0.001)
    XCTAssertEqual(span.geometry.label(for: span.bounds), "39 × 29 pt")
    var pixels = span.geometry
    pixels.unit = .pixels
    XCTAssertEqual(pixels.label(for: span.bounds), "78 × 58 px")
  }

  func testMapper_singleAxisSpanHasZeroThicknessAndOneValue() throws {
    let mapper = try mapper()
    let span = try XCTUnwrap(mapper.span(at: CGPoint(x: 40, y: 30), axis: .horizontal, tolerance: 8, unit: .points))
    XCTAssertEqual(span.bounds.height, 0)
    XCTAssertEqual(span.geometry.label(for: span.bounds), "39 pt")
    XCTAssertEqual(span.geometry.segments(in: span.bounds).count, 1)
  }

  func testMapper_boxSnapsToContentUnlessRaw() throws {
    let mapper = try mapper()
    let snapped = mapper.box(from: CGPoint(x: 5, y: 55), to: CGPoint(x: 95, y: 5), snaps: true, tolerance: 8, unit: .points)
    XCTAssertEqual(snapped.bounds.minX, 20, accuracy: 0.001)
    XCTAssertEqual(snapped.bounds.width, 40, accuracy: 0.001)
    XCTAssertEqual(snapped.bounds.height, 30, accuracy: 0.001)
    XCTAssertEqual(snapped.geometry.label(for: snapped.bounds), "40 × 30 pt")

    let raw = mapper.box(from: CGPoint(x: 5, y: 55), to: CGPoint(x: 95, y: 5), snaps: false, tolerance: 8, unit: .points)
    XCTAssertEqual(raw.bounds.width, 90.5, accuracy: 0.001)
  }

  // MARK: - Item transforms

  private func spanItem() throws -> AnnotationItem {
    let span = try XCTUnwrap(try mapper().span(at: CGPoint(x: 40, y: 30), axis: .both, tolerance: 8, unit: .points))
    return AnnotationItem(type: .measurement(span.geometry), bounds: span.bounds, properties: AnnotationProperties())
  }

  func testSpan_movesButNeverResizes() throws {
    let item = try spanItem()
    XCTAssertFalse(item.supportsResize)
    let moved = item.applyingResizeBounds(item.resizeBounds.offsetBy(dx: 10, dy: -5))
    XCTAssertEqual(moved.bounds.size, item.bounds.size)
    XCTAssertEqual(moved.bounds.minX, item.bounds.minX + 10, accuracy: 0.001)
    guard case .measurement(let before) = item.type, case .measurement(let after) = moved.type else {
      return XCTFail("Expected measurements")
    }
    XCTAssertEqual(after.origin.x, before.origin.x + 10, accuracy: 0.001)
    XCTAssertEqual(after.origin.y, before.origin.y - 5, accuracy: 0.001)
    XCTAssertEqual(after.label(for: moved.bounds), before.label(for: item.bounds))
  }

  func testBox_resizeUpdatesTheLabel() throws {
    let box = try mapper().box(from: CGPoint(x: 5, y: 55), to: CGPoint(x: 95, y: 5), snaps: true, tolerance: 8, unit: .points)
    let item = AnnotationItem(type: .measurement(box.geometry), bounds: box.bounds, properties: AnnotationProperties())
    XCTAssertTrue(item.supportsResize)
    let resized = item.applyingResizeBounds(CGRect(x: 20, y: 20, width: 50, height: 30))
    guard case .measurement(let geometry) = resized.type else { return XCTFail("Expected a measurement") }
    XCTAssertEqual(geometry.label(for: resized.bounds), "50 × 30 pt")
  }

  func testRotation_swapsAxisAndScale() {
    let geometry = MeasureGeometry.span(axis: .horizontal, origin: CGPoint(x: 10, y: 20), pixelScale: CGSize(width: 2, height: 3), unit: .pixels)
    let rotated = geometry.rotated { CGPoint(x: $0.y, y: $0.x) }
    XCTAssertEqual(rotated.axis, .vertical)
    XCTAssertEqual(rotated.pixelScale, CGSize(width: 3, height: 2))
    XCTAssertEqual(rotated.origin, CGPoint(x: 20, y: 10))
  }

  func testHitTesting_spanLineAndLabelSelectButEmptyInsideDoesNot() throws {
    let item = try spanItem()
    guard case .measurement(let geometry) = item.type else { return XCTFail("Expected a measurement") }
    XCTAssertTrue(item.edgeBandContains(CGPoint(x: item.bounds.minX + 3, y: geometry.origin.y)))
    XCTAssertFalse(item.edgeBandContains(CGPoint(x: item.bounds.minX + 3, y: item.bounds.maxY - 2)))
    let label = try XCTUnwrap(AnnotateMeasureRenderer.labelRect(for: item))
    XCTAssertTrue(item.containsPoint(CGPoint(x: label.midX, y: label.midY)))
  }

  func testLabel_staysInsideImageAndRenderBoundsCoverIt() throws {
    let item = AnnotationItem(
      type: .measurement(.box(pixelScale: CGSize(width: 2, height: 2), unit: .points)),
      bounds: CGRect(x: 0, y: 0, width: 40, height: 20),
      properties: AnnotationProperties()
    )
    let label = try XCTUnwrap(AnnotateMeasureRenderer.labelRect(for: item))
    XCTAssertGreaterThanOrEqual(label.minY, 0, "A box on the bottom edge puts its label above")
    XCTAssertGreaterThanOrEqual(label.minX, 0)
    XCTAssertTrue(item.renderBounds.contains(label))
    XCTAssertFalse(item.selectionBounds.contains(label), "Selection geometry stays the measured extent")
  }

  // MARK: - Persistence

  func testPersistence_roundTripsSpanAndBox() throws {
    let span = try spanItem()
    let box = AnnotationItem(
      type: .measurement(.box(pixelScale: CGSize(width: 2, height: 2), unit: .pixels)),
      bounds: CGRect(x: 1, y: 2, width: 30, height: 40),
      properties: AnnotationProperties()
    )
    for item in [span, box] {
      let data = try JSONEncoder().encode(PersistedAnnotationItem(item: item))
      let decoded = try XCTUnwrap(try JSONDecoder().decode(PersistedAnnotationItem.self, from: data).annotationItem)
      XCTAssertEqual(decoded.type, item.type)
      XCTAssertEqual(decoded.bounds, item.bounds)
    }
  }

  func testPersistence_unknownKindIsSkippedNotFatal() throws {
    let known = PersistedAnnotationItem(item: AnnotationItem(type: .rectangle, bounds: CGRect(x: 0, y: 0, width: 10, height: 10), properties: AnnotationProperties()))
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(known)) as? [String: Any])
    var type = try XCTUnwrap(json["type"] as? [String: Any])
    type["kind"] = "hologram"
    json["type"] = type
    let data = try JSONSerialization.data(withJSONObject: [json, try JSONSerialization.jsonObject(with: JSONEncoder().encode(known))])
    let items = try JSONDecoder().decode([PersistedAnnotationItem].self, from: data)
    XCTAssertEqual(items.count, 2)
    XCTAssertEqual(items.compactMap(\.annotationItem).count, 1)
  }

  // MARK: - Canvas gestures

  private func makeCanvas() async throws -> (AnnotateState, DrawingCanvasNSView) {
    let image = boxedImage(scale: 1)
    let state = AnnotateState(defaults: UserDefaultsFactory.make())
    Self.retainedStates.append(state)
    state.loadImage(image)
    state.selectedTool = .measure
    let canvas = DrawingCanvasNSView(state: state)
    canvas.frame = CGRect(origin: .zero, size: image.size)
    canvas.displayScale = 1
    canvas.canvasBounds = CGRect(origin: .zero, size: image.size)
    for _ in 0..<200 where state.measureMapper == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertNotNil(state.measureMapper)
    return (state, canvas)
  }

  private func event(_ type: NSEvent.EventType, at point: CGPoint, flags: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.mouseEvent(
      with: type, location: point, modifierFlags: flags, timestamp: 0,
      windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
    )!
  }

  func testCanvas_clickPinsSpanAndUndoRemovesIt() async throws {
    let (state, canvas) = try await makeCanvas()
    // Image is 200×120 pt at 1×; the box interior spans x 41…118, y (bottom-left) 41…98.
    let point = CGPoint(x: 80, y: 60)
    canvas.mouseDown(with: event(.leftMouseDown, at: point))
    canvas.mouseUp(with: event(.leftMouseUp, at: point))
    let item = try XCTUnwrap(state.annotations.last)
    guard case .measurement(let geometry) = item.type else { return XCTFail("Expected a measurement") }
    XCTAssertEqual(geometry.kind, .span)
    XCTAssertEqual(geometry.label(for: item.bounds), "78 × 58 pt")
    XCTAssertEqual(state.selectedAnnotationId, item.id)
    state.undo()
    XCTAssertTrue(state.annotations.isEmpty)
  }

  func testCanvas_dragSnapsBoxAndCommandKeepsIt() async throws {
    let (state, canvas) = try await makeCanvas()
    let start = CGPoint(x: 10, y: 110)
    let end = CGPoint(x: 190, y: 10)
    canvas.mouseDown(with: event(.leftMouseDown, at: start))
    canvas.mouseDragged(with: event(.leftMouseDragged, at: end))
    canvas.mouseUp(with: event(.leftMouseUp, at: end))
    let snapped = try XCTUnwrap(state.annotations.last)
    guard case .measurement(let geometry) = snapped.type else { return XCTFail("Expected a measurement") }
    XCTAssertEqual(geometry.kind, .box)
    XCTAssertEqual(geometry.label(for: snapped.bounds), "80 × 60 pt")

    canvas.mouseDown(with: event(.leftMouseDown, at: start))
    canvas.mouseDragged(with: event(.leftMouseDragged, at: end, flags: .command))
    canvas.mouseUp(with: event(.leftMouseUp, at: end, flags: .command))
    let raw = try XCTUnwrap(state.annotations.last)
    XCTAssertEqual(raw.bounds.width, 181, accuracy: 0.001)
    XCTAssertEqual(state.annotations.count, 2)
  }

  func testUnitChangeConvertsSelectedMeasurementInOneUndoStep() async throws {
    let (state, canvas) = try await makeCanvas()
    let point = CGPoint(x: 80, y: 60)
    canvas.mouseDown(with: event(.leftMouseDown, at: point))
    canvas.mouseUp(with: event(.leftMouseUp, at: point))
    state.setMeasureUnit(.pixels)
    guard case .measurement(let geometry) = state.annotations.last?.type else { return XCTFail("Expected a measurement") }
    XCTAssertEqual(geometry.unit, .pixels)
    state.undo()
    guard case .measurement(let restored) = state.annotations.last?.type else { return XCTFail("Expected a measurement") }
    XCTAssertEqual(restored.unit, .points)
  }

  func testTool_isDrawableWithDefaultKeyU() {
    XCTAssertTrue(AnnotationToolType.drawableTools.contains(.measure))
    XCTAssertEqual(AnnotationToolType.measure.defaultShortcut, "u")
    XCTAssertTrue(AnnotateShortcutManager.configurableTools.contains(.measure))
  }
}
