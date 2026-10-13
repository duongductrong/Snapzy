//
//  AreaSelectionRecordingDisplayClickTests.swift
//  SnapzyTests
//
//  Overlay-level tests for picking a whole display in the recording overlay: a plain click in
//  manual-region mode (with and without window auto-detection, and on a display that had no
//  backdrop yet), a drag still drawing an area, and the Enter "whole display" mode.
//

import AppKit
@testable import Snapzy
import XCTest

private final class DisplayClickOverlayDelegate: AreaSelectionOverlayViewDelegate {
  private(set) var selectedRects: [CGRect] = []
  private(set) var selectedWindows: [WindowCaptureTarget] = []
  private(set) var selectedDisplayPoints: [CGPoint] = []
  private(set) var manualSelectionBeganPoints: [CGPoint] = []
  private(set) var manualSelectionEndedPoints: [CGPoint] = []
  private(set) var immediateManualSelectionRequests = 0

  func overlayView(_: AreaSelectionOverlayView, didSelectRect rect: CGRect) {
    selectedRects.append(rect)
  }

  func overlayView(_: AreaSelectionOverlayView, didSelectWindow target: WindowCaptureTarget) {
    selectedWindows.append(target)
  }

  func overlayView(_: AreaSelectionOverlayView, didSelectDisplayAt point: CGPoint) {
    selectedDisplayPoints.append(point)
  }

  func overlayViewDidCancel(_: AreaSelectionOverlayView) {}

  func overlayViewDidRequestDisplayActivation(_: AreaSelectionOverlayView) {}

  func overlayViewDidRequestImmediateManualSelection(_: AreaSelectionOverlayView) {
    immediateManualSelectionRequests += 1
  }

  func overlayView(_: AreaSelectionOverlayView, manualSelectionBeganAt point: CGPoint) {
    manualSelectionBeganPoints.append(point)
  }

  func overlayView(_: AreaSelectionOverlayView, manualSelectionChangedTo _: CGPoint) {}

  func overlayView(_: AreaSelectionOverlayView, manualSelectionEndedAt point: CGPoint) {
    manualSelectionEndedPoints.append(point)
  }
}

final class AreaSelectionRecordingDisplayClickTests: AreaSelectionOverlayTestCase {
  private var hostWindow: NSWindow!
  private var delegate: DisplayClickOverlayDelegate!
  private var originalAutoDetectSetting: Any?

  private let hostWindowFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
  private let candidateTarget = WindowCaptureTarget(
    windowID: 1,
    frame: CGRect(x: 300, y: 300, width: 200, height: 150),
    displayID: CGMainDisplayID(),
    title: "Test Window",
    bundleIdentifier: "com.example.test",
    ownerPID: 999
  )

  /// Inside the candidate window, in screen and local coordinates.
  private let insideScreenPoint = CGPoint(x: 350, y: 350)
  private let insideLocalPoint = CGPoint(x: 250, y: 250)
  /// Inside the overlay but outside the candidate window.
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
    delegate = DisplayClickOverlayDelegate()
    overlayView.delegate = delegate
    overlayView.selectionMode = .recording
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

