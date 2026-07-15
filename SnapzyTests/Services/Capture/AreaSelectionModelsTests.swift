//
//  AreaSelectionModelsTests.swift
//  SnapzyTests
//
//  Unit tests for AreaSelectionTarget, AreaSelectionResult, and WindowCaptureTarget.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class AreaSelectionModelsTests: XCTestCase {

  func testAreaSelectionTarget_rect_returnsRect() {
    let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
    let target = AreaSelectionTarget.rect(rect)
    XCTAssertEqual(target.rect, rect)
    XCTAssertNil(target.windowTarget)
  }

  func testAreaSelectionTarget_window_returnsFrameAndTarget() {
    let windowTarget = WindowCaptureTarget(
      windowID: 42,
      frame: CGRect(x: 0, y: 0, width: 800, height: 600),
      displayID: 1,
      title: "Test",
      bundleIdentifier: "com.test",
      ownerPID: nil
    )
    let target = AreaSelectionTarget.window(windowTarget)
    XCTAssertEqual(target.rect, windowTarget.frame)
    XCTAssertEqual(target.windowTarget, windowTarget)
  }

  func testAreaSelectionResult_defaultDisplayIDs() {
    let result = AreaSelectionResult(
      target: .rect(CGRect(x: 0, y: 0, width: 100, height: 100)),
      displayID: 1,
      mode: .screenshot
    )
    XCTAssertEqual(result.displayIDs, [1])
    XCTAssertFalse(result.spansMultipleDisplays)
  }

  func testAreaSelectionResult_multipleDisplayIDs() {
    let result = AreaSelectionResult(
      target: .rect(CGRect(x: 0, y: 0, width: 100, height: 100)),
      displayID: 1,
      mode: .screenshot,
      displayIDs: [1, 2]
    )
    XCTAssertTrue(result.spansMultipleDisplays)
    XCTAssertEqual(result.displayIDs.count, 2)
  }

  func testAreaSelectionResult_rectAccessor() {
    let rect = CGRect(x: 5, y: 5, width: 50, height: 50)
    let result = AreaSelectionResult(
      target: .rect(rect),
      displayID: 1,
      mode: .recording
    )
    XCTAssertEqual(result.rect, rect)
  }

  func testWindowCaptureTarget_equatable() {
    let a = WindowCaptureTarget(windowID: 1, frame: .zero, displayID: 1, title: nil, bundleIdentifier: nil, ownerPID: nil)
    let b = WindowCaptureTarget(windowID: 1, frame: .zero, displayID: 1, title: nil, bundleIdentifier: nil, ownerPID: nil)
    let c = WindowCaptureTarget(windowID: 2, frame: .zero, displayID: 1, title: nil, bundleIdentifier: nil, ownerPID: nil)
    XCTAssertEqual(a, b)
    XCTAssertNotEqual(a, c)
  }
}

// MARK: - Added tests for Settings Interaction fixes

final class CaptureViewModelTests: XCTestCase {

  func testHiddenWindowSession_restore_postsSyntheticMouseMovedEvent() throws {
    let policy = AppLaunchPolicy()
    let isCI = ProcessInfo.processInfo.environment["CI"] != nil || ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil
    if isCI || policy.isHeadlessDisplaySession || NSScreen.screens.isEmpty {
      throw XCTSkip("Skipping window restore test in CI or headless display session")
    }

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.orderFront(nil)
    
    let session = ScreenCaptureViewModel.HiddenWindowSession(
      windows: [window],
      keyWindow: nil,
      mainWindow: nil,
      shouldReactivateApp: false
    )
    
    let expectation = XCTestExpectation(description: "Synthetic mouse event posted")
    
    ScreenCaptureViewModel.HiddenWindowSession.onPostSyntheticMouseEvent = { event in
      if event.windowNumber == 0 {
        expectation.fulfill()
      }
    }
    defer {
      ScreenCaptureViewModel.HiddenWindowSession.onPostSyntheticMouseEvent = nil
    }
    
    session.restore()
    
    wait(for: [expectation], timeout: 2.0)
  }
}

final class AreaSelectionControllerTests: XCTestCase {

  func testStartSelectionSession_whenKeyboardOwnerIsNull_registersMonitors() {
    let controller = AreaSelectionController.shared
    
    // Default mode .recording doesn't own keyboard directly in this setup, so it should register the monitor
    controller.startSelection(mode: .recording, backdrops: [:]) { _ in }
    
    let mirror = Mirror(reflecting: controller)
    let localMonitor = mirror.children.first { $0.label == "localEscapeMonitor" }?.value
    
    if let value = localMonitor {
      let isNil = String(describing: value) == "nil"
      XCTAssertFalse(isNil, "localEscapeMonitor should be non-nil when keyboardOwnerDisplayID is nil")
    } else {
      XCTFail("localEscapeMonitor property not found")
    }
    
    controller.cancelSelection()
  }

  // MARK: - isPresenting lifecycle (Escape LIFO dismissal fix)
  //
  // `isPresenting` is the signal `RecordingCoordinator` reads to yield Escape to a topmost
  // capture-area overlay (LIFO). It is set in `startSelectionSession` (mode-independent, before
  // any mode-specific branching) and cleared in `resetCallbacks` — the single teardown funnel
  // shared by BOTH `cancelSelection` and `completeSelection`.

