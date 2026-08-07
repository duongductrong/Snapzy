//
//  AreaSelectionAutoWindowDetectionTests.swift
//  SnapzyTests
//
//  Unit tests for "automatically detect window under cursor" in manual-region mode: hovering
//  previews whatever window is under the cursor, a plain click selects it, and a drag past a
//  small threshold falls through to an ordinary manual region selection instead.
//

import AppKit
@testable import Snapzy
import XCTest

private final class RecordingOverlayDelegate: AreaSelectionOverlayViewDelegate {
  private(set) var selectedRects: [CGRect] = []
  private(set) var selectedWindows: [WindowCaptureTarget] = []
  private(set) var manualSelectionBeganPoints: [CGPoint] = []
  private(set) var manualSelectionChangedPoints: [CGPoint] = []
  private(set) var manualSelectionEndedPoints: [CGPoint] = []
  private(set) var didCancel = false

  func overlayView(_: AreaSelectionOverlayView, didSelectRect rect: CGRect) {
    selectedRects.append(rect)
  }

  func overlayView(_: AreaSelectionOverlayView, didSelectWindow target: WindowCaptureTarget) {
    selectedWindows.append(target)
  }

  func overlayViewDidCancel(_: AreaSelectionOverlayView) {
    didCancel = true
  }

  func overlayViewDidRequestDisplayActivation(_: AreaSelectionOverlayView) {}

  func overlayViewDidRequestImmediateManualSelection(_: AreaSelectionOverlayView) {}

  func overlayView(_: AreaSelectionOverlayView, manualSelectionBeganAt point: CGPoint) {
    manualSelectionBeganPoints.append(point)
  }

  func overlayView(_: AreaSelectionOverlayView, manualSelectionChangedTo point: CGPoint) {
    manualSelectionChangedPoints.append(point)
  }

  func overlayView(_: AreaSelectionOverlayView, manualSelectionEndedAt point: CGPoint) {
    manualSelectionEndedPoints.append(point)
  }
}

final class AreaSelectionAutoWindowDetectionTests: AreaSelectionOverlayTestCase {
  private var hostWindow: NSWindow!
  private var delegate: RecordingOverlayDelegate!
  private var originalAutoDetectSetting: Any?

  /// Host window frame in screen coordinates; the overlay fills it as content view, so a
  /// screen point maps to a local point by subtracting this origin.
  private let hostWindowFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
  /// Screen coordinates — local rect is (200, 200, 200, 150) inside the overlay.
  private let candidateScreenFrame = CGRect(x: 300, y: 300, width: 200, height: 150)
  private let candidateTarget = WindowCaptureTarget(
    windowID: 1,
    frame: CGRect(x: 300, y: 300, width: 200, height: 150),
    displayID: CGMainDisplayID(),
    title: "Test Window",
    bundleIdentifier: "com.example.test",
    ownerPID: 999
  )

  /// A point inside `candidateScreenFrame`, expressed in both spaces for convenience.
  private let insideScreenPoint = CGPoint(x: 350, y: 350)
  private let insideLocalPoint = CGPoint(x: 250, y: 250)
  /// Inside the overlay bounds but outside the candidate window.
  private let outsideScreenPoint = CGPoint(x: 150, y: 150)
  private let outsideLocalPoint = CGPoint(x: 50, y: 50)

