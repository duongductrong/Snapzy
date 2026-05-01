//
//  ScrollingCaptureMetricsTests.swift
//  SnapzyTests
//
//  Unit tests for ScrollingCaptureSessionMetrics value-type accumulator.
//

import XCTest
@testable import Snapzy

final class ScrollingCaptureMetricsTests: XCTestCase {

  // MARK: - Initial State

  func testFreshMetrics_hadActivity_isFalse() {
    let metrics = ScrollingCaptureSessionMetrics()
    XCTAssertFalse(metrics.hadActivity)
  }

  func testFreshMetrics_allCountersZero() {
    let metrics = ScrollingCaptureSessionMetrics()
    XCTAssertEqual(metrics.scrollEventCount, 0)
    XCTAssertEqual(metrics.totalScrollDistancePoints, 0)
    XCTAssertEqual(metrics.refreshAttemptCount, 0)
    XCTAssertEqual(metrics.refreshSuccessCount, 0)
    XCTAssertEqual(metrics.refreshFailureCount, 0)
    XCTAssertEqual(metrics.appendedCount, 0)
    XCTAssertEqual(metrics.initializedCount, 0)
    XCTAssertEqual(metrics.ignoredNoMovementCount, 0)
    XCTAssertEqual(metrics.ignoredAlignmentFailedCount, 0)
    XCTAssertEqual(metrics.reachedHeightLimitCount, 0)
    XCTAssertEqual(metrics.livePreviewFrameCount, 0)
    XCTAssertEqual(metrics.finalizingStartCount, 0)
  }

  // MARK: - Scroll Events

  func testRecordScrollEvent_incrementsCountAndDistance() {
    var metrics = ScrollingCaptureSessionMetrics()
    metrics.recordScrollEvent(deltaY: 10.5)
    metrics.recordScrollEvent(deltaY: 20.0)

    XCTAssertEqual(metrics.scrollEventCount, 2)
    XCTAssertEqual(metrics.totalScrollDistancePoints, 30.5, accuracy: 0.001)
    XCTAssertTrue(metrics.hadActivity)
  }

  // MARK: - Refresh Success with Outcomes

  func testRecordRefreshSuccess_initializedOutcome() {
    var metrics = ScrollingCaptureSessionMetrics()
    metrics.recordRefreshSuccess(
      reason: "scroll",
      captureDurationMs: 10,
      stitchDurationMs: 5,
      previewPublishDurationMs: 3,
      totalDurationMs: 18,
      outcome: .initialized,
      alignmentDebug: nil
    )

    XCTAssertEqual(metrics.refreshAttemptCount, 1)
    XCTAssertEqual(metrics.refreshSuccessCount, 1)
    XCTAssertEqual(metrics.initializedCount, 1)
    XCTAssertEqual(metrics.refreshCaptureDurationTotalMs, 10)
    XCTAssertEqual(metrics.refreshStitchDurationTotalMs, 5)
    XCTAssertEqual(metrics.refreshDurationTotalMs, 18)
  }

  func testRecordRefreshSuccess_appendedOutcome_tracksDelta() {
    var metrics = ScrollingCaptureSessionMetrics()
    let debug = ScrollingCaptureAlignmentDebugInfo(
      path: .fastGuided,
      usedVisionEstimate: false,
      confidence: 0.95,
      pixelScore: 2.1,
      totalScore: 3.0,
      appendDeltaY: 42,
      visionAgreementCount: 0
    )
    metrics.recordRefreshSuccess(
      reason: "scroll",
      captureDurationMs: 10,
      stitchDurationMs: 5,
      previewPublishDurationMs: 3,
      totalDurationMs: 18,
      outcome: .appended(deltaY: 42),
      alignmentDebug: debug
    )

    XCTAssertEqual(metrics.appendedCount, 1)
    XCTAssertEqual(metrics.appendedDeltaTotalPixels, 42)
    XCTAssertEqual(metrics.appendedDeltaMaxPixels, 42)
    XCTAssertEqual(metrics.fastGuidedMatchCount, 1)
    XCTAssertEqual(metrics.matcherConfidenceCount, 1)
    XCTAssertEqual(metrics.matcherConfidenceTotal, 0.95, accuracy: 0.001)
  }

