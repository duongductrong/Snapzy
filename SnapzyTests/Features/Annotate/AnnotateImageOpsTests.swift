//
//  AnnotateImageOpsTests.swift
//  SnapzyTests
//
//  Characterization tests for image load / replace / import behavior on
//  AnnotateState. Pure/state-only assertions — ALWAYS-RUN.
//
//  NOTE: replaceSourceImagePreservingAnnotations offset-merge is already covered
//  by AnnotateCoreTests.testAnnotateState_replaceSourceImagePreservingAnnotationsAppliesOffset,
//  so this file characterizes load + import paths and the import size guard only.
//

import AppKit
import CoreGraphics
import XCTest
@testable import Snapzy

@MainActor
final class AnnotateImageOpsTests: XCTestCase {
  // Keep AnnotateState alive for the test process; XCTest scope cleanup can
  // crash while deinitializing this MainActor app-level ObservableObject.
  private static var retainedAnnotateStates: [AnnotateState] = []

  private func makeAnnotateState() -> AnnotateState {
    let state = AnnotateState()
    Self.retainedAnnotateStates.append(state)
    return state
  }

  private func makeImage(width: Int, height: Int) throws -> NSImage {
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: width, height: height))
    return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
  }

  // MARK: - loadImage

  func testLoadImageSetsSourceAndSizesCanvasToImage() throws {
    let state = makeAnnotateState()
    let image = try makeImage(width: 240, height: 160)

    state.loadImage(image)

    XCTAssertTrue(state.hasImage)
    XCTAssertEqual(state.sourceImage?.size.width ?? 0, 240, accuracy: 0.0001)
    XCTAssertEqual(state.sourceImage?.size.height ?? 0, 160, accuracy: 0.0001)
    XCTAssertEqual(state.imageWidth, 240, accuracy: 0.0001)
    XCTAssertEqual(state.imageHeight, 160, accuracy: 0.0001)
    XCTAssertEqual(state.editorMode, .annotate)
    XCTAssertFalse(state.hasUnsavedChanges)
  }

  func testLoadImageWithURLRecordsSourceURL() throws {
    let state = makeAnnotateState()
    let image = try makeImage(width: 100, height: 100)
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("snapzy-load-\(UUID().uuidString).png")

    state.loadImage(image, url: url)

    XCTAssertEqual(state.sourceURL, url)
  }

  func testLoadImageResetsExistingAnnotations() throws {
    let state = makeAnnotateState()
    state.annotations = [
      AnnotationItem(
        type: .rectangle,
        bounds: CGRect(x: 5, y: 5, width: 20, height: 20),
        properties: AnnotationProperties()
      )
    ]

    state.loadImage(try makeImage(width: 120, height: 80))

    XCTAssertTrue(state.annotations.isEmpty)
    XCTAssertNil(state.selectedAnnotationId)
    XCTAssertFalse(state.canUndo)
    XCTAssertFalse(state.canRedo)
  }

  // MARK: - importImage (image overload) -> Bool

  func testImportImageWithoutExistingBaseBecomesBaseImage() throws {
    let state = makeAnnotateState()
    let image = try makeImage(width: 300, height: 200)

    let accepted = state.importImage(image)

    XCTAssertTrue(accepted)
    XCTAssertTrue(state.hasImage)
    XCTAssertEqual(state.sourceImage?.size.width ?? 0, 300, accuracy: 0.0001)
    // Base image import does not append an embedded-image annotation.
    XCTAssertTrue(state.annotations.isEmpty)
  }

  func testImportImageWithExistingBaseAppendsEmbeddedLayer() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 400, height: 300))

    let accepted = state.importImage(try makeImage(width: 120, height: 90))

    XCTAssertTrue(accepted)
    XCTAssertEqual(state.annotations.count, 1)
    guard case .embeddedImage = try XCTUnwrap(state.annotations.first).type else {
      return XCTFail("Expected embedded-image annotation for secondary import")
    }
    XCTAssertEqual(state.selectedTool, .selection)
    XCTAssertTrue(state.hasUnsavedChanges)
    XCTAssertTrue(state.isCombineMode)
  }

  func testCombineImportPlacesSecondImageFlushRightInHorizontalMode() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 400, height: 300))
    state.importImage(try makeImage(width: 200, height: 100))
    state.setCombineDirection(.horizontal)

    let imported = try XCTUnwrap(state.annotations.first)
    XCTAssertEqual(imported.bounds.minX, 400, accuracy: 0.001)
    XCTAssertEqual(imported.bounds.minY, 0, accuracy: 0.001)
    XCTAssertEqual(imported.bounds.height, 300, accuracy: 0.001)
    XCTAssertEqual(state.combineContentBounds.width, 1000, accuracy: 0.001)
  }

  func testCombineModeSwitchRestoresFreeCanvasBounds() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 400, height: 300))
    state.importImage(try makeImage(width: 200, height: 100))
    state.setCombineMode(.freeCanvas)

    let importedID = try XCTUnwrap(state.annotations.first?.id)
    let freeBounds = CGRect(x: 90, y: -40, width: 240, height: 120)
    state.updateAnnotationBounds(id: importedID, bounds: freeBounds)
    state.setCombineMode(.autoStitch)
    XCTAssertNotEqual(state.annotations.first?.bounds, freeBounds)

    state.setCombineMode(.freeCanvas)
    XCTAssertEqual(state.annotations.first?.bounds, freeBounds)
  }

  func testCombineImageOrderCanMoveImportedImageBeforeBase() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 400, height: 300))
    state.importImage(try makeImage(width: 200, height: 100))

    state.moveCombineImage(at: 1, by: -1)

    XCTAssertEqual(state.sourceImage?.size, NSSize(width: 200, height: 100))
    guard case .embeddedImage(let assetID) = try XCTUnwrap(state.annotations.first).type else {
      return XCTFail("Expected imported image layer")
    }
    XCTAssertEqual(state.embeddedImage(for: assetID)?.size, NSSize(width: 400, height: 300))
    XCTAssertEqual(state.combineImageCount, 2)

    state.undo()
    XCTAssertEqual(state.sourceImage?.size, NSSize(width: 400, height: 300))
    XCTAssertEqual(state.embeddedImage(for: assetID)?.size, NSSize(width: 200, height: 100))
  }

  func testMarkupToolsTreatCombinedImageLayersAsCanvas() throws {
    let embeddedLayer = AnnotationItem(
      type: .embeddedImage(UUID()),
      bounds: CGRect(x: 300, y: 0, width: 200, height: 300),
      properties: AnnotationProperties()
    )
    let rectangle = AnnotationItem(
      type: .rectangle,
      bounds: CGRect(x: 10, y: 10, width: 40, height: 40),
      properties: AnnotationProperties()
    )

    XCTAssertTrue(DrawingCanvasNSView.shouldPrioritizeCanvasMarkup(over: embeddedLayer, selectedTool: .rectangle))
    XCTAssertTrue(DrawingCanvasNSView.shouldPrioritizeCanvasMarkup(over: embeddedLayer, selectedTool: .text))
    XCTAssertFalse(DrawingCanvasNSView.shouldPrioritizeCanvasMarkup(over: embeddedLayer, selectedTool: .selection))
    XCTAssertFalse(DrawingCanvasNSView.shouldPrioritizeCanvasMarkup(over: rectangle, selectedTool: .rectangle))
  }

  func testActivatingMarkupToolClearsCombinedImageSelection() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 400, height: 300))
    state.importImage(try makeImage(width: 200, height: 100))
    let importedID = try XCTUnwrap(state.annotations.first?.id)
    state.setSelectedAnnotationIds([importedID])

    state.activateTool(.rectangle)

    XCTAssertNil(state.selectedAnnotationId)
    XCTAssertTrue(state.selectedAnnotationIds.isEmpty)
    XCTAssertEqual(state.selectedTool, .rectangle)
  }

  // MARK: - addImportedImage size guard

  // Characterization: there is NO oversized-pixel rejection. The only guard is
  // imageSize.width > 0 && height > 0 — a zero-sized image is silently ignored
  // (no annotation appended). Oversized imports are accepted; they only surface
  // a performance warning (see testImportOversizedImageIsAcceptedNotRejected).
  func testAddImportedImageWithZeroSizedImageIsIgnored() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 200, height: 200))
    let emptyImage = NSImage(size: NSSize(width: 0, height: 0))

    state.addImportedImage(emptyImage)

    XCTAssertTrue(state.annotations.isEmpty)
  }

  func testAddImportedImageAppendsValidLayer() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 200, height: 200))

    state.addImportedImage(try makeImage(width: 60, height: 60))

    XCTAssertEqual(state.annotations.count, 1)
    XCTAssertEqual(state.selectedAnnotationId, state.annotations.first?.id)
  }

  func testImportOversizedImageIsAcceptedNotRejected() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 200, height: 200))

    // Large layer: importImage still returns true (no size-limit rejection).
    let accepted = state.importImage(try makeImage(width: 4000, height: 4000))

    XCTAssertTrue(accepted)
    XCTAssertEqual(state.annotations.count, 1)
  }
}