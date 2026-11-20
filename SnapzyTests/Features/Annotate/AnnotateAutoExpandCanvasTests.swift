//
//  AnnotateAutoExpandCanvasTests.swift
//  SnapzyTests
//
//  The Annotate canvas grows to fit annotations drawn or moved past the image (or
//  applied crop) edge (#492): derived canvas, shrink-back, crop cuts until the item
//  is touched, undo, rotation, persistence fallback, live gesture growth, export size.
//

import AppKit
import CoreGraphics
import XCTest
@testable import Snapzy

final class AnnotateAutoExpandCanvasTests: XCTestCase {
  // Keep AnnotateState alive for the test process; XCTest scope cleanup can
  // crash while deinitializing this MainActor app-level ObservableObject.
  @MainActor private static var retainedAnnotateStates: [AnnotateState] = []

  private static let imageBounds = CGRect(x: 0, y: 0, width: 400, height: 300)

  @MainActor
  private func makeState(autoExpand: Bool = true) throws -> AnnotateState {
    let suite = "AnnotateAutoExpandCanvasTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defaults.set(autoExpand, forKey: PreferencesKeys.annotateAutoExpandCanvasEnabled)
    let state = AnnotateState(defaults: defaults, appliesDefaultCanvasPresetOnNewImages: false)
    Self.retainedAnnotateStates.append(state)
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: 400, height: 300))
    state.loadImage(NSImage(cgImage: cgImage, size: Self.imageBounds.size))
    return state
  }

  @MainActor
  private func rectangle(_ bounds: CGRect) -> AnnotationItem {
    var properties = AnnotationProperties()
    properties.strokeWidth = 4
    return AnnotationItem(type: .rectangle, bounds: bounds, properties: properties)
  }

  @MainActor
  private func footprint(_ item: AnnotationItem) throws -> CGRect {
    try XCTUnwrap(AnnotateState.canvasFootprint(of: item))
  }

  // MARK: - Growth & shrink-back

  @MainActor
  func testItemInsideImageKeepsPlainCanvas() throws {
    let state = try makeState()
    state.annotations = [rectangle(CGRect(x: 20, y: 20, width: 100, height: 80))]

    XCTAssertNil(state.autoExpandedCanvasRect)
    XCTAssertNil(state.appliedCanvasRect)
    XCTAssertEqual(state.activeAnnotationBounds, Self.imageBounds)
  }

  @MainActor
  func testItemPastEdgeGrowsCanvasToItsFootprint() throws {
    let state = try makeState()
    let item = rectangle(CGRect(x: 350, y: 250, width: 120, height: 90))
    state.annotations = [item]

    let expected = Self.imageBounds.union(try footprint(item))
    XCTAssertEqual(state.autoExpandedCanvasRect, expected)
    XCTAssertEqual(state.activeAnnotationBounds, expected)
    XCTAssertEqual(state.makeRenderSnapshot()?.cropRect, expected)
  }

  @MainActor
  func testMovingItemBackInsideShrinksCanvas() throws {
    let state = try makeState()
    var item = rectangle(CGRect(x: -60, y: 10, width: 100, height: 50))
    state.annotations = [item]
    XCTAssertNotNil(state.autoExpandedCanvasRect)

    item.bounds = CGRect(x: 40, y: 10, width: 100, height: 50)
    state.annotations = [item]

    XCTAssertNil(state.autoExpandedCanvasRect)
    XCTAssertEqual(state.activeAnnotationBounds, Self.imageBounds)
  }

  @MainActor
  func testSettingOffKeepsCanvasClamped() throws {
    let state = try makeState(autoExpand: false)
    state.annotations = [rectangle(CGRect(x: 350, y: 250, width: 120, height: 90))]

    XCTAssertFalse(state.autoExpandsCanvas)
    XCTAssertNil(state.appliedCanvasRect)
    XCTAssertEqual(state.activeAnnotationBounds, Self.imageBounds)
    XCTAssertNil(state.makeRenderSnapshot()?.cropRect)
  }

  @MainActor
  func testCaptureMarkupNeverExpands() throws {
    let state = try makeState()
    state.allowsCanvasAutoExpand = false
    state.annotations = [rectangle(CGRect(x: 350, y: 250, width: 120, height: 90))]

    XCTAssertNil(state.autoExpandedCanvasRect)
  }

  @MainActor
  func testExportIncludesGrownArea() async throws {
    let state = try makeState()
    let item = rectangle(CGRect(x: 350, y: 100, width: 150, height: 60))
    state.annotations = [item]
    let expected = Self.imageBounds.union(try footprint(item))

    let snapshot = try XCTUnwrap(state.makeRenderSnapshot())
    let rendered = await AnnotateExporter.renderFinalImage(snapshot: snapshot)
    let image = try XCTUnwrap(rendered)

    XCTAssertEqual(image.size.width, expected.width, accuracy: 1)
    XCTAssertEqual(image.size.height, expected.height, accuracy: 1)
  }

  // MARK: - Crop

  @MainActor
  func testCropCutsItemUntilItIsTouched() throws {
    let state = try makeState()
    var item = rectangle(CGRect(x: 150, y: 100, width: 150, height: 60))
    state.annotations = [item]

    state.beginCropInteraction()
    state.updateCropRect(CGRect(x: 0, y: 0, width: 200, height: 300))
    state.applyCrop()

    // The crop wins: the rectangle it cuts does not grow the canvas back.
    let crop = CGRect(x: 0, y: 0, width: 200, height: 300)
    XCTAssertEqual(state.activeAnnotationBounds, crop)
    XCTAssertNil(state.autoExpandedCanvasRect)

    // Touching it (a move) makes it count again.
    item.bounds = item.bounds.offsetBy(dx: 10, dy: 0)
    state.annotations = [item]
    XCTAssertEqual(state.autoExpandedCanvasRect, crop.union(try footprint(item)))
  }

  @MainActor
  func testCropStartsFromGrownCanvasAndCancelKeepsIt() throws {
    let state = try makeState()
    let item = rectangle(CGRect(x: 350, y: 100, width: 150, height: 60))
    state.annotations = [item]
    let grown = try XCTUnwrap(state.autoExpandedCanvasRect)

    state.beginCropInteraction()
    XCTAssertEqual(state.cropRect, grown)

    state.cancelCrop()
    XCTAssertNil(state.cropRect)
    XCTAssertEqual(state.autoExpandedCanvasRect, grown)
  }

  @MainActor
  func testUndoReturnsTouchedItemToCropCutState() throws {
    let state = try makeState()
    let item = rectangle(CGRect(x: 150, y: 100, width: 150, height: 60))
    state.annotations = [item]
    state.beginCropInteraction()
    state.updateCropRect(CGRect(x: 0, y: 0, width: 200, height: 300))
    state.applyCrop()

    state.setSelectedAnnotationIds([item.id])
    state.nudgeSelectedAnnotation(dx: 10, dy: 0)
    XCTAssertNotNil(state.autoExpandedCanvasRect)

    state.undo()
    XCTAssertNil(state.autoExpandedCanvasRect)
    XCTAssertEqual(state.activeAnnotationBounds, CGRect(x: 0, y: 0, width: 200, height: 300))
  }

  @MainActor
  func testNudgePastEdgeGrowsCanvasInOneUndoStep() throws {
    let state = try makeState()
    let item = rectangle(CGRect(x: 300, y: 100, width: 90, height: 60))
    state.annotations = [item]
    state.setSelectedAnnotationIds([item.id])

    state.nudgeSelectedAnnotation(dx: 50, dy: 0)
    let grown = try XCTUnwrap(state.autoExpandedCanvasRect)
    XCTAssertGreaterThan(grown.maxX, Self.imageBounds.maxX)

    state.undo()
    XCTAssertNil(state.autoExpandedCanvasRect)
  }

  @MainActor
  func testRotationKeepsCropCutItemsCut() throws {
    let state = try makeState()
    state.annotations = [rectangle(CGRect(x: 150, y: 100, width: 150, height: 60))]
    state.beginCropInteraction()
    state.updateCropRect(CGRect(x: 0, y: 0, width: 200, height: 300))
    state.applyCrop()

    state.rotateImage(clockwise: true)

    XCTAssertNil(state.autoExpandedCanvasRect)
    XCTAssertEqual(state.activeAnnotationBounds, try XCTUnwrap(state.cropRect))

    state.undo()
    XCTAssertNil(state.autoExpandedCanvasRect)
    XCTAssertEqual(state.activeAnnotationBounds, CGRect(x: 0, y: 0, width: 200, height: 300))
  }

  // MARK: - Persistence

  @MainActor
  func testRestoringSessionWithoutBaselineNeverGrowsCanvas() throws {
    let state = try makeState()
    state.annotations = [rectangle(CGRect(x: 350, y: 100, width: 150, height: 60))]

    state.restoreCropBaselineFootprints(nil)

    XCTAssertNil(state.autoExpandedCanvasRect)
  }

  @MainActor
  func testPersistedSessionRoundTripsBaseline() throws {
    let state = try makeState()
    state.annotations = [rectangle(CGRect(x: 150, y: 100, width: 150, height: 60))]
    state.beginCropInteraction()
    state.updateCropRect(CGRect(x: 0, y: 0, width: 200, height: 300))
    state.applyCrop()

    let sessionData = AnnotationSessionData.snapshot(from: state, originalImageData: Data())
    let persisted = PersistedAnnotationSession(
      sessionData: sessionData,
      sourceFilePath: "/tmp/a.png",
      sourceFilePathHash: "hash",
      sourceSignature: PersistedFileSignature(fileSize: 0, modifiedAtMilliseconds: 0, pathExtension: "png"),
      createdAt: Date()
    )
    let decoded = try JSONDecoder().decode(
      PersistedAnnotationSession.self,
      from: JSONEncoder().encode(persisted)
    )
    let restored = decoded.sessionData(originalImageData: Data(), cutoutImageData: nil, embeddedImageAssetsData: [:])

    XCTAssertEqual(restored.cropBaselineFootprints, state.cropBaselineFootprints)
  }

  // MARK: - Live gesture

  @MainActor
  func testLiveGestureGrowsWithoutChangingFitBounds() throws {
    let state = try makeState()

    state.beginCanvasGesture()
    XCTAssertEqual(state.canvasFitBounds, Self.imageBounds)
    let outside = CGRect(x: 380, y: 280, width: 60, height: 60)
    state.updateLiveCanvas(including: [outside])

    XCTAssertEqual(state.appliedCanvasRect, Self.imageBounds.union(outside))
    XCTAssertEqual(state.canvasFitBounds, Self.imageBounds)

    state.endCanvasGesture()
    XCTAssertNil(state.appliedCanvasRect)
  }

  @MainActor
  func testDrawingPastEdgeIsNotClampedAndGrowsCanvas() throws {
    let state = try makeState()
    state.selectedTool = .rectangle
    let canvas = DrawingCanvasNSView(state: state)
    canvas.frame = Self.imageBounds
    canvas.displayScale = 1
    canvas.canvasBounds = Self.imageBounds

    canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 300, y: 100)))
    canvas.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 480, y: 160)))
    XCTAssertGreaterThan(try XCTUnwrap(state.liveCanvasBounds).maxX, Self.imageBounds.maxX)
    canvas.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 480, y: 160)))

    let annotation = try XCTUnwrap(state.annotations.last)
    XCTAssertEqual(annotation.bounds.maxX, 480, accuracy: 0.0001)
    XCTAssertNil(state.liveCanvasBounds)
    XCTAssertEqual(state.activeAnnotationBounds.maxX, try footprint(annotation).maxX, accuracy: 0.0001)
  }

  private func mouseEvent(_ type: NSEvent.EventType, at location: CGPoint) -> NSEvent {
    NSEvent.mouseEvent(
      with: type,
      location: location,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: 1
    )!
  }
}
