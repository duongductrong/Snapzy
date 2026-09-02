//
//  ScrollingCaptureAutoScrollController.swift
//  Snapzy
//
//  Closed-loop Auto Scroll state machine: one bounded step, settle, then one commit.
//

import Foundation

struct ScrollingCaptureAutoScrollStep: Equatable {
  let id: UUID
  let generation: Int
  let plan: ScrollingCaptureAutoScrollPolicy.StepPlan
  let isRetry: Bool
  var postedTickCount: Int
  var lastSyntheticEventAt: TimeInterval?
  var postEventFrameCount: Int
  var commitRequested: Bool

  var hasPostedEvents: Bool {
    postedTickCount > 0
  }
}

/// Serializes Auto Scroll so a new synthetic step cannot start while a commit is pending,
/// and so synthetic wheel events cannot schedule the manual-scroll commit loop.
final class ScrollingCaptureAutoScrollController {
  private(set) var phase: ScrollingCaptureAutoScrollPhase = .idle
  private(set) var activeStep: ScrollingCaptureAutoScrollStep?
  private(set) var generation = 0
  private(set) var consecutiveNoMovementCount = 0
  private(set) var stopReason: ScrollingCaptureAutoScrollStopReason = .none
  private(set) var stepCount = 0
  private(set) var settledCommitCount = 0
  private(set) var retryCount = 0
  private(set) var rejectedStaleFrameCount = 0
  private(set) var boundaryConfirmationCount = 0

  var isDriving: Bool {
    stopReason != .cancelRequested && (phase != .idle || stopReason == .finishRequested)
  }

  var suppressesManualCommitLoop: Bool {
    switch phase {
    case .idle:
      return false
    case .emittingBoundedStep, .waitingForSettle, .requestingCommit, .waitingForCommitResult, .decidingNextAction:
      return true
    }
  }

  var canBeginStep: Bool {
    guard stopReason == .none else { return false }
    switch phase {
    case .idle, .decidingNextAction:
      return activeStep == nil || activeStep?.commitRequested == true
    case .emittingBoundedStep, .waitingForSettle, .requestingCommit, .waitingForCommitResult:
      return false
    }
  }

  var isWaitingForCommitResult: Bool {
    phase == .waitingForCommitResult
  }

  var isIdleForFinish: Bool {
    switch phase {
    case .idle:
      return true
    case .decidingNextAction:
      return stopReason != .none
    case .emittingBoundedStep, .waitingForSettle, .requestingCommit, .waitingForCommitResult:
      return false
    }
  }

  func start(generation: Int) {
    self.generation = generation
    phase = .idle
    activeStep = nil
    consecutiveNoMovementCount = 0
    stopReason = .none
    stepCount = 0
    settledCommitCount = 0
    retryCount = 0
    rejectedStaleFrameCount = 0
    boundaryConfirmationCount = 0
  }

  func requestStop(_ reason: ScrollingCaptureAutoScrollStopReason) {
    stopReason = reason
    if reason == .cancelRequested {
      invalidate(generation: generation)
    }
  }

  func invalidate(generation: Int) {
    self.generation = generation
    phase = .idle
    activeStep = nil
    stopReason = .cancelRequested
  }

  func matchesGeneration(_ generation: Int) -> Bool {
    generation == self.generation && stopReason != .cancelRequested
  }

  @discardableResult
  func beginStep(generation: Int, regionHeight: CGFloat, isRetry: Bool) -> ScrollingCaptureAutoScrollStep? {
    guard matchesGeneration(generation), canBeginStep else { return nil }

    let plan = ScrollingCaptureAutoScrollPolicy.stepPlan(
      regionHeight: regionHeight,
      isRetry: isRetry
    )
    let step = ScrollingCaptureAutoScrollStep(
      id: UUID(),
      generation: generation,
      plan: plan,
      isRetry: isRetry,
      postedTickCount: 0,
      lastSyntheticEventAt: nil,
      postEventFrameCount: 0,
      commitRequested: false
    )
    activeStep = step
    phase = .emittingBoundedStep
    stepCount += 1
    if isRetry {
      retryCount += 1
    }
    return step
  }

  func noteSyntheticEvent(at time: TimeInterval, generation: Int) {
    guard matchesGeneration(generation), phase == .emittingBoundedStep, var step = activeStep else {
      return
    }

    step.postedTickCount += 1
    step.lastSyntheticEventAt = time
    activeStep = step
  }

