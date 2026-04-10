//
//  ScrollingCaptureMetrics.swift
//  Snapzy
//
//  Lightweight per-session metrics for scrolling capture diagnostics.
//

import Foundation

struct ScrollingCaptureSessionMetrics {
  private(set) var sessionStartedAt = ProcessInfo.processInfo.systemUptime
  private(set) var scrollEventCount = 0
  private(set) var totalScrollDistancePoints: CGFloat = 0

  private(set) var livePreviewStartAttempts = 0
  private(set) var livePreviewStartFailures = 0
  private(set) var livePreviewFallbackActivations = 0
  private(set) var livePreviewFailureCount = 0
  private(set) var livePreviewFrameCount = 0
  private(set) var livePreviewPublishDurationTotalMs = 0
  private(set) var livePreviewGapTotalMs = 0
  private(set) var livePreviewGapMaxMs = 0

  private(set) var commitScheduleCount = 0
  private(set) var commitCoalescedCount = 0

  private(set) var refreshAttemptCount = 0
  private(set) var refreshSuccessCount = 0
  private(set) var refreshFailureCount = 0
  private(set) var refreshCaptureDurationTotalMs = 0
  private(set) var refreshStitchDurationTotalMs = 0
  private(set) var refreshPreviewPublishDurationTotalMs = 0
  private(set) var refreshDurationTotalMs = 0
  private(set) var refreshReasonCounts: [String: Int] = [:]

  private(set) var initializedCount = 0
  private(set) var appendedCount = 0
  private(set) var ignoredNoMovementCount = 0
  private(set) var ignoredAlignmentFailedCount = 0
  private(set) var reachedHeightLimitCount = 0
  private(set) var alignmentFailureStreakMax = 0
  private(set) var fastGuidedMatchCount = 0
  private(set) var guidedVisionMatchCount = 0
  private(set) var recoveryVisionMatchCount = 0
  private(set) var visionEstimateCount = 0
  private(set) var matcherConfidenceTotal = 0.0
  private(set) var matcherConfidenceCount = 0
  private(set) var appendedDeltaTotalPixels = 0
  private(set) var appendedDeltaMaxPixels = 0

  private(set) var autoScrollStepCount = 0
  private(set) var autoScrollRequestedStepTotalPoints: CGFloat = 0
  private(set) var autoScrollRequestedStepMaxPoints: CGFloat = 0
  private(set) var autoScrollBlockedCount = 0
  private(set) var autoScrollBoundaryCount = 0
  private(set) var autoScrollFailureCount = 0
  private(set) var autoScrollFrameObservationCount = 0
  private(set) var autoScrollFrameObservationTimeoutCount = 0
  private(set) var autoScrollFrameWaitDurationTotalMs = 0
  private(set) var autoScrollCommitAcceptedCount = 0

  private var lastLivePreviewFrameAt: TimeInterval?
  private var currentAlignmentFailureStreak = 0

  var hadActivity: Bool {
    scrollEventCount > 0
      || livePreviewStartAttempts > 0
      || livePreviewFrameCount > 0
      || refreshAttemptCount > 0
      || autoScrollStepCount > 0
  }

  mutating func recordScrollEvent(deltaY: CGFloat) {
    scrollEventCount += 1
    totalScrollDistancePoints += deltaY
  }

  mutating func recordLivePreviewStart(success: Bool) {
    livePreviewStartAttempts += 1
    if !success {
      livePreviewStartFailures += 1
    }
  }

  mutating func recordLivePreviewFallbackActivation() {
    livePreviewFallbackActivations += 1
  }

  mutating func recordLivePreviewFailure() {
    livePreviewFailureCount += 1
    livePreviewFallbackActivations += 1
  }

  mutating func recordLivePreviewFramePublished(
    at timestamp: TimeInterval,
    publishDurationMs: Int
  ) {
    livePreviewFrameCount += 1
    livePreviewPublishDurationTotalMs += publishDurationMs

    if let lastLivePreviewFrameAt {
      let gapMs = Int(((timestamp - lastLivePreviewFrameAt) * 1_000).rounded())
      livePreviewGapTotalMs += gapMs
      livePreviewGapMaxMs = max(livePreviewGapMaxMs, gapMs)
    }

    lastLivePreviewFrameAt = timestamp
  }

  mutating func recordCommitScheduled() {
    commitScheduleCount += 1
  }