  override func setUp() {
    super.setUp()
    originalAutoDetectSetting = UserDefaults.standard.object(forKey: PreferencesKeys.screenshotAutoDetectWindowUnderCursor)
    hostWindow = NSWindow(
      contentRect: hostWindowFrame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    hostWindow.contentView = overlayView
    hostWindow.setIsVisible(true)
    delegate = RecordingOverlayDelegate()
    overlayView.delegate = delegate
    overlayView.setAllowsApplicationWindowSelection(true)
    overlayView.setWindowSelectionSnapshot(WindowSelectionSnapshot(
      orderedCandidates: [
        WindowSelectionCandidate(target: candidateTarget, ownerName: "Test", windowLayer: 0),
      ]
    ))
  }

  override func tearDown() {
    if let originalAutoDetectSetting {
      UserDefaults.standard.set(originalAutoDetectSetting, forKey: PreferencesKeys.screenshotAutoDetectWindowUnderCursor)
    } else {
      UserDefaults.standard.removeObject(forKey: PreferencesKeys.screenshotAutoDetectWindowUnderCursor)
    }
    overlayView.testMouseLocationOverride = nil
    hostWindow.contentView = nil
    hostWindow.setIsVisible(false)
    hostWindow = nil
    delegate = nil
    super.tearDown()
  }

  private func setAutoDetect(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: PreferencesKeys.screenshotAutoDetectWindowUnderCursor)
    overlayView.setSelectionEnabled(true)
    overlayView.setInteractionMode(.manualRegion, resetSelection: false)
    // `autoDetectWindowUnderCursor` is read from defaults once here, mirroring session start.
    overlayView.resetSelection()
  }

  private func mouseEvent(_ type: NSEvent.EventType, at localPoint: CGPoint) -> NSEvent {
    NSEvent.mouseEvent(
      with: type,
      location: localPoint,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: hostWindow.windowNumber,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: type == .leftMouseDown ? 1 : 0
    )!
  }

  // MARK: - Hover preview

  func testHover_showsNoHighlight_whenPreferenceOff() {
    setAutoDetect(false)
    overlayView.testMouseLocationOverride = insideScreenPoint

    overlayView.mouseMoved(with: mouseEvent(.mouseMoved, at: insideLocalPoint))

    XCTAssertFalse(overlayView.testIsAutoWindowDetectionActive)
    XCTAssertNil(overlayView.testHoveredWindowCandidate)
    XCTAssertTrue(overlayView.testSelectionBorderLayer.isHidden)
  }

  func testHover_showsWindowHighlight_whenActiveAndCursorOverWindow() {
    setAutoDetect(true)
    overlayView.testMouseLocationOverride = insideScreenPoint

    overlayView.mouseMoved(with: mouseEvent(.mouseMoved, at: insideLocalPoint))

    XCTAssertTrue(overlayView.testIsAutoWindowDetectionActive)
    XCTAssertEqual(overlayView.testHoveredWindowCandidate?.target, candidateTarget)
    XCTAssertFalse(overlayView.testSelectionBorderLayer.isHidden)
  }

  func testHover_showsNoHighlight_whenActiveButCursorOutsideAnyWindow() {
    setAutoDetect(true)
    overlayView.testMouseLocationOverride = outsideScreenPoint

    overlayView.mouseMoved(with: mouseEvent(.mouseMoved, at: outsideLocalPoint))

    XCTAssertNil(overlayView.testHoveredWindowCandidate)
    XCTAssertTrue(overlayView.testSelectionBorderLayer.isHidden)
  }

  // MARK: - Click selects the hovered window

  func testClick_withoutMovement_selectsHoveredWindow() {
    setAutoDetect(true)
    overlayView.testMouseLocationOverride = insideScreenPoint
    overlayView.mouseMoved(with: mouseEvent(.mouseMoved, at: insideLocalPoint))

    overlayView.mouseDown(with: mouseEvent(.leftMouseDown, at: insideLocalPoint))
    XCTAssertFalse(overlayView.isManualSelectionInProgress, "A click on a hovered window must not start a manual drag")

    overlayView.mouseUp(with: mouseEvent(.leftMouseUp, at: insideLocalPoint))

    XCTAssertEqual(delegate.selectedWindows, [candidateTarget])
    XCTAssertTrue(delegate.manualSelectionBeganPoints.isEmpty)
    XCTAssertTrue(delegate.manualSelectionEndedPoints.isEmpty)
  }

