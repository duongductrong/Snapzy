//
//  AnnotateViewportUIStateTests.swift
//  SnapzyTests
//
//  Characterization tests for AnnotateState viewport geometry (zoom/pan/viewport
//  metrics) and UI state (tool activation, sidebar collapse/restore for crop,
//  drag-to-app preparation state, markAsSaved). The basic sidebar preview-mode
//  no-op is already covered in AnnotateCoreTests
//  (testAnnotateStateToggleSidebarVisibilitySkipsPreviewMode) and is not
//  duplicated here.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class AnnotateViewportUIStateTests: XCTestCase {
  @MainActor private static var retainedAnnotateStates: [AnnotateState] = []

  @MainActor
  private func makeAnnotateState() -> AnnotateState {
    let state = AnnotateState()
    Self.retainedAnnotateStates.append(state)
    return state
  }

  // MARK: - Zoom

  @MainActor
  func testClampedZoomClampsBelowMinimumToMinimum() {
    let state = makeAnnotateState()

    // Default fitScale == 1.0 -> range is [0.25, 4.0].
    XCTAssertEqual(state.clampedZoom(0.01), AnnotateState.minimumZoomLevel, accuracy: 0.0001)
  }

  @MainActor
  func testClampedZoomClampsAboveMaximumToMaximum() {
    let state = makeAnnotateState()

    XCTAssertEqual(state.clampedZoom(999), state.effectiveMaximumZoomLevel, accuracy: 0.0001)
    // Default fitScale == 1.0 keeps the max at the default ceiling.
    XCTAssertEqual(state.effectiveMaximumZoomLevel, AnnotateState.defaultMaximumZoomLevel, accuracy: 0.0001)
  }

  @MainActor
  func testClampedZoomPassesThroughValueWithinRange() {
    let state = makeAnnotateState()

    XCTAssertEqual(state.clampedZoom(1.5), 1.5, accuracy: 0.0001)
  }

  @MainActor
  func testZoomLevelForDisplayedPercentMapsPercentToScaleAtUnitFitScale() {
    let state = makeAnnotateState()

    // fitScale defaults to 1.0, so displayed percent maps 1:1 to zoom level.
    XCTAssertEqual(state.zoomLevel(forDisplayedPercent: 100), 1.0, accuracy: 0.0001)
    XCTAssertEqual(state.zoomLevel(forDisplayedPercent: 200), 2.0, accuracy: 0.0001)
    // Below-range percents clamp up to the minimum zoom level.
    XCTAssertEqual(state.zoomLevel(forDisplayedPercent: 10), AnnotateState.minimumZoomLevel, accuracy: 0.0001)
  }

  @MainActor
  func testZoomLevelForDisplayedPercentDividesByFitScale() {
    let state = makeAnnotateState()
    // Feed a sub-unit fitScale via viewport metrics; a 4x fit widens the range.
    state.updateViewportMetrics(
      containerSize: CGSize(width: 400, height: 400),
      baseCanvasSize: CGSize(width: 100, height: 100),
      fitScale: 0.5
    )

    // percent/100 / fitScale = 1.0 / 0.5 = 2.0, still within [0.25, max].
    XCTAssertEqual(state.zoomLevel(forDisplayedPercent: 100), 2.0, accuracy: 0.0001)
  }

  // MARK: - Pan

  @MainActor
  func testPanIsZeroedWhenContentFitsViewport() {
    let state = makeAnnotateState()
    // Canvas smaller than container -> no overflow -> not interactively pannable.
    state.updateViewportMetrics(
      containerSize: CGSize(width: 800, height: 600),
      baseCanvasSize: CGSize(width: 400, height: 300),
      fitScale: 1.0
    )
    state.zoomLevel = 1.0

    state.pan(by: CGSize(width: 120, height: 80))

    XCTAssertEqual(state.panOffset.width, 0, accuracy: 0.0001)
    XCTAssertEqual(state.panOffset.height, 0, accuracy: 0.0001)
    XCTAssertFalse(state.canPanInteractively)
  }

  @MainActor
  func testPanAppliesDeltaWhenContentOverflowsViewport() {
    let state = makeAnnotateState()
    // Canvas larger than container -> overflow -> pannable.
    state.updateViewportMetrics(
      containerSize: CGSize(width: 200, height: 200),
      baseCanvasSize: CGSize(width: 1000, height: 1000),
      fitScale: 1.0
    )
    state.zoomLevel = 1.0

    XCTAssertTrue(state.canPanInteractively)

    // A small delta stays within the clamp bounds and is applied verbatim.
    state.pan(by: CGSize(width: 30, height: -20))

    XCTAssertEqual(state.panOffset.width, 30, accuracy: 0.0001)
    XCTAssertEqual(state.panOffset.height, -20, accuracy: 0.0001)
  }

  @MainActor
  func testClampPanOffsetKeepsOffsetWithinAllowedBounds() {
    let state = makeAnnotateState()
    state.updateViewportMetrics(
      containerSize: CGSize(width: 200, height: 200),
      baseCanvasSize: CGSize(width: 1000, height: 1000),
      fitScale: 1.0
    )
    state.zoomLevel = 1.0

    // Overflow per side = (1000 - 200) / 2 = 400; margin = 200 * 0.1 = 20.
    let maxPan: CGFloat = 400 + 20

    state.panOffset = CGSize(width: 10_000, height: -10_000)
    state.clampPanOffset()

    XCTAssertEqual(state.panOffset.width, maxPan, accuracy: 0.0001)
    XCTAssertEqual(state.panOffset.height, -maxPan, accuracy: 0.0001)
  }

  @MainActor
  func testResetPanIfNeededZeroesOffsetWhenContentFits() {
    let state = makeAnnotateState()
    state.updateViewportMetrics(
      containerSize: CGSize(width: 800, height: 600),
      baseCanvasSize: CGSize(width: 400, height: 300),
      fitScale: 1.0
    )
    state.zoomLevel = 1.0
    state.panOffset = CGSize(width: 50, height: 50)

    state.resetPanIfNeeded()

    XCTAssertEqual(state.panOffset.width, 0, accuracy: 0.0001)
    XCTAssertEqual(state.panOffset.height, 0, accuracy: 0.0001)
  }

  @MainActor
  func testResetPanIfNeededLeavesHandModeAvailableWhileCanvasOverflows() {
    let state = makeAnnotateState()
    state.updateViewportMetrics(
      containerSize: CGSize(width: 200, height: 200),
      baseCanvasSize: CGSize(width: 1000, height: 1000),
      fitScale: 1.0
    )
    state.isCanvasPanningMode = true

    state.resetPanIfNeeded()

    XCTAssertTrue(state.isCanvasPanningMode)
  }

  // MARK: - Viewport metrics

  @MainActor
  func testUpdateViewportMetricsStoresFitScaleAndBaseCanvasSize() {
    let state = makeAnnotateState()

    state.updateViewportMetrics(
      containerSize: CGSize(width: 640, height: 480),
      baseCanvasSize: CGSize(width: 320, height: 240),
      fitScale: 0.75
    )

    XCTAssertEqual(state.fitScale, 0.75, accuracy: 0.0001)
    XCTAssertEqual(state.baseCanvasDisplaySize.width, 320, accuracy: 0.0001)
    XCTAssertEqual(state.baseCanvasDisplaySize.height, 240, accuracy: 0.0001)
  }

  @MainActor
  func testUpdateViewportMetricsClampsCurrentZoomIntoRange() {
    let state = makeAnnotateState()
    state.zoomLevel = 999

    state.updateViewportMetrics(
      containerSize: CGSize(width: 400, height: 400),
      baseCanvasSize: CGSize(width: 400, height: 400),
      fitScale: 1.0
    )

    XCTAssertEqual(state.zoomLevel, state.effectiveMaximumZoomLevel, accuracy: 0.0001)
  }

  // MARK: - Tool activation

  @MainActor
  func testActivateToolSetsSelectedTool() {
    let state = makeAnnotateState()

    state.activateTool(.arrow)

    XCTAssertEqual(state.selectedTool, .arrow)
  }

  @MainActor
  func testActivateNonSelectionToolClearsSelectedAnnotation() {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .rectangle,
      bounds: CGRect(x: 10, y: 10, width: 40, height: 40),
      properties: AnnotationProperties()
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id

    state.activateTool(.oval)

    XCTAssertNil(state.selectedAnnotationId)
    XCTAssertEqual(state.selectedTool, .oval)
  }

  @MainActor
  func testActivateSelectionToolKeepsSelectedAnnotation() {
    let state = makeAnnotateState()
    let annotation = AnnotationItem(
      type: .rectangle,
      bounds: CGRect(x: 10, y: 10, width: 40, height: 40),
      properties: AnnotationProperties()
    )
    state.annotations = [annotation]
    state.selectedAnnotationId = annotation.id

    state.activateTool(.selection)

    XCTAssertEqual(state.selectedAnnotationId, annotation.id)
    XCTAssertEqual(state.selectedTool, .selection)
  }

  // MARK: - Sidebar collapse/restore for crop

  @MainActor
  func testCollapseSidebarForCropInteractionHidesVisibleSidebar() {
    let state = makeAnnotateState()
    state.showSidebar = true

    state.collapseSidebarForCropInteraction()

    XCTAssertFalse(state.showSidebar)
  }

  @MainActor
  func testCollapseSidebarForCropInteractionIsNoOpWhenAlreadyHidden() {
    let state = makeAnnotateState()
    state.showSidebar = false

    state.collapseSidebarForCropInteraction()
    // No restore flag was set, so a later restore attempt stays hidden.
    state.restoreSidebarAfterCropInteractionIfNeeded()

    XCTAssertFalse(state.showSidebar)
  }

  @MainActor
  func testRestoreSidebarAfterCropInteractionReopensAutoCollapsedSidebar() {
    let state = makeAnnotateState()
    state.showSidebar = true

    state.collapseSidebarForCropInteraction()
    XCTAssertFalse(state.showSidebar)

    state.restoreSidebarAfterCropInteractionIfNeeded()

    XCTAssertTrue(state.showSidebar)
  }

  @MainActor
  func testRestoreSidebarAfterCropInteractionIsNoOpWithoutAutoCollapse() {
    let state = makeAnnotateState()
    state.showSidebar = false

    state.restoreSidebarAfterCropInteractionIfNeeded()

    XCTAssertFalse(state.showSidebar)
  }

  // MARK: - Drag-to-app preparation state (pure state transition, ALWAYS-RUN)

  @MainActor
  func testSetDragToAppPreparationStateTransitionsBetweenStates() {
    let state = makeAnnotateState()

    state.setDragToAppPreparationState(.preparing)
    XCTAssertEqual(state.dragToAppPreparationState, .preparing)

    state.setDragToAppPreparationState(.ready)
    XCTAssertEqual(state.dragToAppPreparationState, .ready)
    XCTAssertTrue(state.dragToAppPreparationState.isInteractive)

    state.setDragToAppPreparationState(.unavailable)
    XCTAssertEqual(state.dragToAppPreparationState, .unavailable)
    XCTAssertFalse(state.dragToAppPreparationState.isInteractive)
  }

  // MARK: - Mark saved

  @MainActor
  func testMarkAsSavedClearsUnsavedChanges() {
    let state = makeAnnotateState()
    state.hasUnsavedChanges = true

    state.markAsSaved()

    XCTAssertFalse(state.hasUnsavedChanges)
  }
}