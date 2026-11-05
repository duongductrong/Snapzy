//
//  AreaSelectionControllerReleaseEndpointTests.swift
//  SnapzyTests
//
//  Controller-level coverage for #527. During a manual drag the controller's `NSEvent`
//  monitors consume the drag and release events, so the controller (not the overlay view)
//  commits the rect. A fast trackpad release must commit the release event's own location,
//  never `NSEvent.mouseLocation`, which can still hold an earlier sample. These tests drive a
//  real overlay session and feed the monitor events directly, with event timestamps older than
//  the moment they are handled, as on a busy main thread.
//

import AppKit
@testable import Snapzy
import XCTest

final class AreaSelectionControllerReleaseEndpointTests: XCTestCase {
  private var originalAutoDetectSetting: Any?

  override func setUp() {
    super.setUp()
    originalAutoDetectSetting = UserDefaults.standard
      .object(forKey: PreferencesKeys.screenshotAutoDetectWindowUnderCursor)
    UserDefaults.standard.set(false, forKey: PreferencesKeys.screenshotAutoDetectWindowUnderCursor)
  }

  override func tearDown() {
    if let originalAutoDetectSetting {
      UserDefaults.standard.set(
        originalAutoDetectSetting,
        forKey: PreferencesKeys.screenshotAutoDetectWindowUnderCursor
      )
    } else {
      UserDefaults.standard.removeObject(forKey: PreferencesKeys.screenshotAutoDetectWindowUnderCursor)
    }
    AreaSelectionController.shared.cancelSelection()
    super.tearDown()
  }

  /// Recording parks every press as a pending click. The drag that clears the threshold reaches
  /// the controller through the overlay; the release then arrives through the monitor right away.
  func testRecordingPendingClick_fastRelease_commitsReleasePoint() throws {
    try skipIfRunningInCI(
      "Presents real overlay windows via the shared AreaSelectionController, which is flaky on headless CI runners"
    )
    let controller = AreaSelectionController.shared
    var results: [AreaSelectionResult?] = []
    controller.startSelection(mode: .recording, backdrops: [:]) { results.append($0) }
    let window = try presentedWindow()

    let start = CGPoint(x: window.frame.minX + 100, y: window.frame.minY + 100)
    let firstDrag = CGPoint(x: start.x + 30, y: start.y + 20)
    let release = CGPoint(x: start.x + 420, y: start.y + 260)
    let t0 = ProcessInfo.processInfo.systemUptime - 0.5

    window.overlayView.mouseDown(with: overlayEvent(.leftMouseDown, at: start, in: window, timestamp: t0))
    XCTAssertTrue(window.overlayView.hasPendingClick, "recording parks the press as a pending click")
    window.overlayView.mouseDragged(with: overlayEvent(
      .leftMouseDragged,
      at: firstDrag,
      in: window,
      timestamp: t0 + 0.008
    ))
    XCTAssertTrue(window.overlayView.isManualSelectionInProgress, "the drag past the threshold starts the selection")

    controller.testHandleManualSelectionMonitorEvent(monitorEvent(.leftMouseUp, at: release, timestamp: t0 + 0.016))

    XCTAssertEqual(committedRect(results), rect(from: start, to: release))
  }

  /// A press on a display whose backdrop is still loading is parked, then promoted through live
  /// fallback, which reports the press point as the first drag sample. The monitor drag and
  /// release that follow must still move the endpoint to the release.
  func testBackdropLoading_fastRelease_commitsReleasePoint() throws {
    try skipIfRunningInCI(
      "Presents real overlay windows via the shared AreaSelectionController, which is flaky on headless CI runners"
    )
    let controller = AreaSelectionController.shared
    var results: [AreaSelectionResult?] = []
    // A backdrop for a display that does not exist keeps every real display waiting on its own.
    let pendingBackdrop = try XCTUnwrap(Self.makeBackdrop(displayID: CGDirectDisplayID.max - 1))
    controller.startSelection(
      mode: .screenshot,
      backdrops: [pendingBackdrop.displayID: pendingBackdrop]
    ) { results.append($0) }
    let window = try presentedWindow()
    let displayID = try XCTUnwrap(window.displayID)

    let start = CGPoint(x: window.frame.minX + 120, y: window.frame.minY + 120)
    let lateDrag = CGPoint(x: start.x + 150, y: start.y + 90)
    let release = CGPoint(x: start.x + 480, y: start.y + 300)
    let t0 = ProcessInfo.processInfo.systemUptime - 0.5

    window.overlayView.mouseDown(with: overlayEvent(.leftMouseDown, at: start, in: window, timestamp: t0))
    XCTAssertTrue(
      liveFallbackDisplayIDs().contains(displayID),
      "the press on a display without its backdrop must enable live fallback"
    )
    XCTAssertTrue(window.overlayView.isManualSelectionInProgress)

    controller.testHandleManualSelectionMonitorEvent(monitorEvent(
      .leftMouseDragged,
      at: lateDrag,
      timestamp: t0 + 0.008
    ))
    controller.testHandleManualSelectionMonitorEvent(monitorEvent(.leftMouseUp, at: release, timestamp: t0 + 0.016))

    XCTAssertEqual(committedRect(results), rect(from: start, to: release))
  }

