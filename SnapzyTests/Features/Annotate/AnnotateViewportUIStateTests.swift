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

import AppKit
import CoreGraphics
import SwiftUI
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

  @MainActor
  func testTallCanvasAtFiftyTwoPercentHitTestsAcrossItsVisibleWidth() throws {
    let state = AnnotateState(
      image: NSImage(size: CGSize(width: 3_546, height: 16_348)),
      url: URL(fileURLWithPath: "/tmp/tall-annotate-canvas.png")
    )
    Self.retainedAnnotateStates.append(state)
    state.showSidebar = false

    let window = makeAnnotationWindow(state: state)
    defer {
      window.close()
      window.contentView = nil
    }

    window.setFrame(CGRect(x: 0, y: 0, width: 1_500, height: 900), display: false)
    window.makeKeyAndOrderFront(nil)
    drainMainRunLoop()

    state.zoomLevel = state.zoomLevel(forDisplayedPercent: 52)
    // A scrolling capture is commonly viewed away from the centered origin.
    // Keep a non-zero pan in this regression case so the proxy must include the
    // outer translation as well as the outer scale in its visual hit bounds.
    state.panOffset = CGSize(width: -120, height: 80)
    drainMainRunLoop()

    let contentView = try XCTUnwrap(window.contentView)
    let canvas = try XCTUnwrap(findDrawingCanvas(in: contentView))
    let interactionProxy = try XCTUnwrap(findCanvasInteractionProxy(in: contentView))
    XCTAssertLessThan(canvas.frame.width, contentView.bounds.width / 2)

    // The 52%-wide image visually spans the viewport, but this point falls
    // outside the canvas' unzoomed AppKit frame. It must still resolve to the
    // interaction bridge, which forwards events through the drawing view's
    // transformed coordinate conversion.
    let visiblePoint = CGPoint(x: contentView.bounds.maxX - 40, y: contentView.bounds.midY)
    XCTAssertTrue(
      isDescendant(contentView.hitTest(visiblePoint), of: interactionProxy),
      "Zoomed image content outside the unzoomed canvas frame must remain interactive"
    )

    state.selectedTool = .rectangle
    let start = contentView.convert(visiblePoint, to: nil)
    let end = CGPoint(x: start.x - 32, y: start.y - 24)
    try dispatchMouseEvent(
      makeMouseEvent(type: .leftMouseDown, location: start, window: window),
      in: contentView
    )
    try dispatchMouseEvent(
      makeMouseEvent(type: .leftMouseDragged, location: end, window: window),
      in: contentView
    )
    try dispatchMouseEvent(
      makeMouseEvent(type: .leftMouseUp, location: end, window: window),
      in: contentView
    )

    XCTAssertEqual(state.annotations.count, 1)
    XCTAssertGreaterThan(state.annotations[0].bounds.width, 0)
    XCTAssertGreaterThan(state.annotations[0].bounds.height, 0)

    // The same bridge must preserve the existing select → move → resize flow,
    // rather than merely allowing insertion on the formerly inert surface.
    let originalBounds = state.annotations[0].bounds
    state.selectedTool = .selection
    let selectionPoint = windowPoint(
      for: CGPoint(x: originalBounds.midX, y: originalBounds.midY),
      on: canvas
    )
    let movedPoint = CGPoint(x: selectionPoint.x - 24, y: selectionPoint.y + 18)
    try dispatchMouseEvent(
      makeMouseEvent(type: .leftMouseDown, location: selectionPoint, window: window),
      in: contentView
    )
    try dispatchMouseEvent(
      makeMouseEvent(type: .leftMouseDragged, location: movedPoint, window: window),
      in: contentView
    )
    try dispatchMouseEvent(
      makeMouseEvent(type: .leftMouseUp, location: movedPoint, window: window),
      in: contentView
    )

    let movedBounds = state.annotations[0].bounds
    XCTAssertEqual(state.selectedAnnotationId, state.annotations[0].id)
    XCTAssertNotEqual(movedBounds.origin, originalBounds.origin)

    let resizePoint = windowPoint(
      for: CGPoint(x: movedBounds.maxX, y: movedBounds.maxY),
      on: canvas
    )
    let resizedPoint = CGPoint(x: resizePoint.x + 30, y: resizePoint.y + 20)
    try dispatchMouseEvent(
      makeMouseEvent(type: .leftMouseDown, location: resizePoint, window: window),
      in: contentView
    )
    try dispatchMouseEvent(
      makeMouseEvent(type: .leftMouseDragged, location: resizedPoint, window: window),
      in: contentView
    )
    try dispatchMouseEvent(
      makeMouseEvent(type: .leftMouseUp, location: resizedPoint, window: window),
      in: contentView
    )

    let resizedBounds = state.annotations[0].bounds
    XCTAssertGreaterThan(resizedBounds.width, movedBounds.width)
    XCTAssertGreaterThan(resizedBounds.height, movedBounds.height)
  }

  @MainActor
  func testPerspectiveMockupDoesNotInstallRectangularInteractionProxy() throws {
    let state = makeAnnotateStateWithImage()
    state.editorMode = .mockup
    state.mockupRotationY = 18
    let window = makeAnnotationWindow(state: state)
    defer {
      window.close()
      window.contentView = nil
    }

    window.makeKeyAndOrderFront(nil)
    drainMainRunLoop()

    XCTAssertNil(findCanvasInteractionProxy(in: try XCTUnwrap(window.contentView)))
  }

  @MainActor
  func testZoomShortcutOnlyUpdatesTheOriginatingAnnotationWindow() {
    let stateA = makeAnnotateStateWithImage()
    let stateB = makeAnnotateStateWithImage()
    let windowA = makeAnnotationWindow(state: stateA)
    let windowB = makeAnnotationWindow(state: stateB)
    defer {
      windowA.close()
      windowB.close()
      windowA.contentView = nil
      windowB.contentView = nil
    }

    windowA.makeKeyAndOrderFront(nil)
    windowB.orderFrontRegardless()
    drainMainRunLoop()

    let event = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: .command,
      timestamp: 0,
      windowNumber: windowA.windowNumber,
      context: nil,
      characters: "=",
      charactersIgnoringModifiers: "=",
      isARepeat: false,
      keyCode: 24
    )

    XCTAssertNotNil(event)
    XCTAssertTrue(windowA.performKeyEquivalent(with: event!))
    drainMainRunLoop()

    XCTAssertEqual(stateA.zoomLevel, 1.25, accuracy: 0.0001)
    XCTAssertEqual(stateB.zoomLevel, 1.0, accuracy: 0.0001)

    stateA.updateViewportMetrics(
      containerSize: CGSize(width: 200, height: 200),
      baseCanvasSize: CGSize(width: 1_000, height: 1_000),
      fitScale: 1.0
    )
    stateB.updateViewportMetrics(
      containerSize: CGSize(width: 200, height: 200),
      baseCanvasSize: CGSize(width: 1_000, height: 1_000),
      fitScale: 1.0
    )

    NotificationCenter.default.post(name: .annotateSpaceDown, object: windowA)
    NotificationCenter.default.post(
      name: .annotatePanDrag,
      object: windowA,
      userInfo: ["deltaX": CGFloat(24), "deltaY": CGFloat(-12)]
    )
    drainMainRunLoop()

    XCTAssertTrue(stateA.isSpacePanning)
    XCTAssertFalse(stateB.isSpacePanning)
    XCTAssertEqual(stateA.panOffset.width, 24, accuracy: 0.0001)
    XCTAssertEqual(stateA.panOffset.height, -12, accuracy: 0.0001)
    XCTAssertEqual(stateB.panOffset, .zero)

    NotificationCenter.default.post(name: .annotateSpaceUp, object: windowA)
    drainMainRunLoop()
    XCTAssertFalse(stateA.isSpacePanning)
    XCTAssertFalse(stateB.isSpacePanning)

    windowA.close()
    drainMainRunLoop()
    XCTAssertEqual(stateB.zoomLevel, 1.0, accuracy: 0.0001)
    XCTAssertEqual(stateB.panOffset, .zero)
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

  @MainActor
  private func makeAnnotateStateWithImage() -> AnnotateState {
    let state = AnnotateState(
      image: NSImage(size: NSSize(width: 100, height: 100)),
      url: URL(fileURLWithPath: "/tmp/annotate-window-isolation.png")
    )
    Self.retainedAnnotateStates.append(state)
    return state
  }

  @MainActor
  private func makeAnnotationWindow(state: AnnotateState) -> AnnotateWindow {
    let window = AnnotateWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600))
    window.interactionState = state
    let eventRouter = AnnotateWindowEventRouter(window: window)
    window.contentView = NSHostingView(rootView: AnnotateCanvasView(state: state, eventRouter: eventRouter))
    return window
  }

  @MainActor
  private func drainMainRunLoop() {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
  }

  @MainActor
  private func findDrawingCanvas(in view: NSView) -> DrawingCanvasNSView? {
    if let canvas = view as? DrawingCanvasNSView {
      return canvas
    }
    for subview in view.subviews {
      if let canvas = findDrawingCanvas(in: subview) {
        return canvas
      }
    }
    return nil
  }

  @MainActor
  private func findCanvasInteractionProxy(in view: NSView) -> CanvasInteractionProxyNSView? {
    if let proxy = view as? CanvasInteractionProxyNSView {
      return proxy
    }
    for subview in view.subviews {
      if let proxy = findCanvasInteractionProxy(in: subview) {
        return proxy
      }
    }
    return nil
  }

  @MainActor
  private func isDescendant(_ view: NSView?, of ancestor: NSView) -> Bool {
    var current = view
    while let view = current {
      if view === ancestor {
        return true
      }
      current = view.superview
    }
    return false
  }

  @MainActor
  private func windowPoint(for imagePoint: CGPoint, on canvas: DrawingCanvasNSView) -> CGPoint {
    let displayPoint = CGPoint(
      x: (imagePoint.x - canvas.canvasBounds.minX) * canvas.displayScale,
      y: (imagePoint.y - canvas.canvasBounds.minY) * canvas.displayScale
    )
    return canvas.convert(displayPoint, to: nil)
  }

  @MainActor
  private func dispatchMouseEvent(_ event: NSEvent, in contentView: NSView) throws {
    let point = contentView.convert(event.locationInWindow, from: nil)
    let target = try XCTUnwrap(contentView.hitTest(point))
    switch event.type {
    case .leftMouseDown:
      target.mouseDown(with: event)
    case .leftMouseDragged:
      target.mouseDragged(with: event)
    case .leftMouseUp:
      target.mouseUp(with: event)
    default:
      XCTFail("Unexpected event type: \(event.type)")
    }
  }

  private func makeMouseEvent(type: NSEvent.EventType, location: CGPoint, window: NSWindow) -> NSEvent {
    NSEvent.mouseEvent(
      with: type,
      location: location,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: 1
    )!
  }
}
