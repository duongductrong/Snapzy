//
//  AreaSelectionPresentationLogicTests.swift
//  SnapzyTests
//
//  Unit tests for the area-selection presentation watchdog's pure evaluator.
//  The watchdog exists because `isVisible` alone cannot detect a window that
//  composites nothing (off-screen frame, wrong space, occlusion, dragged
//  alpha) — the live-passthrough failure mode where selection keeps working
//  but no crosshair/selection visuals ever paint.
//

import CoreGraphics
@testable import Snapzy
import XCTest

final class AreaSelectionPresentationLogicTests: XCTestCase {
  private let frame = CGRect(x: 0, y: 0, width: 1800, height: 1169)

  private func cleanState() -> AreaSelectionPresentationState {
    AreaSelectionPresentationState(
      isVisible: true,
      isOnActiveSpace: true,
      occlusionVisible: true,
      alphaValue: 1,
      windowFrame: frame,
      screenFrame: frame,
      onScreenPerWindowServer: true
    )
  }

  func testCleanState_reportsNoIssues() {
    XCTAssertTrue(AreaSelectionPresentationLogic.issues(for: cleanState()).isEmpty)
  }

  func testInvisibleWindow_flagged() {
    var state = cleanState()
    state.isVisible = false
    XCTAssertEqual(AreaSelectionPresentationLogic.issues(for: state), [.notVisible])
  }

  func testOffActiveSpace_flagged() {
    var state = cleanState()
    state.isOnActiveSpace = false
    XCTAssertEqual(AreaSelectionPresentationLogic.issues(for: state), [.offActiveSpace])
  }

  func testFrameMismatch_sameSizeDifferentOrigin_flagged() {
    var state = cleanState()
    state.windowFrame = CGRect(x: 1800, y: 0, width: frame.width, height: frame.height)
    XCTAssertEqual(AreaSelectionPresentationLogic.issues(for: state), [.frameMismatch])
  }

  func testFrameMismatch_differentSize_flagged() {
    var state = cleanState()
    state.screenFrame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    XCTAssertEqual(AreaSelectionPresentationLogic.issues(for: state), [.frameMismatch])
  }

  func testNonOpaqueAlpha_flagged() {
    var state = cleanState()
    state.alphaValue = 0
    XCTAssertEqual(AreaSelectionPresentationLogic.issues(for: state), [.unexpectedAlpha])
  }

  func testOccludedWindow_flagged() {
    var state = cleanState()
    state.occlusionVisible = false
    XCTAssertEqual(AreaSelectionPresentationLogic.issues(for: state), [.occluded])
  }

  /// The ground-truth check: the WindowServer's on-screen list does not include the window
  /// even though every AppKit-side property is healthy (the `.canJoinAllSpaces` membership
  /// failure where the overlay shows on one desktop Space but not another).
  func testWindowServerOffScreen_flagged() {
    var state = cleanState()
    state.onScreenPerWindowServer = false
    XCTAssertEqual(AreaSelectionPresentationLogic.issues(for: state), [.notOnScreenPerWindowServer])
  }

  /// A failed WindowServer query (nil = unknown) must never be treated as an anomaly —
  /// otherwise a transient CGWindowList failure would trigger heals on healthy windows.
  func testWindowServerUnknown_notFlagged() {
    var state = cleanState()
    state.onScreenPerWindowServer = nil
    XCTAssertTrue(AreaSelectionPresentationLogic.issues(for: state).isEmpty)
  }

  /// The field failure this watchdog targets: `isVisible == true` while the window paints
  /// nothing. Each non-visible presentation defect must surface even when `isVisible` holds.
  func testInvisibleButFunctionalStates_flaggedDespiteIsVisible() {
    for mutate in [
      { (s: inout AreaSelectionPresentationState) in s.windowFrame.origin.x += 5000 },
      { (s: inout AreaSelectionPresentationState) in s.occlusionVisible = false },
      { (s: inout AreaSelectionPresentationState) in s.isOnActiveSpace = false },
      { (s: inout AreaSelectionPresentationState) in s.onScreenPerWindowServer = false },
    ] {
      var state = cleanState()
      mutate(&state)
      XCTAssertTrue(state.isVisible)
      XCTAssertFalse(
        AreaSelectionPresentationLogic.issues(for: state).isEmpty,
        "a compositing defect must be detected even when isVisible == true"
      )
    }
  }

  func testCombinedIssues_allReported() {
    var state = cleanState()
    state.isVisible = false
    state.isOnActiveSpace = false
    state.alphaValue = 0.5
    state.occlusionVisible = false
    state.windowFrame.origin.y = 999
    state.onScreenPerWindowServer = false
    XCTAssertEqual(
      Set(AreaSelectionPresentationLogic.issues(for: state)),
      Set(AreaSelectionPresentationIssue.allCases)
    )
  }

  // MARK: - Heal escalation ladder

  private func healAction(
    issues: [AreaSelectionPresentationIssue],
    ticks: Int = 1,
    recreations: Int = 0,
    maxRecreations: Int = 2,
    lastResortUsed: Bool = false
  ) -> AreaSelectionPresentationHealAction? {
    AreaSelectionPresentationLogic.healAction(
      for: issues,
      consecutiveAnomalyTicks: ticks,
      recreationCount: recreations,
      maxRecreations: maxRecreations,
      lastResortUsed: lastResortUsed
    )
  }

  func testHealAction_noIssues_returnsNil() {
    XCTAssertNil(healAction(issues: []))
  }

  /// Transient anomalies (space-switch turbulence) get one cheap re-assert first.
  func testHealAction_transientOnlyFirstTick_reasserts() {
    XCTAssertEqual(healAction(issues: [.occluded], ticks: 1), .reassert)
    XCTAssertEqual(healAction(issues: [.notVisible], ticks: 1), .reassert)
    XCTAssertEqual(healAction(issues: [.frameMismatch], ticks: 1), .reassert)
    XCTAssertEqual(healAction(issues: [.unexpectedAlpha], ticks: 1), .reassert)
  }

  /// A transient anomaly that survives the first re-assert escalates to recreation.
  func testHealAction_persistentTransient_escalatesToRecreate() {
    XCTAssertEqual(healAction(issues: [.occluded], ticks: 2), .recreateWindow)
  }

  /// Membership loss escalates to recreation immediately — the re-assert provably cannot
  /// repair it, so waiting a tick only delays the crosshair.
  func testHealAction_membershipLoss_recreatesImmediately() {
    XCTAssertEqual(healAction(issues: [.offActiveSpace], ticks: 1), .recreateWindow)
    XCTAssertEqual(healAction(issues: [.notOnScreenPerWindowServer], ticks: 1), .recreateWindow)
    XCTAssertEqual(
      healAction(issues: [.offActiveSpace, .occluded, .notOnScreenPerWindowServer], ticks: 1),
      .recreateWindow
    )
  }

  /// Past the recreation cap, the single activate-and-recreate last resort fires once.
  func testHealAction_recreationCapExhausted_activateAndRecreateOnce() {
    XCTAssertEqual(
      healAction(issues: [.offActiveSpace], ticks: 1, recreations: 2),
      .activateAndRecreate
    )
    XCTAssertEqual(
      healAction(issues: [.offActiveSpace], ticks: 1, recreations: 2, lastResortUsed: true),
      .reassert
    )
  }

  /// Under the cap, membership loss keeps recreating.
  func testHealAction_underCap_keepsRecreating() {
    XCTAssertEqual(
      healAction(issues: [.notOnScreenPerWindowServer], ticks: 3, recreations: 1),
      .recreateWindow
    )
  }
}