  mutating func recordCommitCoalesced() {
    commitCoalescedCount += 1
  }

  mutating func recordRefreshSuccess(
    reason: String,
    captureDurationMs: Int,
    stitchDurationMs: Int,
    previewPublishDurationMs: Int,
    totalDurationMs: Int,
    outcome: ScrollingCaptureStitchOutcome,
    alignmentDebug: ScrollingCaptureAlignmentDebugInfo?
  ) {
    refreshAttemptCount += 1
    refreshSuccessCount += 1
    refreshReasonCounts[reason, default: 0] += 1
    refreshCaptureDurationTotalMs += captureDurationMs
    refreshStitchDurationTotalMs += stitchDurationMs
    refreshPreviewPublishDurationTotalMs += previewPublishDurationMs
    refreshDurationTotalMs += totalDurationMs

    switch outcome {
    case .initialized:
      initializedCount += 1
      currentAlignmentFailureStreak = 0
    case .appended:
      appendedCount += 1
      currentAlignmentFailureStreak = 0
      if let appendDeltaY = alignmentDebug?.appendDeltaY {
        appendedDeltaTotalPixels += appendDeltaY
        appendedDeltaMaxPixels = max(appendedDeltaMaxPixels, appendDeltaY)
      }
    case .ignoredNoMovement:
      ignoredNoMovementCount += 1
    case .ignoredAlignmentFailed:
      ignoredAlignmentFailedCount += 1
      currentAlignmentFailureStreak += 1
      alignmentFailureStreakMax = max(alignmentFailureStreakMax, currentAlignmentFailureStreak)
    case .reachedHeightLimit:
      reachedHeightLimitCount += 1
      currentAlignmentFailureStreak = 0
    }

    if let alignmentDebug {
      if alignmentDebug.usedVisionEstimate {
        visionEstimateCount += 1
      }

      switch alignmentDebug.path {
      case .fastGuided:
        fastGuidedMatchCount += 1
      case .guidedVision:
        guidedVisionMatchCount += 1
      case .recoveryVision:
        recoveryVisionMatchCount += 1
      default:
        break
      }

      matcherConfidenceTotal += alignmentDebug.confidence
      matcherConfidenceCount += 1
    }
  }

  mutating func recordRefreshFailure(
    reason: String,
    captureDurationMs: Int,
    stitchDurationMs: Int,
    totalDurationMs: Int
  ) {
    refreshAttemptCount += 1
    refreshFailureCount += 1
    refreshReasonCounts[reason, default: 0] += 1
    refreshCaptureDurationTotalMs += captureDurationMs
    refreshStitchDurationTotalMs += stitchDurationMs
    refreshDurationTotalMs += totalDurationMs
  }

  mutating func recordAutoScrollStep(
    requestedPoints: CGFloat,
    outcome: ScrollingCaptureAutoScrollEngine.StepOutcome
  ) {
    autoScrollStepCount += 1
    autoScrollRequestedStepTotalPoints += requestedPoints
    autoScrollRequestedStepMaxPoints = max(autoScrollRequestedStepMaxPoints, requestedPoints)

    switch outcome {
    case .scrolled:
      break
    case .blocked:
      autoScrollBlockedCount += 1
    case .reachedBoundary:
      autoScrollBoundaryCount += 1
    case .failed:
      autoScrollFailureCount += 1
    }
  }

  mutating func recordAutoScrollFrameObservation(waitDurationMs: Int, didObserveFrame: Bool) {
    autoScrollFrameObservationCount += 1
    autoScrollFrameWaitDurationTotalMs += waitDurationMs
    if !didObserveFrame {
      autoScrollFrameObservationTimeoutCount += 1
    }
  }

  mutating func recordAutoScrollCommitAccepted() {
    autoScrollCommitAcceptedCount += 1
  }

