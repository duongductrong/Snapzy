//
//  ScrollingCaptureWindowSharingTests.swift
//  SnapzyTests
//
//  Unit tests for scrolling capture session chrome capture exclusion.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class ScrollingCaptureWindowSharingTests: XCTestCase {

  func testPreviewWindow_isExcludedFromScreenCapture() {
    let model = ScrollingCaptureSessionModel(selectedRect: sampleAnchorRect)
    let window = ScrollingCapturePreviewWindow(anchorRect: sampleAnchorRect, model: model)
    defer { window.close() }

    XCTAssertEqual(window.sharingType, NSWindow.SharingType.none)
  }

  func testHUDWindow_isExcludedFromScreenCapture() {
    let model = ScrollingCaptureSessionModel(selectedRect: sampleAnchorRect)
    let window = ScrollingCaptureHUDWindow(
      anchorRect: sampleAnchorRect,
      model: model,
      onStart: {},
      onDone: {},
      onCancel: {},
      onToggleAutoScroll: {}
    )
    defer { window.close() }

    XCTAssertEqual(window.sharingType, NSWindow.SharingType.none)
  }

  func testAreaSelectionWindow_isExcludedFromScreenCapture() throws {
    let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
    let window = AreaSelectionWindow(screen: screen, pooled: true)
    defer { window.close() }

    XCTAssertEqual(window.sharingType, NSWindow.SharingType.none)
  }

  private var sampleAnchorRect: CGRect {
    CGRect(x: 120, y: 120, width: 360, height: 480)
  }
}

final class ScrollingCaptureAutoScrollPolicyTests: XCTestCase {

  func testCanToggleAutoScrollOnlyAfterFirstFrameLocks() {
    assertCanToggleAutoScroll(
      phase: .ready,
      acceptedFrameCount: 0,
      isAutoScrolling: false,
      expected: false
    )
    assertCanToggleAutoScroll(
      phase: .capturing,
      acceptedFrameCount: 0,
      isAutoScrolling: false,
      expected: false
    )
    assertCanToggleAutoScroll(
      phase: .capturing,
      acceptedFrameCount: 1,
      isAutoScrolling: false,
      expected: true
    )
    assertCanToggleAutoScroll(
      phase: .capturing,
      acceptedFrameCount: 0,
      isAutoScrolling: true,
      expected: true
    )
    assertCanToggleAutoScroll(
      phase: .finalizing,
      acceptedFrameCount: 1,
      isAutoScrolling: true,
      expected: false
    )
    assertCanToggleAutoScroll(
      phase: .saving,
      acceptedFrameCount: 1,
      isAutoScrolling: true,
      expected: false
    )
  }

  func testPlaceMouseInsideSelectionGuidance_usesWarningTone() {
    let guidance = ScrollingCaptureSelectionGuidanceKind.placeMouseInsideSelection.guidance

    XCTAssertFalse(guidance.title.isEmpty)
    XCTAssertFalse(guidance.detail?.isEmpty ?? true)
    if case .warning = guidance.tone {
      return
    }
    XCTFail("Expected warning guidance tone")
  }

  func testHUDWindowContentSize_usesMinimumForCompactContent() {
    XCTAssertEqual(
      ScrollingCaptureHUDWindow.resolvedContentSize(for: CGSize(width: 240.1, height: 32.4)),
      CGSize(width: 380, height: 44)
    )
  }

  func testHUDWindowContentSize_expandsToFitAutoScrollControls() {
    XCTAssertEqual(
      ScrollingCaptureHUDWindow.resolvedContentSize(for: CGSize(width: 431.2, height: 45.1)),
      CGSize(width: 432, height: 46)
    )
  }

