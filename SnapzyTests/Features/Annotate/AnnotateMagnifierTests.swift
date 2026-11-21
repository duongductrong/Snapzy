//
//  AnnotateMagnifierTests.swift
//  SnapzyTests
//
//  Annotate Magnifier tool: creation gestures, lens/source editing rules, image transforms,
//  sidecar persistence, and export pixels (crop offset, blur never revealed).
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class AnnotateMagnifierTests: XCTestCase {
  private static var retainedStates: [AnnotateState] = []

  /// 200×100 pt at 1×: left half red, right half blue, with a 1 px black/white checkerboard in
  /// px x 150…169, y (top-left) 40…59 (a blur over it must not show the pattern in a lens).
  private func splitImage() -> NSImage {
    let cgImage = ColorPickerTestImages.image(width: 200, height: 100, colorSpace: ColorPickerTestImages.sRGB) { x, y in
      if (150...169).contains(x), (40...59).contains(y) {
        return (x + y).isMultiple(of: 2) ? (0, 0, 0) : (255, 255, 255)
      }
      return x < 100 ? (255, 0, 0) : (0, 0, 255)
    }
    return NSImage(cgImage: cgImage, size: CGSize(width: 200, height: 100))
  }

  private func makeState() -> AnnotateState {
    let state = AnnotateState(defaults: UserDefaultsFactory.make())
    Self.retainedStates.append(state)
    state.loadImage(splitImage())
    return state
  }

  private func magnifier(lens: CGRect, source: CGPoint, zoom: CGFloat = 2) -> AnnotationItem {
    var properties = AnnotationProperties()
    properties.strokeWidth = 0
    return AnnotationItem(
      type: .magnifier(MagnifierGeometry(sourceCenter: source, zoom: zoom, showsConnector: false, showsShadow: false)),
      bounds: lens,
      properties: properties
    )
  }

  /// RGB at a top-left pixel of a rendered image.
  private func pixel(_ image: NSImage, x: Int, y: Int) throws -> (r: CGFloat, g: CGFloat, b: CGFloat) {
    let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let rep = NSBitmapImageRep(cgImage: cgImage)
    let color = try XCTUnwrap(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
    return (color.redComponent, color.greenComponent, color.blueComponent)
  }

  // MARK: - Geometry

  func testSourceRect_isLensDividedByZoomAroundCenter() {
    let geometry = MagnifierGeometry(sourceCenter: CGPoint(x: 50, y: 40), zoom: 4)
    XCTAssertEqual(geometry.sourceRect(forLens: CGRect(x: 0, y: 0, width: 80, height: 40)), CGRect(x: 40, y: 35, width: 20, height: 10))
    XCTAssertEqual(MagnifierGeometry(sourceCenter: .zero, zoom: 20).zoom, MagnifierGeometry.maximumZoom)
    XCTAssertEqual(MagnifierGeometry(sourceCenter: .zero, zoom: 1).zoom, MagnifierGeometry.minimumZoom)
  }

  func testMovingLensKeepsSourceButRigidMoveCarriesIt() {
    let item = magnifier(lens: CGRect(x: 0, y: 0, width: 40, height: 40), source: CGPoint(x: 100, y: 50))
    let moved = item.applyingResizeBounds(CGRect(x: 30, y: 10, width: 40, height: 40))
    XCTAssertEqual(moved.type.magnifierGeometry?.sourceCenter, CGPoint(x: 100, y: 50))
    let shifted = item.translatedBy(dx: 5, dy: -3)
    XCTAssertEqual(shifted.type.magnifierGeometry?.sourceCenter, CGPoint(x: 105, y: 47))
    XCTAssertEqual(shifted.bounds.origin, CGPoint(x: 5, y: -3))
  }

  func testHitTesting_lensFaceSelects() {
    let item = magnifier(lens: CGRect(x: 0, y: 0, width: 40, height: 40), source: CGPoint(x: 100, y: 50))
    XCTAssertTrue(item.containsPoint(CGPoint(x: 20, y: 20)))
    XCTAssertTrue(item.edgeBandContains(CGPoint(x: 20, y: 20)))
    XCTAssertFalse(item.containsPoint(CGPoint(x: 100, y: 50)))
  }

  func testRenderBounds_includeSourceOutlineWhenConnectorShows() {
    var item = magnifier(lens: CGRect(x: 0, y: 0, width: 40, height: 40), source: CGPoint(x: 150, y: 50))
    XCTAssertFalse(item.renderBounds.contains(CGPoint(x: 150, y: 50)))
    guard case .magnifier(var geometry) = item.type else { return XCTFail("Expected a magnifier") }
    geometry.showsConnector = true
    item.type = .magnifier(geometry)
    XCTAssertTrue(item.renderBounds.contains(CGPoint(x: 150, y: 50)))
  }

  // MARK: - Persistence

  func testPersistence_roundTrips() throws {
    let item = AnnotationItem(
      type: .magnifier(MagnifierGeometry(sourceCenter: CGPoint(x: 12, y: 34), zoom: 3, shape: .roundedRect, showsConnector: false, showsShadow: true)),
      bounds: CGRect(x: 1, y: 2, width: 60, height: 40),
      properties: AnnotationProperties()
    )
    let data = try JSONEncoder().encode(PersistedAnnotationItem(item: item))
    let decoded = try XCTUnwrap(try JSONDecoder().decode(PersistedAnnotationItem.self, from: data).annotationItem)
    XCTAssertEqual(decoded.type, item.type)
    XCTAssertEqual(decoded.bounds, item.bounds)
  }

  // MARK: - Canvas gestures

  private func makeCanvas() -> (AnnotateState, DrawingCanvasNSView) {
    let state = makeState()
    state.selectedTool = .magnifier
    let canvas = DrawingCanvasNSView(state: state)
    canvas.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
    canvas.displayScale = 1
    canvas.canvasBounds = CGRect(x: 0, y: 0, width: 200, height: 100)
    return (state, canvas)
  }

  private func event(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
    NSEvent.mouseEvent(
      with: type, location: point, modifierFlags: [], timestamp: 0,
      windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
    )!
  }

  func testCanvas_clickPlacesLensOverSpotAndDragPullsItOut() throws {
    let (state, canvas) = makeCanvas()
    canvas.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 50, y: 50)))
    canvas.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 50, y: 50)))
    let clicked = try XCTUnwrap(state.annotations.last)
    XCTAssertEqual(clicked.type.magnifierGeometry?.sourceCenter, CGPoint(x: 50, y: 50))
    XCTAssertEqual(clicked.bounds.midX, 50, accuracy: 0.001)
    XCTAssertEqual(clicked.bounds.midY, 50, accuracy: 0.001)
    XCTAssertEqual(state.selectedAnnotationId, clicked.id)

    state.deselectAnnotation()
    canvas.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 150, y: 70)))
    canvas.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 160, y: 40)))
    canvas.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 160, y: 40)))
    XCTAssertEqual(state.annotations.count, 2)
    let dragged = try XCTUnwrap(state.annotations.last)
    XCTAssertEqual(dragged.type.magnifierGeometry?.sourceCenter, CGPoint(x: 150, y: 70))
    // Lens nudged inside the 200×100 canvas but centred on the release where it fits.
    XCTAssertEqual(dragged.bounds.width, 72, accuracy: 0.001)
    XCTAssertEqual(dragged.bounds.midX, 160, accuracy: 0.001)
    XCTAssertTrue(CGRect(x: 0, y: 0, width: 200, height: 100).contains(dragged.bounds))

    state.undo()
    XCTAssertEqual(state.annotations.count, 1)
  }

  func testStyleChangeRestylesSelectionInOneUndoStep() {
    let state = makeState()
    let item = magnifier(lens: CGRect(x: 0, y: 0, width: 40, height: 40), source: CGPoint(x: 150, y: 50))
    state.annotations = [item]
    state.setSelectedAnnotationIds([item.id])
    let defaultZoom = state.magnifierStyle.zoom
    state.updateMagnifierStyle { $0.zoom = 6 }
    XCTAssertEqual(state.annotations[0].type.magnifierGeometry?.zoom, 6)
    XCTAssertEqual(state.magnifierStyle.zoom, defaultZoom)
    state.undo()
    XCTAssertEqual(state.annotations[0].type.magnifierGeometry?.zoom, 2)
  }

  // MARK: - Image transforms

  func testRotateFlipAndCutOutMoveTheSourceWithThePixels() {
    let state = makeState()
    let item = magnifier(lens: CGRect(x: 10, y: 10, width: 40, height: 40), source: CGPoint(x: 150, y: 70))
    state.annotations = [item]

    state.flipImage(.horizontal)
    XCTAssertEqual(state.annotations[0].type.magnifierGeometry?.sourceCenter, CGPoint(x: 50, y: 70))
    state.flipImage(.horizontal)

    state.rotateImage(clockwise: true)
    let rotated = AnnotateImageRotation.rotatePoint(CGPoint(x: 150, y: 70), oldSize: CGSize(width: 200, height: 100), clockwise: true)
    XCTAssertEqual(state.annotations[0].type.magnifierGeometry?.sourceCenter, rotated)
    state.undo()
    XCTAssertEqual(state.annotations[0].type.magnifierGeometry?.sourceCenter, CGPoint(x: 150, y: 70))
  }

  // MARK: - Export

  func testExport_lensShowsSourcePixelsAfterCropAndFlip() throws {
    let state = makeState()
    // Lens over the red half, magnifying the blue half.
    state.annotations = [magnifier(lens: CGRect(x: 20, y: 30, width: 40, height: 40), source: CGPoint(x: 130, y: 20))]
    var image = try XCTUnwrap(AnnotateExporter.renderFinalImage(state: state))
    var color = try pixel(image, x: 40, y: 50)
    XCTAssertGreaterThan(color.b, 0.9)
    XCTAssertLessThan(color.r, 0.1)

    // Crop shifts the export; the lens must still sample the blue source, not the red under it.
    state.cropRect = CGRect(x: 10, y: 10, width: 180, height: 80)
    image = try XCTUnwrap(AnnotateExporter.renderFinalImage(state: state))
    color = try pixel(image, x: 30, y: 40)
    XCTAssertGreaterThan(color.b, 0.9)
    XCTAssertLessThan(color.r, 0.1)
    state.cropRect = nil

    // Flip: red/blue swap sides. The lens mirrors onto what is now red and its source moves
    // with the blue pixels it showed, so the lens still shows blue over a red background.
    state.flipImage(.horizontal)
    image = try XCTUnwrap(AnnotateExporter.renderFinalImage(state: state))
    color = try pixel(image, x: 160, y: 50)
    XCTAssertGreaterThan(color.b, 0.9)
    XCTAssertLessThan(color.r, 0.1)
    let background = try pixel(image, x: 120, y: 90)
    XCTAssertGreaterThan(background.r, 0.9)
  }

  func testExport_blurUnderTheSourceIsNotRevealed() throws {
    let state = makeState()
    // Checkerboard spans pt x 150…170, y (bottom-left) 40…60; magnify its centre ×8.
    let lens = CGRect(x: 10, y: 10, width: 80, height: 80)
    state.annotations = [magnifier(lens: lens, source: CGPoint(x: 160, y: 50), zoom: 8)]
    var image = try XCTUnwrap(AnnotateExporter.renderFinalImage(state: state))
    let sharp = try (0..<7).map { try pixel(image, x: 30 + $0 * 8, y: 46) }
    XCTAssertTrue(sharp.contains { $0.r > 0.9 } && sharp.contains { $0.r < 0.1 }, "Unblurred lens shows the checkerboard")

    var blurProperties = AnnotationProperties()
    blurProperties.strokeWidth = 10
    state.annotations.insert(
      AnnotationItem(type: .blur(.pixelated), bounds: CGRect(x: 148, y: 38, width: 24, height: 24), properties: blurProperties),
      at: 0
    )
    image = try XCTUnwrap(AnnotateExporter.renderFinalImage(state: state))
    let blurred = try (0..<7).map { try pixel(image, x: 30 + $0 * 8, y: 46) }
    // A raw 1 px checkerboard alternates black/white every 8 lens pixels; through the blur
    // the samples no longer alternate.
    let reds = blurred.map(\.r)
    XCTAssertLessThan((reds.max() ?? 0) - (reds.min() ?? 0), 0.2, "Lens must show the blur, not the raw pattern")
  }

  func testTool_isDrawableWithDefaultKeyZ() {
    XCTAssertTrue(AnnotationToolType.drawableTools.contains(.magnifier))
    XCTAssertTrue(AnnotationToolType.inlineAnnotateTools.contains(.magnifier))
    XCTAssertEqual(AnnotationToolType.magnifier.defaultShortcut, "z")
    XCTAssertTrue(AnnotateShortcutManager.configurableTools.contains(.magnifier))
  }
}