  /// Plain manual drag: the release's own location wins over a drag sample that stopped short.
  func testManualDrag_releaseAfterLaggingDrag_commitsReleasePoint() throws {
    try skipIfRunningInCI(
      "Presents real overlay windows via the shared AreaSelectionController, which is flaky on headless CI runners"
    )
    let controller = AreaSelectionController.shared
    var results: [AreaSelectionResult?] = []
    let backdrop = try XCTUnwrap(Self.makeBackdrop(displayID: CGDirectDisplayID.max - 1))
    // Any backdrop keeps the session off the live-passthrough tap, so input uses the monitors.
    controller.startSelection(mode: .screenshot, backdrops: [backdrop.displayID: backdrop]) { results.append($0) }
    let window = try presentedWindow()
    let displayID = try XCTUnwrap(window.displayID)
    controller.enableLiveFallbackSelection(for: displayID)

    let start = CGPoint(x: window.frame.minX + 80, y: window.frame.minY + 80)
    let laggingDrag = CGPoint(x: start.x + 60, y: start.y + 40)
    let release = CGPoint(x: start.x + 360, y: start.y + 240)
    let t0 = ProcessInfo.processInfo.systemUptime - 0.5

    window.overlayView.mouseDown(with: overlayEvent(.leftMouseDown, at: start, in: window, timestamp: t0))
    XCTAssertTrue(window.overlayView.isManualSelectionInProgress)
    controller.testHandleManualSelectionMonitorEvent(monitorEvent(
      .leftMouseDragged,
      at: laggingDrag,
      timestamp: t0 + 0.008
    ))
    controller.testHandleManualSelectionMonitorEvent(monitorEvent(
      .leftMouseDragged,
      at: laggingDrag,
      timestamp: t0 + 0.012
    ))
    controller.testHandleManualSelectionMonitorEvent(monitorEvent(.leftMouseUp, at: release, timestamp: t0 + 0.016))

    XCTAssertEqual(committedRect(results), rect(from: start, to: release))
  }

  // MARK: - Helpers

  private func presentedWindow() throws -> AreaSelectionWindow {
    let mirror = Mirror(reflecting: AreaSelectionController.shared)
    guard let pool = mirror.children.first(where: { $0.label == "windowPool" })?.value
      as? [CGDirectDisplayID: AreaSelectionWindow],
      let window = pool.values.first(where: { $0.frame.width > 600 && $0.frame.height > 400 })
    else {
      AreaSelectionController.shared.cancelSelection()
      throw XCTSkip("no pooled AreaSelectionWindow large enough (headless host with no screens)")
    }
    return window
  }

  private func liveFallbackDisplayIDs() -> Set<CGDirectDisplayID> {
    let mirror = Mirror(reflecting: AreaSelectionController.shared)
    return mirror.children.first(where: { $0.label == "liveFallbackDisplayIDs" })?.value
      as? Set<CGDirectDisplayID> ?? []
  }

  /// An event the overlay window receives, in that window's coordinates.
  private func overlayEvent(
    _ type: NSEvent.EventType,
    at screenPoint: CGPoint,
    in window: NSWindow,
    timestamp: TimeInterval
  ) -> NSEvent {
    NSEvent.mouseEvent(
      with: type,
      location: window.convertPoint(fromScreen: screenPoint),
      modifierFlags: [],
      timestamp: timestamp,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: type == .leftMouseDown ? 1 : 0
    )!
  }

  /// An event as a global monitor sees it: no window, so the location is the screen point.
  private func monitorEvent(_ type: NSEvent.EventType, at screenPoint: CGPoint, timestamp: TimeInterval) -> NSEvent {
    NSEvent.mouseEvent(
      with: type,
      location: screenPoint,
      modifierFlags: [],
      timestamp: timestamp,
      windowNumber: 0,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: 0
    )!
  }

  private func committedRect(_ results: [AreaSelectionResult?]) -> CGRect? {
    XCTAssertEqual(results.count, 1, "the release must complete the selection exactly once")
    guard let result = results.first ?? nil, case .rect(let rect) = result.target else { return nil }
    return rect
  }

  private func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
    CGRect(
      x: min(start.x, end.x),
      y: min(start.y, end.y),
      width: abs(end.x - start.x),
      height: abs(end.y - start.y)
    )
  }

  private static func makeBackdrop(displayID: CGDirectDisplayID) -> AreaSelectionBackdrop? {
    guard let context = CGContext(
      data: nil,
      width: 4,
      height: 4,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.setFillColor(CGColor(gray: 0.5, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    guard let image = context.makeImage() else { return nil }
    return AreaSelectionBackdrop(displayID: displayID, image: image, scaleFactor: 1)
  }
}
