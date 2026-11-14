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

  // MARK: - Positional combine drop (issue #739)

  func testDropBelowSingleImageStartsCombineAndStitchesUnderneath() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 400, height: 300))

    let target = try XCTUnwrap(state.resolveCombineDrop(at: CGPoint(x: 200, y: -40)))
    XCTAssertEqual(target, .stitch(anchor: AnnotateState.combineBaseLayerID, edge: .bottom))
    let id = try XCTUnwrap(state.importImage(try makeImage(width: 200, height: 100), sourceData: nil, at: target))

    XCTAssertTrue(state.isCombineMode)
    XCTAssertTrue(state.hasCustomCombineArrangement)
    let bounds = try XCTUnwrap(state.annotations.first { $0.id == id }?.bounds)
    XCTAssertEqual(bounds.maxY, 0, accuracy: 0.001)
    XCTAssertEqual(bounds.width, 400, accuracy: 0.001)
    XCTAssertEqual(state.combineStitchedOrder, [AnnotateState.combineBaseLayerID, id])
  }

  func testDropInCentreOfSingleImageStartsCombineAsOverlay() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 400, height: 300))

    let target = try XCTUnwrap(state.resolveCombineDrop(at: CGPoint(x: 200, y: 140)))
    let id = try XCTUnwrap(state.importImage(try makeImage(width: 400, height: 400), sourceData: nil, at: target))

    XCTAssertTrue(state.isCombineMode)
    XCTAssertTrue(state.isCombineOverlay(id))
    XCTAssertEqual(state.combineContentBounds, state.sourceImageBounds)
    let bounds = try XCTUnwrap(state.annotations.first { $0.id == id }?.bounds)
    XCTAssertEqual(bounds.width, 150, accuracy: 0.001) // fits half of the 300pt height
    XCTAssertEqual(bounds.midX, 200, accuracy: 0.001)
    XCTAssertEqual(bounds.midY, 140, accuracy: 0.001)
  }

  func testOverlayInCombineIsExcludedFromStitchAndUndoable() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 400, height: 300))
    state.importImage(try makeImage(width: 200, height: 100))
    state.setCombineDirection(.horizontal)
    let contentBefore = state.combineContentBounds

    let overlayID = try XCTUnwrap(state.importImage(
      try makeImage(width: 80, height: 80),
      sourceData: nil,
      at: .overlay(at: CGPoint(x: 200, y: 150))
    ))

    XCTAssertTrue(state.isCombineOverlay(overlayID))
    XCTAssertEqual(state.combineImageCount, 2)
    XCTAssertEqual(state.combineContentBounds, contentBefore)
    XCTAssertFalse(state.isAutoStitchedLayer(try XCTUnwrap(state.annotations.last)))

    state.undo()
    XCTAssertFalse(state.annotations.contains { $0.id == overlayID })
  }

  func testDraggingStitchedImageReordersDetachesAndReattaches() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 400, height: 300))
    state.importImage(try makeImage(width: 200, height: 300))
    state.setCombineDirection(.horizontal)
    let id = try XCTUnwrap(state.annotations.first?.id)
    let base = AnnotateState.combineBaseLayerID

    // Drag it to the far left of the base → it moves before the base.
    state.saveState()
    state.commitCombineLayerDrag(
      id: id,
      target: state.resolveCombineDrop(at: CGPoint(x: -30, y: 150), movingAnnotationID: id),
      droppedBounds: .zero
    )
    XCTAssertEqual(state.combineStitchedOrder, [id, base])
    XCTAssertEqual(try XCTUnwrap(state.annotations.first?.bounds).maxX, 0, accuracy: 0.001)

    // Releasing it over its own slot (a jitter) changes nothing.
    XCTAssertNil(state.resolveCombineDrop(at: CGPoint(x: -100, y: 150), movingAnnotationID: id))

    // Drag into the middle of the base → it floats as an overlay.
    state.saveState()
    let centre = CGPoint(x: 200, y: 140)
    state.commitCombineLayerDrag(
      id: id,
      target: state.resolveCombineDrop(at: centre, movingAnnotationID: id),
      droppedBounds: CGRect(x: 100, y: 0, width: 200, height: 300)
    )
    XCTAssertTrue(state.isCombineOverlay(id))
    XCTAssertEqual(state.combineStitchedOrder, [base])
    XCTAssertEqual(state.combineContentBounds, state.sourceImageBounds)

    // Moving the overlay inside the content is a plain move.
    XCTAssertNil(state.resolveCombineDrop(at: CGPoint(x: 300, y: 100), movingAnnotationID: id))

    // Dragging it out past the right edge stitches it back.
    state.saveState()
    state.commitCombineLayerDrag(
      id: id,
      target: state.resolveCombineDrop(at: CGPoint(x: 460, y: 150), movingAnnotationID: id),
      droppedBounds: .zero
    )
    XCTAssertFalse(state.isCombineOverlay(id))
    XCTAssertEqual(state.combineStitchedOrder, [base, id])

    state.undo()
    XCTAssertTrue(state.isCombineOverlay(id))
  }

  func testArrangementButtonResetsCustomGridAndUndoRestoresIt() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 400, height: 300))
    let id = try XCTUnwrap(state.importImage(
      try makeImage(width: 400, height: 300),
      sourceData: nil,
      at: .stitch(anchor: AnnotateState.combineBaseLayerID, edge: .top)
    ))
    XCTAssertTrue(state.hasCustomCombineArrangement)
    XCTAssertEqual(state.combineStitchedOrder, [id, AnnotateState.combineBaseLayerID])

    state.setCombineDirection(.horizontal)
    XCTAssertFalse(state.hasCustomCombineArrangement)
    XCTAssertEqual(try XCTUnwrap(state.annotations.first?.bounds).minX, 400, accuracy: 0.001)

    state.undo()
    XCTAssertTrue(state.hasCustomCombineArrangement)
    XCTAssertEqual(try XCTUnwrap(state.annotations.first?.bounds).minY, 300, accuracy: 0.001)
  }

  func testLegacyVerticalSessionKeepsUpwardVisualOrder() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 400, height: 300))
    state.importImage(try makeImage(width: 400, height: 300))
    let id = try XCTUnwrap(state.annotations.first?.id)

    state.restoreCombineSession(CombineSessionSnapshot(
      mode: .autoStitch,
      direction: .vertical,
      gap: 0,
      freeBoundsByAnnotationID: [:],
      stripsGrowDownward: false
    ))

    XCTAssertEqual(try XCTUnwrap(state.annotations.first?.bounds).minY, 300, accuracy: 0.001)
    XCTAssertEqual(state.combineStitchedOrder, [id, AnnotateState.combineBaseLayerID])
  }

  // MARK: - Arrange (z-order)

  func testArrangeOverlaysStepsPastOverlappingLayersOnly() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 400, height: 300))
    let a = try XCTUnwrap(state.importImage(try makeImage(width: 100, height: 100), sourceData: nil, at: .overlay(at: CGPoint(x: 100, y: 150))))
    let far = try XCTUnwrap(state.importImage(try makeImage(width: 100, height: 100), sourceData: nil, at: .overlay(at: CGPoint(x: 330, y: 150))))
    let b = try XCTUnwrap(state.importImage(try makeImage(width: 100, height: 100), sourceData: nil, at: .overlay(at: CGPoint(x: 140, y: 150))))
    func order() -> [UUID] { state.annotations.map(\.id) }
    XCTAssertEqual(order(), [a, far, b])

    state.setSelectedAnnotationIds([a])
    XCTAssertTrue(state.arrangeSelectedAnnotations(.bringForward))
    // `far` does not overlap `a`, so one step lands `a` above `b`.
    XCTAssertEqual(order(), [far, b, a])
    XCTAssertFalse(state.canArrangeSelection(.bringForward))
    XCTAssertFalse(state.canArrangeSelection(.bringToFront))

    XCTAssertTrue(state.arrangeSelectedAnnotations(.sendToBack))
    XCTAssertEqual(order(), [a, far, b])

    state.undo()
    XCTAssertEqual(order(), [far, b, a])
  }

  func testArrangeKeepsStitchedImagesBelowAndMarkupInItsTier() throws {
    let state = makeAnnotateState()
    state.loadImage(try makeImage(width: 400, height: 300))
    let overlay = try XCTUnwrap(state.importImage(try makeImage(width: 100, height: 100), sourceData: nil, at: .overlay(at: CGPoint(x: 200, y: 150))))
    let stitched = try XCTUnwrap(state.importImage(
      try makeImage(width: 400, height: 300),
      sourceData: nil,
      at: .stitch(anchor: AnnotateState.combineBaseLayerID, edge: .right)
    ))
    let rect = AnnotationItem(type: .rectangle, bounds: CGRect(x: 150, y: 100, width: 100, height: 100), properties: AnnotationProperties())
    state.annotations.append(rect)

    // Stitched images are never arranged.
    state.setSelectedAnnotationIds([stitched])
    XCTAssertFalse(state.canArrangeSelection(.bringToFront))

    // Sending the overlay to the back keeps it above the stitched floor.
    state.setSelectedAnnotationIds([overlay])
    _ = state.arrangeSelectedAnnotations(.sendToBack)
    let renderOrder = state.annotations.renderOrdered.map(\.id)
    XCTAssertLessThan(try XCTUnwrap(renderOrder.firstIndex(of: stitched)), try XCTUnwrap(renderOrder.firstIndex(of: overlay)))

    // Markup can't be sent beneath images: nothing below it in its own tier.
    state.setSelectedAnnotationIds([rect.id])
    XCTAssertFalse(state.canArrangeSelection(.sendToBack))
  }

  func testDrawingToolPressIntentTable() throws {
    let rectangle = AnnotationItem(
      type: .rectangle,
      bounds: CGRect(x: 10, y: 10, width: 40, height: 40),
      properties: AnnotationProperties()
    )
    let text = AnnotationItem(
      type: .text("Hello"),
      bounds: CGRect(x: 100, y: 10, width: 80, height: 24),
      properties: AnnotationProperties()
    )
    let embeddedLayer = AnnotationItem(
      type: .embeddedImage(UUID()),
      bounds: CGRect(x: 300, y: 0, width: 200, height: 300),
      properties: AnnotationProperties()
    )

    func intent(
      _ tool: AnnotationToolType,
      _ hit: AnnotationItem?,
      selected: Set<UUID> = [],
      option: Bool = false
    ) -> DrawingToolPressIntent {
      DrawingCanvasNSView.drawingToolPressIntent(
        tool: tool,
        edgeHit: hit,
        selectedIds: selected,
        optionHeld: option
      )
    }

    for tool in AnnotationToolType.allCases {
      for option in [false, true] {
        // No edge hit always draws.
        XCTAssertEqual(intent(tool, nil, option: option), .draw, "\(tool) no hit, option \(option)")
        // Option always draws, even on a selected edge.
        if option {
          XCTAssertEqual(intent(tool, rectangle, option: true), .draw, "\(tool) unselected, option")
          XCTAssertEqual(
            intent(tool, rectangle, selected: [rectangle.id], option: true),
            .draw,
            "\(tool) selected, option"
          )
          continue
        }

        let unselected = intent(tool, rectangle)
        let selected = intent(tool, rectangle, selected: [rectangle.id])
        switch tool {
        case .selection, .crop:
          // Routed before the drawing-tool intent is consulted.
          XCTAssertEqual(unselected, .draw, "\(tool) unselected")
          XCTAssertEqual(selected, .draw, "\(tool) selected")
        case .text, .counter:
          XCTAssertEqual(unselected, .selectNow(item: rectangle, editTextOnClick: false), "\(tool) unselected")
          XCTAssertEqual(selected, .moveSelection(anchor: rectangle, editTextOnClick: false), "\(tool) selected")
        default:
          XCTAssertEqual(unselected, .drawThenMaybeSelect(candidate: rectangle), "\(tool) unselected")
          XCTAssertEqual(selected, .moveSelection(anchor: rectangle, editTextOnClick: false), "\(tool) selected")
        }
      }
    }

    // Text on an existing text selects it and edits on click; Text on a shape
    // only selects it.
    XCTAssertEqual(intent(.text, text), .selectNow(item: text, editTextOnClick: true))
    XCTAssertEqual(intent(.text, rectangle), .selectNow(item: rectangle, editTextOnClick: false))
    XCTAssertEqual(intent(.counter, text), .selectNow(item: text, editTextOnClick: false))
    XCTAssertEqual(intent(.rectangle, text), .drawThenMaybeSelect(candidate: text))
    // An already-selected text still drag-moves with the Text tool (rule 2),
    // but a click without movement enters edit mode (D-2). Other tools on a
    // selected text, and the Text tool on a selected shape, only move.
    XCTAssertEqual(intent(.text, text, selected: [text.id]), .moveSelection(anchor: text, editTextOnClick: true))
    XCTAssertEqual(intent(.counter, text, selected: [text.id]), .moveSelection(anchor: text, editTextOnClick: false))
    XCTAssertEqual(intent(.rectangle, text, selected: [text.id]), .moveSelection(anchor: text, editTextOnClick: false))
    XCTAssertEqual(
      intent(.text, rectangle, selected: [rectangle.id]),
      .moveSelection(anchor: rectangle, editTextOnClick: false)
    )
    XCTAssertEqual(intent(.text, text, selected: [text.id], option: true), .draw)

    // Combined images are canvas for drawing tools (#377), even if passed in.
    for tool in AnnotationToolType.allCases {
      XCTAssertEqual(intent(tool, embeddedLayer), .draw, "\(tool) embedded image")
      XCTAssertEqual(intent(tool, embeddedLayer, selected: [embeddedLayer.id]), .draw, "\(tool) selected embedded image")
    }
  }

  func testDrawingToolHoverCursorMirrorsPressIntent() {
    let item = AnnotationItem(
      type: .rectangle,
      bounds: CGRect(x: 10, y: 10, width: 40, height: 40),
      properties: AnnotationProperties()
    )
    let cases: [(DrawingToolPressIntent, NSCursor)] = [
      (.moveSelection(anchor: item, editTextOnClick: false), .openHand),
      (.moveSelection(anchor: item, editTextOnClick: true), .openHand),
      (.selectNow(item: item, editTextOnClick: true), .pointingHand),
      (.selectNow(item: item, editTextOnClick: false), .pointingHand),
      (.drawThenMaybeSelect(candidate: item), .pointingHand),
      (.draw, .arrow),
    ]
    for (intent, expected) in cases {
      XCTAssertTrue(DrawingCanvasNSView.drawingToolHoverCursor(for: intent) === expected, "\(intent)")
    }
  }

  func testDrawingToolPressIntentTextEditOnClickId() {
    let item = AnnotationItem(
      type: .text("Hello"),
      bounds: CGRect(x: 10, y: 10, width: 80, height: 24),
      properties: AnnotationProperties()
    )
    XCTAssertEqual(DrawingToolPressIntent.moveSelection(anchor: item, editTextOnClick: true).textEditOnClickId, item.id)
    XCTAssertEqual(DrawingToolPressIntent.selectNow(item: item, editTextOnClick: true).textEditOnClickId, item.id)
    XCTAssertNil(DrawingToolPressIntent.moveSelection(anchor: item, editTextOnClick: false).textEditOnClickId)
    XCTAssertNil(DrawingToolPressIntent.selectNow(item: item, editTextOnClick: false).textEditOnClickId)
    XCTAssertNil(DrawingToolPressIntent.drawThenMaybeSelect(candidate: item).textEditOnClickId)
    XCTAssertNil(DrawingToolPressIntent.draw.textEditOnClickId)
  }

  func testDrawingToolOptionDrawsOnlyForDrawingTools() {
    for tool in AnnotationToolType.allCases {
      XCTAssertFalse(DrawingCanvasNSView.drawingToolOptionDraws(tool: tool, optionHeld: false), "\(tool)")
      XCTAssertEqual(
        DrawingCanvasNSView.drawingToolOptionDraws(tool: tool, optionHeld: true),
        tool != .selection && tool != .crop,
        "\(tool)"
      )
    }
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