  func testClick_underDragThreshold_stillSelectsHoveredWindow() {
    setAutoDetect(true)
    overlayView.testMouseLocationOverride = insideScreenPoint
    overlayView.mouseMoved(with: mouseEvent(.mouseMoved, at: insideLocalPoint))
    overlayView.mouseDown(with: mouseEvent(.leftMouseDown, at: insideLocalPoint))

    // 2pt jitter — under the 4pt threshold, must still resolve as a click.
    let jitterPoint = CGPoint(x: insideLocalPoint.x + 2, y: insideLocalPoint.y)
    overlayView.mouseDragged(with: mouseEvent(.leftMouseDragged, at: jitterPoint))
    XCTAssertFalse(overlayView.isManualSelectionInProgress)

    overlayView.mouseUp(with: mouseEvent(.leftMouseUp, at: jitterPoint))

    XCTAssertEqual(delegate.selectedWindows, [candidateTarget])
    XCTAssertTrue(delegate.manualSelectionBeganPoints.isEmpty)
  }

  // MARK: - Drag past the threshold falls through to manual selection

  func testDrag_pastThreshold_fallsThroughToManualSelectionFromOriginalPoint() {
    setAutoDetect(true)
    overlayView.testMouseLocationOverride = insideScreenPoint
    overlayView.mouseMoved(with: mouseEvent(.mouseMoved, at: insideLocalPoint))
    overlayView.mouseDown(with: mouseEvent(.leftMouseDown, at: insideLocalPoint))

    let dragPoint = CGPoint(x: insideLocalPoint.x + 20, y: insideLocalPoint.y + 20)
    overlayView.mouseDragged(with: mouseEvent(.leftMouseDragged, at: dragPoint))

    XCTAssertTrue(overlayView.isManualSelectionInProgress)
    XCTAssertEqual(delegate.manualSelectionBeganPoints, [insideLocalPoint])
    XCTAssertEqual(delegate.manualSelectionChangedPoints, [dragPoint])
    XCTAssertTrue(delegate.selectedWindows.isEmpty, "Crossing the drag threshold must not also select the window it started on")

    overlayView.mouseUp(with: mouseEvent(.leftMouseUp, at: dragPoint))
    XCTAssertEqual(delegate.manualSelectionEndedPoints, [dragPoint])
  }

  func testDrag_exactlyAtThreshold_countsAsADrag() {
    setAutoDetect(true)
    overlayView.testMouseLocationOverride = insideScreenPoint
    overlayView.mouseMoved(with: mouseEvent(.mouseMoved, at: insideLocalPoint))
    overlayView.mouseDown(with: mouseEvent(.leftMouseDown, at: insideLocalPoint))

    // Exactly the 4pt threshold — the guard uses `>=`, so this must already count as a drag.
    let dragPoint = CGPoint(x: insideLocalPoint.x + 4, y: insideLocalPoint.y)
    overlayView.mouseDragged(with: mouseEvent(.leftMouseDragged, at: dragPoint))

    XCTAssertTrue(overlayView.isManualSelectionInProgress)
    XCTAssertEqual(delegate.manualSelectionBeganPoints, [insideLocalPoint])
  }

  // MARK: - No hovered window at mouseDown time

  func testMouseDown_withNoHoveredWindow_startsManualSelectionImmediately() {
    setAutoDetect(true)
    overlayView.testMouseLocationOverride = outsideScreenPoint
    overlayView.mouseMoved(with: mouseEvent(.mouseMoved, at: outsideLocalPoint))
    XCTAssertNil(overlayView.testHoveredWindowCandidate)

    overlayView.mouseDown(with: mouseEvent(.leftMouseDown, at: outsideLocalPoint))

    XCTAssertTrue(overlayView.isManualSelectionInProgress)
    XCTAssertEqual(delegate.manualSelectionBeganPoints, [outsideLocalPoint])
  }
}