  func testAutoScrollPolicy_usesCurrentPointerAsScrollTarget() {
    let mouseLocation = CGPoint(x: 180, y: 220)

    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.scrollTargetPoint(
        mouseLocation: mouseLocation,
        selectedRect: sampleAnchorRect
      ),
      mouseLocation
    )
  }

  func testAutoScrollPolicy_clampsHoverPaddingInsideCapturedPane() {
    let mouseLocation = CGPoint(x: sampleAnchorRect.minX - 10, y: sampleAnchorRect.midY)

    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.scrollTargetPoint(
        mouseLocation: mouseLocation,
        selectedRect: sampleAnchorRect
      ),
      CGPoint(x: sampleAnchorRect.minX + 1, y: sampleAnchorRect.midY)
    )
  }

  func testAutoScrollPolicy_rejectsPointerOutsideHoverPadding() {
    let mouseLocation = CGPoint(x: sampleAnchorRect.minX - 40, y: sampleAnchorRect.midY)

    XCTAssertNil(
      ScrollingCaptureAutoScrollPolicy.scrollTargetPoint(
        mouseLocation: mouseLocation,
        selectedRect: sampleAnchorRect
      )
    )
  }

  func testAutoScrollPolicy_finishesOnHeightLimit() {
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.stitchAction(
        for: stitchUpdate(outcome: .reachedHeightLimit)
      ),
      .finishCapture
    )
  }

  func testAutoScrollPolicy_retriesBeforeTreatingNoMovementAsEnd() {
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.stitchAction(
        for: stitchUpdate(outcome: .ignoredNoMovement, likelyReachedBoundary: true),
        consecutiveNoMovementCount: 1
      ),
      .retryStep
    )
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.stitchAction(
        for: stitchUpdate(outcome: .ignoredNoMovement, likelyReachedBoundary: true),
        consecutiveNoMovementCount: ScrollingCaptureAutoScrollPolicy.noMovementFinishThreshold
      ),
      .finishCapture
    )
  }

  func testAutoScrollPolicy_stopsAfterRepeatedAlignmentFailures() {
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.stitchAction(
        for: stitchUpdate(outcome: .ignoredAlignmentFailed, matchFailureCount: 2)
      ),
      .retryCommit
    )
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.stitchAction(
        for: stitchUpdate(outcome: .ignoredAlignmentFailed, matchFailureCount: 3)
      ),
      .stopScrolling
    )
  }

  func testAutoScrollPolicy_stepDistanceStaysInsideOverlapSafeBounds() {
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.stepDistancePoints(regionHeight: 800),
      192,
      accuracy: 0.001
    )
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.stepDistancePoints(regionHeight: 100),
      26,
      accuracy: 0.001
    )
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.stepDistancePoints(regionHeight: 200),
      48,
      accuracy: 0.001
    )
  }

  func testAutoScrollPolicy_tickCountMatchesWheelDelta() {
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.tickCount(forStepDistancePoints: 36),
      4
    )
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.tickCount(forStepDistancePoints: 90),
      11
    )
  }

  func testAutoScrollPolicy_undersizedAppendTriggersSmallerFollowUpStep() {
    XCTAssertTrue(
      ScrollingCaptureAutoScrollPolicy.shouldTakeSmallerFollowUpStep(
        acceptedDeltaPixels: 24,
        expectedSignedDeltaPixels: -120
      )
    )
    XCTAssertFalse(
      ScrollingCaptureAutoScrollPolicy.shouldTakeSmallerFollowUpStep(
        acceptedDeltaPixels: 80,
        expectedSignedDeltaPixels: -120
      )
    )
  }

  func testAutoScrollPolicy_retryStepPlanUsesSmallerBurstAndLongerSettle() {
    let normal = ScrollingCaptureAutoScrollPolicy.stepPlan(regionHeight: 800, isRetry: false)
    let retry = ScrollingCaptureAutoScrollPolicy.stepPlan(regionHeight: 800, isRetry: true)

    XCTAssertGreaterThan(normal.tickCount, retry.tickCount)
    XCTAssertEqual(normal.settleNanoseconds, ScrollingCaptureAutoScrollPolicy.settleNanoseconds)
    XCTAssertEqual(retry.settleNanoseconds, ScrollingCaptureAutoScrollPolicy.retrySettleNanoseconds)
    XCTAssertEqual(
      normal.postedDistancePoints,
      CGFloat(normal.tickCount) * CGFloat(abs(ScrollingCaptureAutoScrollPolicy.wheelDeltaY))
    )
  }

  func testAutoScrollPolicy_makesUsefulProgressWithoutLongBurstsOrLostOverlap() {
    for height: CGFloat in [120, 240, 600, 800, 1000, 2000] {
      let plan = ScrollingCaptureAutoScrollPolicy.stepPlan(regionHeight: height, isRetry: false)
      let duration = Double(plan.tickCount) * Double(plan.tickIntervalNanoseconds) / 1_000_000_000

      XCTAssertGreaterThan(plan.postedDistancePoints, 0)
      XCTAssertLessThanOrEqual(plan.postedDistancePoints, height * 0.26)
      XCTAssertLessThanOrEqual(duration, 0.5, "Input must stay responsive to Stop and pointer exit")
      XCTAssertGreaterThanOrEqual(Double(plan.postedDistancePoints) / duration, 400)
    }

    let tallSelection = ScrollingCaptureAutoScrollPolicy.stepPlan(regionHeight: 1000, isRetry: false)
    XCTAssertGreaterThanOrEqual(
      tallSelection.postedDistancePoints, 200,
      "Tall selections should not stitch after every tiny scroll"
    )
  }

  func testAutoScrollPolicy_expectedDeltaPrefersObservedScroll() {
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.expectedSignedDeltaPixels(
        postedDistancePoints: 120,
        observedDistancePoints: -80,
        scaleFactor: 2
      ),
      -160
    )
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.expectedSignedDeltaPixels(
        postedDistancePoints: 120,
        observedDistancePoints: 0,
        scaleFactor: 2
      ),
      -240
    )
  }

  func testAutoScrollPolicy_missingStitchUpdateRetriesThenStopsWithoutSaving() {
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.actionForMissingStitchUpdate(consecutiveFailureCount: 1),
      .retryCommit
    )
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.actionForMissingStitchUpdate(
        consecutiveFailureCount: ScrollingCaptureAutoScrollPolicy.alignmentFailureStopThreshold
      ),
      .stopScrolling
    )
  }

  func testAutoScrollPolicy_rejectsFrameCapturedBeforeLastSyntheticEvent() {
    XCTAssertFalse(
      ScrollingCaptureAutoScrollPolicy.isCommitFrameEligible(
        capturedAt: 10.0,
        lastSyntheticEventAt: 10.5
      )
    )
    XCTAssertTrue(
      ScrollingCaptureAutoScrollPolicy.isCommitFrameEligible(
        capturedAt: 10.6,
        lastSyntheticEventAt: 10.5
      )
    )
  }

  private var sampleAnchorRect: CGRect {
    CGRect(x: 120, y: 120, width: 360, height: 480)
  }

  private func assertCanToggleAutoScroll(
    phase: ScrollingCapturePhase,
    acceptedFrameCount: Int,
    isAutoScrolling: Bool,
    expected: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(
      ScrollingCaptureAutoScrollPolicy.canToggle(
        phase: phase,
        acceptedFrameCount: acceptedFrameCount,
        isAutoScrolling: isAutoScrolling
      ),
      expected,
      "phase=\(phase), acceptedFrameCount=\(acceptedFrameCount), isAutoScrolling=\(isAutoScrolling)",
      file: file,
      line: line
    )
  }

  private func stitchUpdate(
    outcome: ScrollingCaptureStitchOutcome,
    matchFailureCount: Int = 0,
    likelyReachedBoundary: Bool = false
  ) -> ScrollingCaptureStitchUpdate {
    ScrollingCaptureStitchUpdate(
      outcome: outcome,
      mergedImage: nil,
      acceptedFrameCount: 1,
      outputHeight: 480,
      matchFailureCount: matchFailureCount,
      mergeDirection: .appendFromBottom,
      likelyReachedBoundary: likelyReachedBoundary,
      safety: .confirmed,
      alignmentDebug: nil
    )
  }
}