  @discardableResult
  func abortActiveStepWithoutCommit(generation: Int) -> Bool {
    guard matchesGeneration(generation) else { return false }
    switch phase {
    case .emittingBoundedStep, .waitingForSettle, .requestingCommit:
      activeStep = nil
      phase = .idle
      return true
    case .idle, .waitingForCommitResult, .decidingNextAction:
      return false
    }
  }

  @discardableResult
  func finishEmitting(generation: Int) -> Bool {
    guard matchesGeneration(generation), phase == .emittingBoundedStep else { return false }
    guard let step = activeStep, step.hasPostedEvents else {
      activeStep = nil
      phase = .idle
      return false
    }

    phase = .waitingForSettle
    return true
  }

  @discardableResult
  func markReadyToCommit(generation: Int) -> Bool {
    guard matchesGeneration(generation), phase == .waitingForSettle, activeStep?.hasPostedEvents == true else {
      return false
    }
    phase = .requestingCommit
    return true
  }

  func shouldAcceptCommitRequest(generation: Int, stepID: UUID) -> Bool {
    guard matchesGeneration(generation), phase == .requestingCommit else { return false }
    guard let step = activeStep, step.id == stepID, !step.commitRequested else { return false }
    return true
  }

  @discardableResult
  func noteCommitRequested(generation: Int, stepID: UUID) -> Bool {
    guard shouldAcceptCommitRequest(generation: generation, stepID: stepID), var step = activeStep else {
      return false
    }

    step.commitRequested = true
    activeStep = step
    phase = .waitingForCommitResult
    settledCommitCount += 1
    return true
  }

  func isFrameEligible(capturedAt: TimeInterval, generation: Int) -> Bool {
    guard matchesGeneration(generation) else { return false }
    return ScrollingCaptureAutoScrollPolicy.isCommitFrameEligible(
      capturedAt: capturedAt,
      lastSyntheticEventAt: activeStep?.lastSyntheticEventAt
    )
  }

  func noteRejectedStaleFrame() {
    rejectedStaleFrameCount += 1
  }

  func notePostEventFrame(capturedAt: TimeInterval, generation: Int) {
    guard isFrameEligible(capturedAt: capturedAt, generation: generation), var step = activeStep else {
      return
    }
    step.postEventFrameCount += 1
    activeStep = step
  }

  func hasSettledFrames(minimum: Int = ScrollingCaptureAutoScrollPolicy.minimumPostEventFrames) -> Bool {
    (activeStep?.postEventFrameCount ?? 0) >= minimum
  }

  func expectedSignedDeltaPixels(observedDistancePoints: CGFloat, scaleFactor: CGFloat) -> Int? {
    guard let step = activeStep else { return nil }
    return ScrollingCaptureAutoScrollPolicy.expectedSignedDeltaPixels(
      postedDistancePoints: step.plan.postedDistancePoints,
      observedDistancePoints: observedDistancePoints,
      scaleFactor: scaleFactor
    )
  }

  func handleCommitResult(
    generation: Int,
    stepID: UUID,
    update: ScrollingCaptureStitchUpdate?
  ) -> ScrollingCaptureAutoScrollStitchAction? {
    guard matchesGeneration(generation) else { return nil }
    guard phase == .waitingForCommitResult, activeStep?.id == stepID else { return nil }

    phase = .decidingNextAction
    let action: ScrollingCaptureAutoScrollStitchAction
    if let update {
      switch update.outcome {
      case .ignoredNoMovement:
        consecutiveNoMovementCount += 1
        if update.likelyReachedBoundary {
          boundaryConfirmationCount += 1
        }
      case .initialized, .appended:
        consecutiveNoMovementCount = 0
      case .ignoredAlignmentFailed, .reachedHeightLimit:
        break
      }
      action = ScrollingCaptureAutoScrollPolicy.stitchAction(
        for: update,
        consecutiveNoMovementCount: consecutiveNoMovementCount
      )
    } else {
      consecutiveNoMovementCount += 1
      action = ScrollingCaptureAutoScrollPolicy.actionForMissingStitchUpdate(
        consecutiveNoMovementCount: consecutiveNoMovementCount
      )
    }

    activeStep = nil
    if stopReason != .none {
      phase = .idle
    }
    return action
  }
}