  func summaryContext(reason: String) -> [String: String] {
    let sessionDurationSeconds = max(0, ProcessInfo.processInfo.systemUptime - sessionStartedAt)
    let livePreviewGapCount = max(0, livePreviewFrameCount - 1)

    return [
      "reason": reason,
      "durationSeconds": Self.formatted(sessionDurationSeconds),
      "scrollEvents": "\(scrollEventCount)",
      "scrollDistancePoints": Self.formatted(totalScrollDistancePoints),
      "refreshAttempts": "\(refreshAttemptCount)",
      "refreshSuccesses": "\(refreshSuccessCount)",
      "refreshFailures": "\(refreshFailureCount)",
      "refreshAvgMs": Self.averageString(total: refreshDurationTotalMs, count: refreshAttemptCount),
      "captureAvgMs": Self.averageString(
        total: refreshCaptureDurationTotalMs,
        count: refreshAttemptCount
      ),
      "stitchAvgMs": Self.averageString(
        total: refreshStitchDurationTotalMs,
        count: refreshAttemptCount
      ),
      "previewPublishAvgMs": Self.averageString(
        total: refreshPreviewPublishDurationTotalMs,
        count: refreshSuccessCount
      ),
      "refreshReasons": Self.compactDescription(refreshReasonCounts),
      "initialized": "\(initializedCount)",
      "appended": "\(appendedCount)",
      "ignoredNoMovement": "\(ignoredNoMovementCount)",
      "ignoredAlignmentFailed": "\(ignoredAlignmentFailedCount)",
      "alignmentFailureStreakMax": "\(alignmentFailureStreakMax)",
      "heightLimitHits": "\(reachedHeightLimitCount)",
      "fastGuidedMatches": "\(fastGuidedMatchCount)",
      "guidedVisionMatches": "\(guidedVisionMatchCount)",
      "recoveryVisionMatches": "\(recoveryVisionMatchCount)",
      "visionEstimates": "\(visionEstimateCount)",
      "matcherConfidenceAvg": Self.averageString(total: matcherConfidenceTotal, count: matcherConfidenceCount),
      "appendDeltaAvgPx": Self.averageString(total: appendedDeltaTotalPixels, count: appendedCount),
      "appendDeltaMaxPx": "\(appendedDeltaMaxPixels)",
      "livePreviewStarts": "\(livePreviewStartAttempts)",
      "livePreviewStartFailures": "\(livePreviewStartFailures)",
      "livePreviewFallbacks": "\(livePreviewFallbackActivations)",
      "livePreviewFailures": "\(livePreviewFailureCount)",
      "livePreviewFrames": "\(livePreviewFrameCount)",
      "commitSchedules": "\(commitScheduleCount)",
      "commitCoalesced": "\(commitCoalescedCount)",
      "livePreviewPublishAvgMs": Self.averageString(
        total: livePreviewPublishDurationTotalMs,
        count: livePreviewFrameCount
      ),
      "livePreviewGapAvgMs": Self.averageString(total: livePreviewGapTotalMs, count: livePreviewGapCount),
      "livePreviewGapMaxMs": "\(livePreviewGapMaxMs)",
      "autoScrollSteps": "\(autoScrollStepCount)",
      "autoScrollStepAvgPoints": Self.averageString(
        total: Int(autoScrollRequestedStepTotalPoints.rounded()),
        count: autoScrollStepCount
      ),
      "autoScrollStepMaxPoints": Self.formatted(autoScrollRequestedStepMaxPoints),
      "autoScrollBlocked": "\(autoScrollBlockedCount)",
      "autoScrollBoundaries": "\(autoScrollBoundaryCount)",
      "autoScrollFailures": "\(autoScrollFailureCount)",
      "autoScrollFrameObservations": "\(autoScrollFrameObservationCount)",
      "autoScrollFrameTimeouts": "\(autoScrollFrameObservationTimeoutCount)",
      "autoScrollFrameWaitAvgMs": Self.averageString(
        total: autoScrollFrameWaitDurationTotalMs,
        count: autoScrollFrameObservationCount
      ),
      "autoScrollCommitAccepted": "\(autoScrollCommitAcceptedCount)"
    ]
  }

  private static func averageString(total: Int, count: Int) -> String {
    guard count > 0 else { return "0" }
    return "\(Int(round(Double(total) / Double(count))))"
  }

  private static func averageString(total: Double, count: Int) -> String {
    guard count > 0 else { return "0.00" }
    return String(format: "%.2f", total / Double(count))
  }

  private static func compactDescription(_ counts: [String: Int]) -> String {
    guard !counts.isEmpty else { return "none" }
    return counts
      .sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
      .joined(separator: ",")
  }

  private static func formatted(_ value: CGFloat) -> String {
    String(format: "%.1f", Double(value))
  }

  private static func formatted(_ value: TimeInterval) -> String {
    String(format: "%.2f", value)
  }
}