  func testRecordRefreshSuccess_ignoredAlignmentFailed_tracksStreak() {
    var metrics = ScrollingCaptureSessionMetrics()

    // 3 consecutive alignment failures
    for _ in 0..<3 {
      metrics.recordRefreshSuccess(
        reason: "scroll",
        captureDurationMs: 10,
        stitchDurationMs: 5,
        previewPublishDurationMs: 0,
        totalDurationMs: 15,
        outcome: .ignoredAlignmentFailed,
        alignmentDebug: nil
      )
    }

    XCTAssertEqual(metrics.ignoredAlignmentFailedCount, 3)
    XCTAssertEqual(metrics.alignmentFailureStreakMax, 3)

    // Success resets the streak
    metrics.recordRefreshSuccess(
      reason: "scroll",
      captureDurationMs: 10,
      stitchDurationMs: 5,
      previewPublishDurationMs: 3,
      totalDurationMs: 18,
      outcome: .appended(deltaY: 10),
      alignmentDebug: nil
    )

    // Max streak still 3 even after reset
    XCTAssertEqual(metrics.alignmentFailureStreakMax, 3)
    XCTAssertEqual(metrics.appendedCount, 1)

    // One more failure: streak is now 1, max stays 3
    metrics.recordRefreshSuccess(
      reason: "scroll",
      captureDurationMs: 10,
      stitchDurationMs: 5,
      previewPublishDurationMs: 0,
      totalDurationMs: 15,
      outcome: .ignoredAlignmentFailed,
      alignmentDebug: nil
    )

    XCTAssertEqual(metrics.alignmentFailureStreakMax, 3)
  }

  func testRecordRefreshSuccess_heightLimitOutcome() {
    var metrics = ScrollingCaptureSessionMetrics()
    metrics.recordRefreshSuccess(
      reason: "scroll",
      captureDurationMs: 10,
      stitchDurationMs: 5,
      previewPublishDurationMs: 3,
      totalDurationMs: 18,
      outcome: .reachedHeightLimit,
      alignmentDebug: nil
    )

    XCTAssertEqual(metrics.reachedHeightLimitCount, 1)
  }

  func testRecordRefreshSuccess_visionEstimateTracking() {
    var metrics = ScrollingCaptureSessionMetrics()
    let debug = ScrollingCaptureAlignmentDebugInfo(
      path: .guidedVision,
      usedVisionEstimate: true,
      confidence: 0.9,
      pixelScore: nil,
      totalScore: nil,
      appendDeltaY: 30,
      visionAgreementCount: 5
    )
    metrics.recordRefreshSuccess(
      reason: "scroll",
      captureDurationMs: 10,
      stitchDurationMs: 5,
      previewPublishDurationMs: 3,
      totalDurationMs: 18,
      outcome: .appended(deltaY: 30),
      alignmentDebug: debug
    )

    XCTAssertEqual(metrics.visionEstimateCount, 1)
    XCTAssertEqual(metrics.guidedVisionMatchCount, 1)
  }

  func testRecordRefreshSuccess_duplicateBoundaryTracking() {
    var metrics = ScrollingCaptureSessionMetrics()
    let debug = ScrollingCaptureAlignmentDebugInfo(
      path: .duplicateBoundary,
      usedVisionEstimate: false,
      confidence: 1.0,
      pixelScore: nil,
      totalScore: nil,
      appendDeltaY: nil,
      visionAgreementCount: 0
    )
    metrics.recordRefreshSuccess(
      reason: "scroll",
      captureDurationMs: 10,
      stitchDurationMs: 5,
      previewPublishDurationMs: 0,
      totalDurationMs: 15,
      outcome: .ignoredNoMovement,
      alignmentDebug: debug
    )

    XCTAssertEqual(metrics.likelyBoundaryNoMovementCount, 1)
    XCTAssertEqual(metrics.ignoredNoMovementCount, 1)
  }

  // MARK: - Refresh Failure