  override func tearDown() {
    // Never leak a presented overlay across tests.
    AreaSelectionController.shared.cancelSelection()
    super.tearDown()
  }

  func testIsPresenting_falseAfterCancel() {
    let controller = AreaSelectionController.shared
    controller.cancelSelection()
    XCTAssertFalse(controller.isPresenting, "isPresenting must be false when no session is active")
  }

  func testIsPresenting_trueWhilePresenting() {
    let controller = AreaSelectionController.shared
    controller.startSelection(mode: .recording, backdrops: [:]) { _ in }
    XCTAssertTrue(controller.isPresenting, "isPresenting must be true once a session is presented")
    controller.cancelSelection()
  }

  func testIsPresenting_falseAfterCancelSelection() {
    let controller = AreaSelectionController.shared
    controller.startSelection(mode: .recording, backdrops: [:]) { _ in }
    controller.cancelSelection()
    XCTAssertFalse(controller.isPresenting, "cancelSelection must clear isPresenting via resetCallbacks")
  }

  func testCancelSelection_restoresDismissesAfterSelectionDefault() {
    let controller = AreaSelectionController.shared
    controller.startSelection(mode: .recording, backdrops: [:]) { _ in }
    controller.setDismissesAfterSelection(false)
    defer { controller.setDismissesAfterSelection(true) }

    controller.cancelSelection()

    XCTAssertTrue(
      controller.dismissesAfterSelection,
      "a cancelled live selection must not leak its dismiss policy into the next capture session"
    )
  }

  func testIsPresenting_falseAfterCompletion() throws {
    // completeSelection funnels through the same resetCallbacks teardown. Drive it with a REAL
    // pooled overlay window (the production success path) so the flag is verified on completion
    // too — no mocks. Environment-gated: skip if the host has no screens to pool a window.
    let controller = AreaSelectionController.shared
    let done = expectation(description: "completion invoked")
    controller.startSelection(mode: .recording, backdrops: [:]) { _ in done.fulfill() }
    XCTAssertTrue(controller.isPresenting)

    guard let window = pooledWindow() else {
      controller.cancelSelection()
      throw XCTSkip("no pooled AreaSelectionWindow (headless host with no screens)")
    }
    controller.completeSelection(rect: CGRect(x: 0, y: 0, width: 10, height: 10), from: window)

    wait(for: [done], timeout: 1.0)
    XCTAssertFalse(controller.isPresenting, "completeSelection must clear isPresenting via resetCallbacks")
  }

  func testIsPresenting_reentrantStartStaysTrue() {
    let controller = AreaSelectionController.shared
    controller.startSelection(mode: .recording, backdrops: [:]) { _ in }
    controller.startSelection(mode: .recording, backdrops: [:]) { _ in }
    XCTAssertTrue(controller.isPresenting, "re-presenting must keep isPresenting true")
    controller.cancelSelection()
    XCTAssertFalse(controller.isPresenting)
  }

  /// Contract test: `RecordingCoordinator` yields Escape by reading exactly this property.
  /// Locks the cross-overlay signal the LIFO fix depends on.
  func testPresentingSignal_isTheContractRecordingCoordinatorReads() {
    let controller = AreaSelectionController.shared
    controller.cancelSelection()
    XCTAssertFalse(controller.isPresenting)  // pre-record would OWN Escape here

    controller.startSelection(mode: .recording, backdrops: [:]) { _ in }
    XCTAssertTrue(controller.isPresenting)   // pre-record must YIELD Escape here

    controller.cancelSelection()
    XCTAssertFalse(controller.isPresenting)  // pre-record OWNS Escape again (2nd Escape)
  }

  /// Escape routing reads `isPresenting` on the hot key-event path — must be trivially cheap.
  /// Requirement: well under 50ms. 100k reads bounds a single read to sub-microsecond.
  func testPresentingSignal_readIsUnder50ms() {
    let controller = AreaSelectionController.shared
    controller.startSelection(mode: .recording, backdrops: [:]) { _ in }
    defer { controller.cancelSelection() }

    let start = DispatchTime.now()
    var sink = false
    for _ in 0..<100_000 { sink = controller.isPresenting || sink }
    let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    XCTAssertTrue(sink)
    XCTAssertLessThan(elapsedMs, 50.0, "100k isPresenting reads took \(elapsedMs)ms; Escape routing must be <50ms")
  }

  /// Resolve a real pooled overlay window (populated lazily by `startSelection`) to drive
  /// `completeSelection` on the success path. Returns nil on a headless host with no screens.
  private func pooledWindow() -> AreaSelectionWindow? {
    let mirror = Mirror(reflecting: AreaSelectionController.shared)
    if let active = mirror.children.first(where: { $0.label == "activeWindow" })?.value as? AreaSelectionWindow {
      return active
    }
    if let pool = mirror.children.first(where: { $0.label == "windowPool" })?.value
      as? [CGDirectDisplayID: AreaSelectionWindow] {
      return pool.values.first
    }
    return nil
  }
}
