//
//  AreaSelectionSessionLifecycleTests.swift
//  SnapzyTests
//
//  Regression tests for the area-selection session lifecycle races:
//  session replacement must tear the previous session down through the cancel
//  path (invoking its completion with nil), completions must be re-entrancy
//  safe, and the dismiss policy must not leak across sessions.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class AreaSelectionSessionLifecycleTests: XCTestCase {

  override func tearDown() {
    // Never leak a presented overlay across tests.
    AreaSelectionController.shared.cancelSelection()
    super.tearDown()
  }

  /// A second `startSelection` while a session is presenting must cancel the first session
  /// through the normal path — invoking its completion exactly once with nil — so the first
  /// caller's state (e.g. `ScreenCaptureViewModel.isAreaSelectionActive`) can reset instead of
  /// stranding every future capture.
  func testReplacement_invokesPreviousCompletionOnceWithNil() throws {
    try skipIfRunningInCI("Presents real overlay windows via the shared AreaSelectionController, which is flaky on headless CI runners")

    let controller = AreaSelectionController.shared
    var firstCalls: [AreaSelectionResult?] = []
    controller.startSelection(mode: .screenshot, backdrops: [:]) { result in
      firstCalls.append(result)
    }
    XCTAssertTrue(controller.isPresenting)

    var secondCalls: [AreaSelectionResult?] = []
    controller.startSelection(mode: .recording, backdrops: [:]) { result in
      secondCalls.append(result)
    }

    XCTAssertEqual(firstCalls.count, 1, "replaced session's completion must fire exactly once")
    if let first = firstCalls.first {
      XCTAssertNil(first, "replaced session's completion must fire with nil (cancelled)")
    }
    XCTAssertTrue(secondCalls.isEmpty, "the new session's completion must not fire during start")
    XCTAssertTrue(controller.isPresenting, "the replacement session must be presenting")
    XCTAssertEqual(controller.selectionMode, .recording)
  }

  /// Live area mode dismisses by calling `cancelSelection()` from inside its own completion.
  /// Callbacks must be snapshotted and cleared before invocation so the re-entrant cancel
  /// cannot fire the same completion a second time (previously produced a spurious extra
  /// `.cancelled` result and a double hidden-window restore).
  func testCompleteSelection_reentrantCancelInsideCompletion_firesOnce() throws {
    try skipIfRunningInCI("Presents real overlay windows via the shared AreaSelectionController, which is flaky on headless CI runners")

    let controller = AreaSelectionController.shared
    var callCount = 0
    controller.startSelection(mode: .screenshot, backdrops: [:], dismissesAfterSelection: false) { result in
      callCount += 1
      if result != nil {
        // Mirrors startLiveAreaSelection: snapshot pixels, then cancel to dismiss the overlay.
        controller.cancelSelection()
      }
    }

    guard let window = pooledWindow() else {
      controller.cancelSelection()
      throw XCTSkip("no pooled AreaSelectionWindow (headless host with no screens)")
    }
    controller.completeSelection(rect: CGRect(x: 0, y: 0, width: 10, height: 10), from: window)

    XCTAssertEqual(callCount, 1, "completion must fire exactly once even when it cancels re-entrantly")
    XCTAssertFalse(controller.isPresenting)
  }

  /// `cancelSelection` must be idempotent with respect to completions: a second cancel must
  /// not re-fire the (already consumed) completion.
  func testCancelSelection_twice_firesCompletionOnce() throws {
    try skipIfRunningInCI("Presents real overlay windows via the shared AreaSelectionController, which is flaky on headless CI runners")

    let controller = AreaSelectionController.shared
    var callCount = 0
    controller.startSelection(mode: .screenshot, backdrops: [:]) { _ in callCount += 1 }

    controller.cancelSelection()
    controller.cancelSelection()

    XCTAssertEqual(callCount, 1, "completion must fire exactly once across duplicate cancels")
    XCTAssertFalse(controller.isPresenting)
  }

  /// The `dismissesAfterSelection` start parameter must be applied for the new session even
  /// though session-start replacement teardown resets the flag to its default.
  func testDismissesAfterSelectionParameter_survivesSessionStart() throws {
    try skipIfRunningInCI("Presents real overlay windows via the shared AreaSelectionController, which is flaky on headless CI runners")

    let controller = AreaSelectionController.shared
    controller.startSelection(mode: .screenshot, backdrops: [:], dismissesAfterSelection: false) { _ in }
    XCTAssertFalse(
      controller.dismissesAfterSelection,
      "a false dismiss policy must be applied after session-start teardown"
    )
    controller.cancelSelection()
    XCTAssertTrue(controller.dismissesAfterSelection, "teardown must restore the default policy")
  }

  /// A live-style session (false dismiss policy) replaced by another session must not leak the
  /// policy: the replacement starts from the default and applies only its own parameter.
  func testReplacement_doesNotLeakDismissPolicy() throws {
    try skipIfRunningInCI("Presents real overlay windows via the shared AreaSelectionController, which is flaky on headless CI runners")

    let controller = AreaSelectionController.shared
    controller.startSelection(mode: .screenshot, backdrops: [:], dismissesAfterSelection: false) { _ in }
    controller.startSelection(mode: .recording, backdrops: [:]) { _ in }
    XCTAssertTrue(
      controller.dismissesAfterSelection,
      "a replaced live session must not leak its dismiss policy into the next session"
    )
    controller.cancelSelection()
  }

  /// Contract for the `RecordingCoordinator` app-toggle LIFO gate: it reads `selectionMode`
  /// to decide whether a presenting session is recording-owned.
  func testSelectionMode_reflectsCurrentSession() throws {
    try skipIfRunningInCI("Presents real overlay windows via the shared AreaSelectionController, which is flaky on headless CI runners")

    let controller = AreaSelectionController.shared
    controller.startSelection(mode: .recording, backdrops: [:]) { _ in }
    XCTAssertEqual(controller.selectionMode, .recording)
    controller.startSelection(mode: .screenshot, backdrops: [:]) { _ in }
    XCTAssertEqual(controller.selectionMode, .screenshot)
    controller.cancelSelection()
  }

  /// Mid-session screen-parameter changes must not hide the session's windows (a hidden panel
  /// is a click fall-through hole on its display). Drives `refreshWindowPool` through the real
  /// notification; environment-gated on hosts with screens.
  func testScreenParameterChange_midSession_keepsWindowsVisible() throws {
    try skipIfRunningInCI("Presents real overlay windows via the shared AreaSelectionController, which is flaky on headless CI runners")

    let controller = AreaSelectionController.shared
    controller.startSelection(mode: .screenshot, backdrops: [:]) { _ in }

    guard !pooledWindows().isEmpty else {
      controller.cancelSelection()
      throw XCTSkip("no pooled AreaSelectionWindow (headless host with no screens)")
    }

    NotificationCenter.default.post(
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )

    for window in pooledWindows() {
      XCTAssertTrue(window.isVisible, "pooled overlay must stay visible across screen-parameter changes")
    }
    controller.cancelSelection()
  }

  // MARK: - Helpers

  /// Resolve a real pooled overlay window (populated lazily by `startSelection`) to drive
  /// `completeSelection` on the success path. Empty on a headless host with no screens.
  private func pooledWindows() -> [AreaSelectionWindow] {
    let mirror = Mirror(reflecting: AreaSelectionController.shared)
    if let pool = mirror.children.first(where: { $0.label == "windowPool" })?.value
      as? [CGDirectDisplayID: AreaSelectionWindow] {
      return Array(pool.values)
    }
    return []
  }

  private func pooledWindow() -> AreaSelectionWindow? {
    pooledWindows().first
  }
}