  func testRecordRefreshFailure_incrementsFailureCount() {
    var metrics = ScrollingCaptureSessionMetrics()
    metrics.recordRefreshFailure(
      reason: "capture-error",
      captureDurationMs: 10,
      stitchDurationMs: 0,
      totalDurationMs: 10
    )

    XCTAssertEqual(metrics.refreshAttemptCount, 1)
    XCTAssertEqual(metrics.refreshFailureCount, 1)
    XCTAssertEqual(metrics.refreshSuccessCount, 0)
  }

  // MARK: - Live Preview

  func testRecordLivePreviewStart() {
    var metrics = ScrollingCaptureSessionMetrics()
    metrics.recordLivePreviewStart(success: true)
    metrics.recordLivePreviewStart(success: false)

    XCTAssertEqual(metrics.livePreviewStartAttempts, 2)
    XCTAssertEqual(metrics.livePreviewStartFailures, 1)
    XCTAssertTrue(metrics.hadActivity)
  }

  func testRecordLivePreviewFramePublished_gapTracking() {
    var metrics = ScrollingCaptureSessionMetrics()

    // First frame: no gap
    metrics.recordLivePreviewFramePublished(at: 1.0, publishDurationMs: 5)
    XCTAssertEqual(metrics.livePreviewFrameCount, 1)
    XCTAssertEqual(metrics.livePreviewGapMaxMs, 0)

    // Second frame: 100ms later
    metrics.recordLivePreviewFramePublished(at: 1.1, publishDurationMs: 3)
    XCTAssertEqual(metrics.livePreviewFrameCount, 2)
    XCTAssertEqual(metrics.livePreviewGapMaxMs, 100)

    // Third frame: 50ms later
    metrics.recordLivePreviewFramePublished(at: 1.15, publishDurationMs: 4)
    XCTAssertEqual(metrics.livePreviewFrameCount, 3)
    XCTAssertEqual(metrics.livePreviewGapMaxMs, 100) // Max stays 100

    XCTAssertEqual(metrics.livePreviewPublishDurationTotalMs, 12) // 5 + 3 + 4
  }

  // MARK: - Commit Tracking

  func testRecordCommitScheduledAndCoalesced() {
    var metrics = ScrollingCaptureSessionMetrics()
    metrics.recordCommitScheduled()
    metrics.recordCommitScheduled()
    metrics.recordCommitCoalesced()

    XCTAssertEqual(metrics.commitScheduleCount, 2)
    XCTAssertEqual(metrics.commitCoalescedCount, 1)
  }

  // MARK: - Finalizing

  func testFinalizingDurationTracking() {
    var metrics = ScrollingCaptureSessionMetrics()
    metrics.recordFinalizingStarted(at: 10.0)
    metrics.recordFinalizingCompleted(at: 10.5)

    XCTAssertEqual(metrics.finalizingStartCount, 1)
    XCTAssertEqual(metrics.finalizingDurationTotalMs, 500)
  }

  func testFinalizingBlockedInput() {
    var metrics = ScrollingCaptureSessionMetrics()
    metrics.recordFinalizingBlockedInput()
    metrics.recordFinalizingBlockedInput()

    XCTAssertEqual(metrics.finalizingBlockedInputCount, 2)
  }

  func testPreStartEscapeCancel() {
    var metrics = ScrollingCaptureSessionMetrics()
    metrics.recordPreStartEscapeCancel()

    XCTAssertEqual(metrics.preStartEscapeCancelCount, 1)
    XCTAssertTrue(metrics.hadActivity)
  }

  // MARK: - Preview Truth

  func testRecordPreviewTruthLiveAhead() {
    var metrics = ScrollingCaptureSessionMetrics()
    metrics.recordPreviewTruthLiveAhead(lagMs: 50)
    metrics.recordPreviewTruthLiveAhead(lagMs: 120)
    metrics.recordPreviewTruthLiveAhead(lagMs: 80)

    XCTAssertEqual(metrics.previewTruthLiveAheadCount, 3)
    XCTAssertEqual(metrics.previewTruthLiveAheadMaxLagMs, 120)
  }

