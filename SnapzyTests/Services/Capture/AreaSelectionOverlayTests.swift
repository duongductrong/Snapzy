//
//  AreaSelectionOverlayTests.swift
//  SnapzyTests
//
//  Remaining overlay tests: coordinates indicator visibility, dimension label
//  presentation, and application-window interaction mode.
//

import XCTest
import AppKit
@testable import Snapzy

final class AreaSelectionOverlayTests: AreaSelectionOverlayTestCase {

  func testCoordinatesIndicator_visibleOnStartSelectionWithoutMouseMove() {
    // 1. GIVEN: overlayView with selection enabled, manual mode, and not selecting
    overlayView.setSelectionEnabled(true)
    overlayView.setInteractionMode(.manualRegion, resetSelection: false)

    // 2. WHEN: resetSelection is called
    overlayView.resetSelection()

    // 3. THEN: The coordinate label text layer and background layer should be visible
    XCTAssertFalse(overlayView.testSizeIndicatorTextLayer.isHidden)
    XCTAssertFalse(overlayView.testSizeIndicatorBackgroundLayer.isHidden)
  }

  /// Regression: AppKit runs a layout pass when the freshly ordered-in overlay window is
  /// displayed — after the session-start indicator was already shown. The layout pass must
  /// re-evaluate the indicator, not hide it, so it stays visible without a mouse move.
  func testCoordinatesIndicator_survivesLayoutPassWithoutMouseMove() {
    // GIVEN: indicator shown at session start (no mouse movement yet)
    overlayView.setSelectionEnabled(true)
    overlayView.setInteractionMode(.manualRegion, resetSelection: false)
    overlayView.resetSelection()
    XCTAssertFalse(overlayView.testSizeIndicatorTextLayer.isHidden)

    // WHEN: AppKit performs a layout pass on the overlay
    overlayView.layout()

    // THEN: the coordinate indicator stays visible
    XCTAssertFalse(overlayView.testSizeIndicatorTextLayer.isHidden)
    XCTAssertFalse(overlayView.testSizeIndicatorBackgroundLayer.isHidden)
  }

  /// Regression: right after a live (backdrop-less) session starts, the async background
  /// snapshot lands and the controller re-renders the (empty) manual selection via
  /// `renderManualSelection(screenRect: nil, currentScreenPoint: nil)`. That re-render must
  /// not hide the coordinate indicator that was shown at session start.
  func testCoordinatesIndicator_survivesEmptySelectionReRenderWithoutMouseMove() {
    // GIVEN: indicator shown at session start (no mouse movement yet)
    overlayView.setSelectionEnabled(true)
    overlayView.setInteractionMode(.manualRegion, resetSelection: false)
    overlayView.resetSelection()
    XCTAssertFalse(overlayView.testSizeIndicatorTextLayer.isHidden)

    // WHEN: the controller re-renders the empty selection (async backdrop applied)
    overlayView.renderManualSelection(screenRect: nil, currentScreenPoint: nil)

    // THEN: the coordinate indicator stays visible
    XCTAssertFalse(overlayView.testSizeIndicatorTextLayer.isHidden)
    XCTAssertFalse(overlayView.testSizeIndicatorBackgroundLayer.isHidden)
  }

  /// Regression: pressing the mouse button starts a selection with a zero-size rect, which
  /// routes through the empty-rect branch of `renderManualSelection`. The coordinate
  /// indicator must stay visible until the drag produces a non-empty rect — the user
  /// should never see the crosshair label vanish between mouseDown and the first movement.
  func testCoordinatesIndicator_survivesMouseDownBeforeFirstDrag() {
    // GIVEN: indicator shown at session start
    overlayView.setSelectionEnabled(true)
    overlayView.setInteractionMode(.manualRegion, resetSelection: false)
    overlayView.resetSelection()
    XCTAssertFalse(overlayView.testSizeIndicatorTextLayer.isHidden)

    // WHEN: the user presses the mouse button (selection begins, rect still zero-size)
    guard let mouseDown = NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: CGPoint(x: 120, y: 120),
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: 1
    ) else {
      XCTFail("Failed to synthesize mouse-down event")
      return
    }
    overlayView.mouseDown(with: mouseDown)
    overlayView.renderManualSelection(screenRect: .zero, currentScreenPoint: nil)

