//
//  QuickAccessPanelControllerTests.swift
//  SnapzyTests
//
//  Regression tests for the panel show/hide transition wedge:
//  a show() landing during the exit animation (or any dropped NSAnimationContext
//  completion) previously left captures with no visible Quick Access panel until
//  the stack fully drained or the app restarted.
//

import SwiftUI
import XCTest
@testable import Snapzy

@MainActor
final class QuickAccessPanelControllerTests: XCTestCase {
  private var controller: QuickAccessPanelController?

  override func setUp() async throws {
    try await super.setUp()
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      throw XCTSkip("Slide-transition paths are disabled under Reduce Motion")
    }
    guard !NSScreen.screens.isEmpty else {
      throw XCTSkip("No screen available in this environment")
    }
    controller = QuickAccessPanelController()
  }

  override func tearDown() async throws {
    controller?.hide()
    controller = nil
    try await super.tearDown()
  }

  private static let panelSize = CGSize(width: 200, height: 400)

  /// Content is pinned to the panel size on purpose: an intrinsically-smaller
  /// hosting view lets AppKit shrink the window around the top-left corner,
  /// which would move the origin under test. Real cards are fixed-size.
  private func showPanel() {
    controller?.show(
      Text("card").frame(width: Self.panelSize.width, height: Self.panelSize.height),
      size: Self.panelSize,
      itemCount: 1,
      scale: 1
    )
  }

  /// The previous stack's 0.25s exit animation must never swallow the show()
  /// of a newly captured card that lands mid-exit.
  func testShowDuringExitTransitionStillEndsWithVisiblePanel() async throws {
    showPanel()
    XCTAssertNotNil(controller?.window)
    try await Task.sleep(nanoseconds: 600_000_000)  // let the enter finish

    controller?.hide()
    // Exit animation is in flight; the next capture's panel request lands now.
    showPanel()

    // Wait past exit (0.25s) + enter (0.4s) + watchdog slack.
    try await Task.sleep(nanoseconds: 1_500_000_000)
    XCTAssertNotNil(controller?.window, "Panel must exist after show-during-exit")
    XCTAssertTrue(controller?.window?.isVisible ?? false)
  }

  /// Removing the last card while the enter animation is still running must
  /// close the panel instead of leaving a stuck empty window on screen.
  func testHideDuringEnterTransitionClosesPanel() async throws {
    showPanel()
    controller?.hide()

    try await Task.sleep(nanoseconds: 1_000_000_000)
    XCTAssertNil(controller?.window, "Hide during enter must close the panel")
  }

  /// Back-to-back hides (e.g. removeItem then dismissAll) must not wedge the
  /// transition state or resurrect the panel.
  func testDoubleHideKeepsPanelClosed() async throws {
    showPanel()
    try await Task.sleep(nanoseconds: 600_000_000)  // let the enter finish

    controller?.hide()
    controller?.hide()

    try await Task.sleep(nanoseconds: 1_000_000_000)
    XCTAssertNil(controller?.window)
  }

  /// A full cycle followed by a fresh capture must show the panel again —
  /// the steady-state path after all transitions have settled.
  func testShowAfterCompletedCycleShowsPanelAgain() async throws {
    showPanel()
    try await Task.sleep(nanoseconds: 600_000_000)
    controller?.hide()
    try await Task.sleep(nanoseconds: 900_000_000)
    XCTAssertNil(controller?.window)

    showPanel()
    XCTAssertNotNil(controller?.window)
    XCTAssertTrue(controller?.window?.isVisible ?? false)
  }

  // MARK: - Multi-display anchoring (#467)

  /// A capture on the display the panel already lives on must not restart the
  /// entrance animation — re-anchoring is only for cross-display captures.
  func testMoveToActiveScreenIsNoOpOnSameDisplay() async throws {
    showPanel()
    try await Task.sleep(nanoseconds: 600_000_000)  // let the enter finish
    let settledFrame = try XCTUnwrap(controller?.window?.frame)

    controller?.moveToActiveScreenIfNeeded()

    XCTAssertEqual(controller?.window?.frame, settledFrame, "Same-display capture must not move the panel")
    XCTAssertFalse(controller?.isDismissing ?? true)
  }

  /// Re-anchoring must land the panel in the target display's corner, matching
  /// the origin the position model computes for that screen.
  func testMoveToActiveScreenLandsInCornerOfAnchoredScreen() async throws {
    let size = Self.panelSize
    showPanel()
    try await Task.sleep(nanoseconds: 600_000_000)

    controller?.moveToActiveScreenIfNeeded()
    try await Task.sleep(nanoseconds: 900_000_000)  // enter (0.4s) + watchdog slack

    // Assert against the anchored screen, not the live cursor screen: on a
    // multi-display Mac the cursor can resolve elsewhere by assert time.
    let screen = try XCTUnwrap(controller?.anchoredScreen)
    let expected = QuickAccessPosition.bottomRight.calculateOrigin(for: size, on: screen)
    let origin = try XCTUnwrap(controller?.window?.frame.origin)
    XCTAssertEqual(origin.x, expected.x, accuracy: 1)
    XCTAssertEqual(origin.y, expected.y, accuracy: 1)
  }

  /// A panel mid slide-out is being torn down; re-anchoring it would drag a
  /// dying window onto the new display instead of the caller showing a fresh one.
  func testMoveToActiveScreenIgnoredWhileDismissing() async throws {
    showPanel()
    try await Task.sleep(nanoseconds: 600_000_000)

    controller?.hide()
    XCTAssertTrue(controller?.isDismissing ?? false, "hide() must mark the panel as dismissing")
    controller?.moveToActiveScreenIfNeeded()

    try await Task.sleep(nanoseconds: 900_000_000)
    XCTAssertNil(controller?.window, "Dismissal must still complete after a move request")
  }
}

@MainActor
final class QuickAccessScreenAnchorTests: XCTestCase {

  func testAnchorReportsChangeOnlyOnNewDisplay() throws {
    let screen = try XCTUnwrap(NSScreen.screens.first)
    var anchor = QuickAccessScreenAnchor()

    XCTAssertNil(anchor.displayID)
    XCTAssertTrue(anchor.anchor(to: screen), "First anchor is always a change")
    XCTAssertEqual(anchor.displayID, ScreenUtility.displayID(of: screen))
    XCTAssertFalse(anchor.anchor(to: screen), "Re-anchoring to the same display is a no-op")
  }

  /// Positioning resolves against the anchored display, not the cursor — moving
  /// the mouse to another screen must never teleport a visible panel.
  func testScreenResolvesToAnchoredDisplay() throws {
    let screen = try XCTUnwrap(NSScreen.screens.first)
    var anchor = QuickAccessScreenAnchor()
    anchor.anchor(to: screen)

    XCTAssertEqual(ScreenUtility.displayID(of: anchor.screen), ScreenUtility.displayID(of: screen))
  }

  /// An unset anchor (and, by the same path, a disconnected display) falls back
  /// to the active screen rather than trapping the panel on a missing monitor.
  func testUnanchoredFallsBackToActiveScreen() {
    let anchor = QuickAccessScreenAnchor()

    XCTAssertEqual(
      ScreenUtility.displayID(of: anchor.screen),
      ScreenUtility.activeDisplayID()
    )
  }
}