  // MARK: - Summary Context

  func testSummaryContext_returnsAllExpectedKeys() {
    var metrics = ScrollingCaptureSessionMetrics()
    metrics.recordScrollEvent(deltaY: 10)
    metrics.recordRefreshSuccess(
      reason: "scroll",
      captureDurationMs: 10,
      stitchDurationMs: 5,
      previewPublishDurationMs: 3,
      totalDurationMs: 18,
      outcome: .initialized,
      alignmentDebug: nil
    )

    let context = metrics.summaryContext(reason: "test-done")

    let expectedKeys = [
      "reason", "durationSeconds", "scrollEvents", "scrollDistancePoints",
      "refreshAttempts", "refreshSuccesses", "refreshFailures", "refreshAvgMs",
      "captureAvgMs", "stitchAvgMs", "previewPublishAvgMs", "refreshReasons",
      "initialized", "appended", "ignoredNoMovement", "likelyBoundaryNoMovement",
      "ignoredAlignmentFailed", "alignmentFailureStreakMax", "heightLimitHits",
      "fastGuidedMatches", "guidedVisionMatches", "recoveryVisionMatches",
      "visionEstimates", "matcherConfidenceAvg", "appendDeltaAvgPx", "appendDeltaMaxPx",
      "livePreviewStarts", "livePreviewStartFailures", "livePreviewFallbacks",
      "livePreviewFailures", "livePreviewFrames", "commitSchedules", "commitCoalesced",
      "livePreviewPublishAvgMs", "livePreviewGapAvgMs", "livePreviewGapMaxMs",
      "previewTruthLiveAhead", "previewTruthLiveAheadMaxLagMs",
      "finalizingStarts", "finalizingAvgMs", "finalizingBlockedInput",
      "preStartEscapeCancels"
    ]

    for key in expectedKeys {
      XCTAssertNotNil(context[key], "Missing key: \(key)")
    }

    XCTAssertEqual(context["reason"], "test-done")
  }

  // MARK: - Reason Counting

  func testRefreshReasonCounts_accumulatesCorrectly() {
    var metrics = ScrollingCaptureSessionMetrics()
    metrics.recordRefreshSuccess(
      reason: "scroll", captureDurationMs: 0, stitchDurationMs: 0,
      previewPublishDurationMs: 0, totalDurationMs: 0,
      outcome: .initialized, alignmentDebug: nil
    )
    metrics.recordRefreshSuccess(
      reason: "scroll", captureDurationMs: 0, stitchDurationMs: 0,
      previewPublishDurationMs: 0, totalDurationMs: 0,
      outcome: .appended(deltaY: 10), alignmentDebug: nil
    )
    metrics.recordRefreshFailure(
      reason: "timer", captureDurationMs: 0, stitchDurationMs: 0, totalDurationMs: 0
    )

    let context = metrics.summaryContext(reason: "done")
    // Should contain both reasons
    XCTAssertTrue(context["refreshReasons"]?.contains("scroll=2") ?? false)
    XCTAssertTrue(context["refreshReasons"]?.contains("timer=1") ?? false)
  }

  // MARK: - Appended Delta Max Tracking

  func testAppendedDeltaMax_tracksLargest() {
    var metrics = ScrollingCaptureSessionMetrics()
    let deltas = [10, 50, 30, 20]

    for delta in deltas {
      let debug = ScrollingCaptureAlignmentDebugInfo(
        path: .fastGuided, usedVisionEstimate: false, confidence: 0.9,
        pixelScore: nil, totalScore: nil, appendDeltaY: delta, visionAgreementCount: 0
      )
      metrics.recordRefreshSuccess(
        reason: "scroll", captureDurationMs: 0, stitchDurationMs: 0,
        previewPublishDurationMs: 0, totalDurationMs: 0,
        outcome: .appended(deltaY: delta), alignmentDebug: debug
      )
    }

    XCTAssertEqual(metrics.appendedDeltaMaxPixels, 50)
    XCTAssertEqual(metrics.appendedDeltaTotalPixels, 110)
    XCTAssertEqual(metrics.appendedCount, 4)
  }
}