    // THEN: the coordinate indicator stays visible
    XCTAssertFalse(overlayView.testSizeIndicatorTextLayer.isHidden, "Coordinate indicator must stay visible between mouseDown and first drag")
    XCTAssertFalse(overlayView.testSizeIndicatorBackgroundLayer.isHidden, "Background layer must stay visible between mouseDown and first drag")
  }

  /// Once the drag produces a non-empty selection rect, the dimensions label owns the size
  /// indicator layers — a passive refresh must keep that pill visible and must not swap back
  /// to the two-line coordinate label.
  func testDimensionIndicator_survivesLayoutPassWhileSelectionRectVisible() {
    overlayView.setSelectionEnabled(true)
    overlayView.setInteractionMode(.manualRegion, resetSelection: false)
    movePointer(to: CGPoint(x: 400, y: 300))
    overlayView.renderManualSelection(
      screenRect: CGRect(x: 10, y: 10, width: 200, height: 100),
      currentScreenPoint: nil
    )

    overlayView.layout()

    XCTAssertEqual(overlayView.testSizeIndicatorTextLayer.string as? String, "200 × 100")
    XCTAssertFalse(overlayView.testSizeIndicatorTextLayer.isHidden)
    XCTAssertEqual(
      overlayView.testSizeIndicatorBackgroundLayer.backgroundColor,
      CoordinateBubbleStyle.dimensionBackgroundColor.cgColor
    )
  }

  func testDimensionIndicator_survivesLayoutPassInHostedWindow() throws {
    try skipIfRunningInCI("Requires a visible host window which can fail on headless CI runners")

    let hostWindowFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
    let hostWindow = NSWindow(
      contentRect: hostWindowFrame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    hostWindow.contentView = overlayView
    hostWindow.setIsVisible(true)
    defer {
      hostWindow.contentView = nil
      hostWindow.setIsVisible(false)
    }

    overlayView.setSelectionEnabled(true)
    overlayView.setInteractionMode(.manualRegion, resetSelection: false)

    let localPointer = CGPoint(x: 400, y: 300)
    movePointer(to: localPointer)
    let screenPointer = hostWindow.convertPoint(toScreen: localPointer)
    let screenRect = CGRect(
      x: hostWindowFrame.minX + 10,
      y: hostWindowFrame.minY + 10,
      width: 200,
      height: 100
    )

    overlayView.renderManualSelection(screenRect: screenRect, currentScreenPoint: screenPointer)
    overlayView.layout()

    XCTAssertEqual(overlayView.testSizeIndicatorTextLayer.string as? String, "200 × 100")
    XCTAssertFalse(overlayView.testSizeIndicatorTextLayer.isHidden)
    XCTAssertEqual(
      overlayView.testSizeIndicatorBackgroundLayer.backgroundColor,
      CoordinateBubbleStyle.dimensionBackgroundColor.cgColor
    )
  }

  func testDimensionIndicator_showsReadableSingleLineSizeAtSelectionCorner() {
    overlayView.setSelectionEnabled(true)
    overlayView.setInteractionMode(.manualRegion, resetSelection: false)
    movePointer(to: CGPoint(x: 400, y: 300))
    overlayView.renderManualSelection(
      screenRect: CGRect(x: 10, y: 10, width: 640, height: 220),
      currentScreenPoint: nil
    )

    let text = overlayView.testSizeIndicatorTextLayer.string as? String
    XCTAssertEqual(text, "640 × 220")
    XCTAssertFalse(overlayView.testSizeIndicatorTextLayer.isHidden)
    XCTAssertFalse(overlayView.testSizeIndicatorBackgroundLayer.isHidden)
    XCTAssertEqual(
      overlayView.testSizeIndicatorBackgroundLayer.backgroundColor,
      CoordinateBubbleStyle.dimensionBackgroundColor.cgColor
    )

    let labelFrame = overlayView.testSizeIndicatorTextLayer.frame
    let selectionRect = CGRect(x: 10, y: 10, width: 640, height: 220)
    XCTAssertGreaterThanOrEqual(labelFrame.minX, selectionRect.maxX - 4)
    XCTAssertGreaterThanOrEqual(labelFrame.minY, selectionRect.minY - 4)
  }

  func testDimensionIndicator_hiddenWhenPointerOutsideOverlay() {
    overlayView.setSelectionEnabled(true)
    overlayView.setInteractionMode(.manualRegion, resetSelection: false)
    movePointer(to: CGPoint(x: 400, y: 300))
    overlayView.renderManualSelection(
      screenRect: CGRect(x: 10, y: 10, width: 200, height: 100),
      currentScreenPoint: nil
    )
    XCTAssertFalse(overlayView.testSizeIndicatorTextLayer.isHidden)

    movePointer(to: CGPoint(x: -20, y: 300))
    overlayView.renderManualSelection(
      screenRect: CGRect(x: 10, y: 10, width: 200, height: 100),
      currentScreenPoint: nil
    )

    XCTAssertTrue(overlayView.testSizeIndicatorTextLayer.isHidden)
    XCTAssertTrue(overlayView.testSizeIndicatorBackgroundLayer.isHidden)
  }

  func testDimensionIndicator_fallsBackInsideSelectionWhenNearBottomRightEdge() {
    overlayView.setSelectionEnabled(true)
    overlayView.setInteractionMode(.manualRegion, resetSelection: false)
    movePointer(to: CGPoint(x: 760, y: 40))
    overlayView.renderManualSelection(
      screenRect: CGRect(x: 720, y: 10, width: 70, height: 40),
      currentScreenPoint: nil
    )

    let labelFrame = overlayView.testSizeIndicatorTextLayer.frame
    let selectionRect = CGRect(x: 720, y: 10, width: 70, height: 40)
    XCTAssertLessThanOrEqual(labelFrame.maxX, overlayView.bounds.maxX)
    XCTAssertLessThanOrEqual(labelFrame.maxY, overlayView.bounds.maxY)
    XCTAssertGreaterThanOrEqual(labelFrame.minX, selectionRect.minX)
    XCTAssertLessThanOrEqual(labelFrame.maxX, selectionRect.maxX)
  }

  func testCoordinateIndicator_restoresTransparentStyleAfterSelectionEnds() {
    overlayView.setSelectionEnabled(true)
    overlayView.setInteractionMode(.manualRegion, resetSelection: false)
    movePointer(to: CGPoint(x: 120, y: 120))
    overlayView.renderManualSelection(
      screenRect: CGRect(x: 10, y: 10, width: 200, height: 100),
      currentScreenPoint: nil
    )
    XCTAssertEqual(
      overlayView.testSizeIndicatorBackgroundLayer.backgroundColor,
      CoordinateBubbleStyle.dimensionBackgroundColor.cgColor
    )

    overlayView.renderManualSelection(screenRect: nil, currentScreenPoint: nil)

    XCTAssertFalse(overlayView.testSizeIndicatorTextLayer.isHidden)
    XCTAssertEqual(
      overlayView.testSizeIndicatorBackgroundLayer.backgroundColor,
      CoordinateBubbleStyle.backgroundColor.cgColor
    )
    XCTAssertEqual(overlayView.testSizeIndicatorTextLayer.string as? String, "120\n480")
  }

  private func movePointer(to point: CGPoint) {
    guard let event = NSEvent.mouseEvent(
      with: .mouseMoved,
      location: point,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      eventNumber: 0,
      clickCount: 0,
      pressure: 0
    ) else {
      XCTFail("Failed to synthesize mouse-moved event")
      return
    }
    overlayView.mouseMoved(with: event)
  }

  func testApplicationWindowMode_hasNoManualDragInProgress() {
    // GIVEN: application-window interaction mode
    overlayView.setSelectionEnabled(true)
    overlayView.setInteractionMode(.applicationWindow)

    // WHEN: a left mouse-down lands inside the overlay
    guard let mouseDown = NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: CGPoint(x: 120, y: 120),
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: 1
    ) else {
      XCTFail("Failed to synthesize mouse-down event")
      return
    }
    overlayView.mouseDown(with: mouseDown)

    // THEN: window mode is not a manual drag, so re-assertion stays a no-op
    XCTAssertFalse(
      overlayView.isManualSelectionInProgress,
      "Application-window mode must not report a drag in progress"
    )
    overlayView.reassertCursorDuringDrag()
    XCTAssertFalse(overlayView.isManualSelectionInProgress)
  }
}