  private func configure(autoDetect: Bool, mode: AreaSelectionInteractionMode = .manualRegion) {
    UserDefaults.standard.set(autoDetect, forKey: PreferencesKeys.screenshotAutoDetectWindowUnderCursor)
    overlayView.setSelectionEnabled(true)
    overlayView.setInteractionMode(mode, resetSelection: false)
    // Auto-detection is read from defaults here, mirroring session start.
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

  private func click(at localPoint: CGPoint, screenPoint: CGPoint) {
    overlayView.testMouseLocationOverride = screenPoint
    overlayView.mouseMoved(with: mouseEvent(.mouseMoved, at: localPoint))
    overlayView.mouseDown(with: mouseEvent(.leftMouseDown, at: localPoint))
    overlayView.mouseUp(with: mouseEvent(.leftMouseUp, at: localPoint))
  }

  // MARK: - Plain click in manual-region mode

  func testClick_withAutoDetectOff_overAWindow_selectsDisplayNotWindow() {
    configure(autoDetect: false)

    click(at: insideLocalPoint, screenPoint: insideScreenPoint)

    XCTAssertEqual(delegate.selectedDisplayPoints, [insideLocalPoint])
    XCTAssertTrue(delegate.selectedWindows.isEmpty)
    XCTAssertTrue(delegate.manualSelectionBeganPoints.isEmpty, "A plain click must not start a manual drag")
  }

  func testClick_withAutoDetectOn_overAWindow_selectsWindow() {
    configure(autoDetect: true)

    click(at: insideLocalPoint, screenPoint: insideScreenPoint)

    XCTAssertEqual(delegate.selectedWindows, [candidateTarget])
    XCTAssertTrue(delegate.selectedDisplayPoints.isEmpty)
  }

  func testClick_withAutoDetectOn_outsideAnyWindow_selectsDisplay() {
    configure(autoDetect: true)

    click(at: outsideLocalPoint, screenPoint: outsideScreenPoint)

    XCTAssertEqual(delegate.selectedDisplayPoints, [outsideLocalPoint])
    XCTAssertTrue(delegate.selectedWindows.isEmpty)
  }

  func testClick_withSubThresholdJitter_stillSelectsDisplay_withoutWindowHighlight() {
    configure(autoDetect: false)
    overlayView.testMouseLocationOverride = insideScreenPoint
    overlayView.mouseDown(with: mouseEvent(.leftMouseDown, at: insideLocalPoint))

    let jitterPoint = CGPoint(x: insideLocalPoint.x + 2, y: insideLocalPoint.y)
    overlayView.mouseDragged(with: mouseEvent(.leftMouseDragged, at: jitterPoint))
    XCTAssertNil(overlayView.testHoveredWindowCandidate, "Auto-detect is off, so no window may be highlighted")
    XCTAssertTrue(overlayView.testSelectionBorderLayer.isHidden)

    overlayView.mouseUp(with: mouseEvent(.leftMouseUp, at: jitterPoint))

    XCTAssertEqual(delegate.selectedDisplayPoints, [jitterPoint])
    XCTAssertTrue(delegate.manualSelectionBeganPoints.isEmpty)
  }

  func testDrag_pastThreshold_stillDrawsAnArea() {
    configure(autoDetect: false)
    overlayView.testMouseLocationOverride = outsideScreenPoint
    overlayView.mouseDown(with: mouseEvent(.leftMouseDown, at: outsideLocalPoint))

    let dragPoint = CGPoint(x: outsideLocalPoint.x + 100, y: outsideLocalPoint.y + 80)
    overlayView.mouseDragged(with: mouseEvent(.leftMouseDragged, at: dragPoint))
    XCTAssertEqual(delegate.manualSelectionBeganPoints, [outsideLocalPoint], "The drag starts at the original press")

    overlayView.mouseUp(with: mouseEvent(.leftMouseUp, at: dragPoint))

    XCTAssertEqual(delegate.manualSelectionEndedPoints, [dragPoint])
    XCTAssertTrue(delegate.selectedDisplayPoints.isEmpty)
  }

  func testClick_onDisplayWithoutBackdrop_selectsThatDisplay() {
    configure(autoDetect: false)
    // Once the magnifier backdrop lands on the active display, the others report
    // selection-disabled until the controller enables live fallback for them.
    overlayView.setSelectionEnabled(false)
    overlayView.testMouseLocationOverride = outsideScreenPoint
    overlayView.mouseDown(with: mouseEvent(.leftMouseDown, at: outsideLocalPoint))
    XCTAssertEqual(delegate.immediateManualSelectionRequests, 1)

    // What `enableLiveFallbackSelection` does in response, synchronously inside mouseDown.
    overlayView.setSelectionEnabled(true)
    overlayView.activatePendingSelectionIfNeeded()
    XCTAssertTrue(delegate.manualSelectionBeganPoints.isEmpty, "Recording parks the press instead of starting a drag")

    overlayView.mouseUp(with: mouseEvent(.leftMouseUp, at: outsideLocalPoint))

    XCTAssertEqual(delegate.selectedDisplayPoints, [outsideLocalPoint])
  }

  func testParkedPress_survivesDisplayBeingDisabledMidPress() {
    configure(autoDetect: false)
    overlayView.mouseDown(with: mouseEvent(.leftMouseDown, at: outsideLocalPoint))
    XCTAssertTrue(overlayView.hasPendingClick)

    // The active display's magnifier backdrop lands while the button is held, disabling this
    // (secondary) display. The press must be handed to the live-fallback path, not dropped.
    overlayView.setSelectionEnabled(false)
    XCTAssertEqual(delegate.immediateManualSelectionRequests, 1)

    // The controller's live-fallback response.
    overlayView.setSelectionEnabled(true)
    overlayView.activatePendingSelectionIfNeeded()
    XCTAssertTrue(overlayView.hasPendingClick)

    overlayView.mouseUp(with: mouseEvent(.leftMouseUp, at: outsideLocalPoint))

    XCTAssertEqual(delegate.selectedDisplayPoints, [outsideLocalPoint])
  }

  func testScreenshotSession_plainClick_keepsStartingManualSelection() {
    overlayView.selectionMode = .screenshot
    configure(autoDetect: false)

    click(at: outsideLocalPoint, screenPoint: outsideScreenPoint)

    XCTAssertEqual(delegate.manualSelectionBeganPoints, [outsideLocalPoint])
    XCTAssertTrue(delegate.selectedDisplayPoints.isEmpty)
  }

  // MARK: - Events that bypass the overlay

  func testUndeliveredRelease_ofParkedPress_selectsDisplay() {
    configure(autoDetect: false)
    overlayView.mouseDown(with: mouseEvent(.leftMouseDown, at: outsideLocalPoint))
    XCTAssertTrue(overlayView.hasPendingClick)

    overlayView.handleUndeliveredMouseUp(atScreenPoint: outsideScreenPoint)

    XCTAssertEqual(delegate.selectedDisplayPoints, [outsideLocalPoint])
    XCTAssertFalse(overlayView.hasPendingClick)
  }

  func testUndeliveredDrag_ofParkedPress_startsAreaFromOriginalPoint() {
    configure(autoDetect: false)
    overlayView.mouseDown(with: mouseEvent(.leftMouseDown, at: outsideLocalPoint))

    overlayView.handleUndeliveredMouseDragged(
      atScreenPoint: CGPoint(x: outsideScreenPoint.x + 50, y: outsideScreenPoint.y + 50)
    )

    XCTAssertEqual(delegate.manualSelectionBeganPoints, [outsideLocalPoint])
    XCTAssertFalse(overlayView.hasPendingClick)
  }

  func testUndeliveredEvents_withoutParkedPress_areIgnored() {
    configure(autoDetect: false)

    overlayView.handleUndeliveredMouseDragged(atScreenPoint: outsideScreenPoint)
    overlayView.handleUndeliveredMouseUp(atScreenPoint: outsideScreenPoint)

    XCTAssertTrue(delegate.selectedDisplayPoints.isEmpty)
    XCTAssertTrue(delegate.manualSelectionBeganPoints.isEmpty)
  }

  func testFullDisplayMode_undeliveredRelease_selectsDisplay() {
    configure(autoDetect: false, mode: .fullDisplay)
    overlayView.mouseDown(with: mouseEvent(.leftMouseDown, at: outsideLocalPoint))

    overlayView.handleUndeliveredMouseUp(atScreenPoint: outsideScreenPoint)

    XCTAssertEqual(delegate.selectedDisplayPoints, [outsideLocalPoint])
  }

  // MARK: - Whole-display mode

  func testFullDisplayMode_click_selectsDisplayAtReleasePoint_evenOverAWindow() {
    configure(autoDetect: true, mode: .fullDisplay)

    click(at: insideLocalPoint, screenPoint: insideScreenPoint)

    XCTAssertEqual(delegate.selectedDisplayPoints, [insideLocalPoint])
    XCTAssertTrue(delegate.selectedWindows.isEmpty, "Whole-display mode ignores auto-detection")
    XCTAssertTrue(delegate.manualSelectionBeganPoints.isEmpty)
  }

  func testFullDisplayMode_drag_isIgnored_andReleaseSelectsDisplay() {
    configure(autoDetect: false, mode: .fullDisplay)
    overlayView.mouseDown(with: mouseEvent(.leftMouseDown, at: outsideLocalPoint))
    let releasePoint = CGPoint(x: 700, y: 500)
    overlayView.mouseDragged(with: mouseEvent(.leftMouseDragged, at: releasePoint))
    overlayView.mouseUp(with: mouseEvent(.leftMouseUp, at: releasePoint))

    XCTAssertTrue(delegate.manualSelectionBeganPoints.isEmpty)
    XCTAssertEqual(delegate.selectedDisplayPoints, [releasePoint])
  }

  func testFullDisplayMode_highlightFollowsController() {
    configure(autoDetect: false, mode: .fullDisplay)
    XCTAssertTrue(overlayView.testSelectionBorderLayer.isHidden)

    overlayView.setFullDisplayHighlighted(true)
    XCTAssertFalse(overlayView.testSelectionBorderLayer.isHidden)

    overlayView.setFullDisplayHighlighted(false)
    XCTAssertTrue(overlayView.testSelectionBorderLayer.isHidden)
  }

  func testFullDisplayHighlight_isIgnoredOutsideFullDisplayMode() {
    configure(autoDetect: false, mode: .manualRegion)

    overlayView.setFullDisplayHighlighted(true)

    XCTAssertTrue(overlayView.testSelectionBorderLayer.isHidden)
  }
}
