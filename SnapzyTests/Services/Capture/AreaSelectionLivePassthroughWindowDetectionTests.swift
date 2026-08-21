//
//  AreaSelectionLivePassthroughWindowDetectionTests.swift
//  SnapzyTests
//
//  Regression coverage for https://github.com/duongductrong/Snapzy/pull/472#issuecomment-5357458899:
//  under live-passthrough input (the default capture mode), `AreaSelectionController.handleLivePassthroughButton`
//  routed `.manualRegion` drag/release events straight to `updateManualSelection`/`endManualSelection`,
//  which silently no-op until a selection has formally begun. With window/element auto-detection on,
//  `mouseDown` over a hovered window parks the click as pending (`pendingWindowDetectionStartPoint`) instead
//  of starting one immediately — so every drag and click was dropped on the floor. `AreaSelectionAutoWindowDetectionTests`
//  didn't catch this because it drives `AreaSelectionOverlayView` directly, bypassing this controller-level dispatch.
//

import AppKit
@testable import Snapzy
import XCTest

final class AreaSelectionLivePassthroughWindowDetectionTests: XCTestCase {
  private var originalAutoDetectSetting: Any?

  override func setUp() {
    super.setUp()
    originalAutoDetectSetting = UserDefaults.standard.object(forKey: PreferencesKeys.screenshotAutoDetectWindowUnderCursor)
  }

  override func tearDown() {
    if let originalAutoDetectSetting {
      UserDefaults.standard.set(originalAutoDetectSetting, forKey: PreferencesKeys.screenshotAutoDetectWindowUnderCursor)
    } else {
      UserDefaults.standard.removeObject(forKey: PreferencesKeys.screenshotAutoDetectWindowUnderCursor)
    }
    AreaSelectionController.shared.cancelSelection()
    super.tearDown()
  }

  func testLivePassthroughDrag_pastThreshold_overHoveredWindow_stillStartsManualSelection() throws {
    try skipIfRunningInCI(
      "Presents real overlay windows via the shared AreaSelectionController, which is flaky on headless CI runners"
    )
    UserDefaults.standard.set(true, forKey: PreferencesKeys.screenshotAutoDetectWindowUnderCursor)

    let controller = AreaSelectionController.shared
    controller.startSelection(mode: .screenshot, backdrops: [:]) { _ in }
    guard let window = pooledWindow(), let screen = NSScreen.screens.first(where: { $0.displayID == window.displayID })
    else {
      controller.cancelSelection()
      throw XCTSkip("no pooled AreaSelectionWindow (headless host with no screens)")
    }

    let hoverPoint = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
    let candidateTarget = WindowCaptureTarget(
      windowID: 1,
      frame: screen.frame.insetBy(dx: 50, dy: 50),
      displayID: window.displayID ?? CGMainDisplayID(),
      title: "Test Window",
      bundleIdentifier: "com.example.test",
      ownerPID: 999
    )
    window.overlayView.setAllowsApplicationWindowSelection(true)
    window.overlayView.setWindowSelectionSnapshot(WindowSelectionSnapshot(
      orderedCandidates: [WindowSelectionCandidate(target: candidateTarget, ownerName: "Test", windowLayer: 0)]
    ))
    window.setLivePassthroughInputEnabled(true)
    window.overlayView.handleLivePassthroughMouseMoved(atScreenPoint: hoverPoint)
    XCTAssertEqual(
      window.overlayView.testHoveredWindowCandidate?.target, candidateTarget,
      "test setup must actually be hovering the candidate window before exercising the click/drag path"
    )

    controller.testHandleLivePassthroughButton(.leftMouseDown, at: hoverPoint)
    XCTAssertFalse(
      window.overlayView.isManualSelectionInProgress,
      "mouseDown over a hovered window must not commit to a drag immediately — it might resolve as a click"
    )

    let dragPoint = CGPoint(x: hoverPoint.x + 20, y: hoverPoint.y + 20)
    controller.testHandleLivePassthroughButton(.leftMouseDragged, at: dragPoint)

    XCTAssertTrue(
      window.overlayView.isManualSelectionInProgress,
      "dragging past the click/drag threshold must start a manual region selection, not silently no-op"
    )
  }

  func testLivePassthroughClick_onHoveredWindow_selectsIt() throws {
    try skipIfRunningInCI(
      "Presents real overlay windows via the shared AreaSelectionController, which is flaky on headless CI runners"
    )
    UserDefaults.standard.set(true, forKey: PreferencesKeys.screenshotAutoDetectWindowUnderCursor)

    let controller = AreaSelectionController.shared
    var results: [AreaSelectionResult?] = []
    controller.startSelection(mode: .screenshot, backdrops: [:]) { results.append($0) }
    guard let window = pooledWindow(), let screen = NSScreen.screens.first(where: { $0.displayID == window.displayID })
    else {
      controller.cancelSelection()
      throw XCTSkip("no pooled AreaSelectionWindow (headless host with no screens)")
    }

    let hoverPoint = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
    let candidateTarget = WindowCaptureTarget(
      windowID: 1,
      frame: screen.frame.insetBy(dx: 50, dy: 50),
      displayID: window.displayID ?? CGMainDisplayID(),
      title: "Test Window",
      bundleIdentifier: "com.example.test",
      ownerPID: 999
    )
    window.overlayView.setAllowsApplicationWindowSelection(true)
    window.overlayView.setWindowSelectionSnapshot(WindowSelectionSnapshot(
      orderedCandidates: [WindowSelectionCandidate(target: candidateTarget, ownerName: "Test", windowLayer: 0)]
    ))
    window.setLivePassthroughInputEnabled(true)
    window.overlayView.handleLivePassthroughMouseMoved(atScreenPoint: hoverPoint)

    controller.testHandleLivePassthroughButton(.leftMouseDown, at: hoverPoint)
    controller.testHandleLivePassthroughButton(.leftMouseUp, at: hoverPoint)

    XCTAssertEqual(results.count, 1, "a click on a hovered window must capture it instead of dropping the release")
    guard let result = results.first ?? nil else {
      XCTFail("expected a capture result")
      return
    }
    XCTAssertEqual(result.target, .window(candidateTarget))
  }

  private func pooledWindow() -> AreaSelectionWindow? {
    let mirror = Mirror(reflecting: AreaSelectionController.shared)
    guard let pool = mirror.children.first(where: { $0.label == "windowPool" })?.value
      as? [CGDirectDisplayID: AreaSelectionWindow] else { return nil }
    return pool.values.first
  }
}
