//
//  ScrollingCaptureAutoScrollControllerTests.swift
//  SnapzyTests
//
//  Closed-loop Auto Scroll sequencing: one step, one settled commit, no stale frames.
//

import XCTest
@testable import Snapzy

@MainActor
final class ScrollingCaptureAutoScrollControllerTests: XCTestCase {

  func testNoSecondStepStartsUntilPreviousCommitResolves() throws {
    let controller = ScrollingCaptureAutoScrollController()
    let step = try beginPostedStep(on: controller)

    XCTAssertFalse(controller.canBeginStep)
    XCTAssertTrue(controller.finishEmitting(generation: 1))
    XCTAssertFalse(controller.canBeginStep)
    XCTAssertTrue(controller.markReadyToCommit(generation: 1))
    XCTAssertFalse(controller.canBeginStep)

    XCTAssertTrue(controller.noteCommitRequested(generation: 1, stepID: step.id))
    XCTAssertFalse(controller.canBeginStep)
    XCTAssertNil(controller.beginStep(generation: 1, regionHeight: 400, isRetry: false))

    let action = controller.handleCommitResult(
      generation: 1,
      stepID: step.id,
      update: stitchUpdate(outcome: .appended(deltaY: 80))
    )
    XCTAssertEqual(action, .keepScrolling)
    XCTAssertTrue(controller.canBeginStep)
  }

  func testSyntheticEventsInsideAStepDoNotCreateCommits() throws {
    let controller = ScrollingCaptureAutoScrollController()
    let step = try beginPostedStep(on: controller)

    controller.noteSyntheticEvent(at: 1.02, generation: 1)
    controller.noteSyntheticEvent(at: 1.04, generation: 1)

    XCTAssertEqual(controller.phase, .emittingBoundedStep)
    XCTAssertEqual(controller.settledCommitCount, 0)
    XCTAssertFalse(controller.noteCommitRequested(generation: 1, stepID: step.id))
  }

  func testExactlyOneSettledCommitPerSuccessfulStep() throws {
    let controller = ScrollingCaptureAutoScrollController()
    let step = try requestCommit(on: controller)

    XCTAssertFalse(controller.noteCommitRequested(generation: 1, stepID: step.id))
    XCTAssertEqual(controller.settledCommitCount, 1)
  }

  func testFrameOlderThanFinalSyntheticEventIsNotEligible() throws {
    let controller = ScrollingCaptureAutoScrollController()
    _ = try beginPostedStep(on: controller, eventAt: 5.0)

    XCTAssertFalse(controller.isFrameEligible(capturedAt: 4.9, generation: 1))
    XCTAssertTrue(controller.isFrameEligible(capturedAt: 5.01, generation: 1))
  }

  func testKnownStepExpectedDeltaUsesCurrentStepNotPreviousAccepted() throws {
    let controller = ScrollingCaptureAutoScrollController()
    let step = try beginPostedStep(on: controller, regionHeight: 800)

    let expected = try XCTUnwrap(
      controller.expectedSignedDeltaPixels(observedDistancePoints: 0, scaleFactor: 2)
    )
    XCTAssertEqual(expected, -Int(step.plan.postedDistancePoints * 2))
    XCTAssertEqual(
      expected,
      ScrollingCaptureAutoScrollPolicy.expectedSignedDeltaPixels(
        postedDistancePoints: step.plan.postedDistancePoints,
        observedDistancePoints: 0,
        scaleFactor: 2
      )
    )
  }

  func testFailedAlignmentCausesRetryRatherThanImmediateNextFullStep() throws {
    let controller = ScrollingCaptureAutoScrollController()
    let step = try requestCommit(on: controller)

    let action = controller.handleCommitResult(
      generation: 1,
      stepID: step.id,
      update: stitchUpdate(outcome: .ignoredAlignmentFailed, matchFailureCount: 1)
    )
    XCTAssertEqual(action, .retryStep)

    let retry = try XCTUnwrap(controller.beginStep(generation: 1, regionHeight: 400, isRetry: true))
    XCTAssertTrue(retry.isRetry)
    XCTAssertLessThan(retry.plan.postedDistancePoints, step.plan.postedDistancePoints)
  }

  func testPointerLeavingAbortsUnsettledStepWithoutCommit() throws {
    let controller = ScrollingCaptureAutoScrollController()
    _ = try beginPostedStep(on: controller)

    XCTAssertTrue(controller.abortActiveStepWithoutCommit(generation: 1))
    XCTAssertEqual(controller.phase, .idle)
    XCTAssertNil(controller.activeStep)
    XCTAssertEqual(controller.settledCommitCount, 0)
  }

  func testCancelInvalidatesLateCommitResults() throws {
    let controller = ScrollingCaptureAutoScrollController()
    let step = try requestCommit(on: controller)

    controller.invalidate(generation: 2)
    XCTAssertNil(
      controller.handleCommitResult(
        generation: 1,
        stepID: step.id,
        update: stitchUpdate(outcome: .appended(deltaY: 80))
      )
    )
    XCTAssertEqual(controller.phase, .idle)
  }

  func testDoneWaitsForActiveStepAndDoesNotStartAnother() throws {
    let controller = ScrollingCaptureAutoScrollController()
    let step = try requestCommit(on: controller)

    controller.requestStop(.finishRequested)
    XCTAssertFalse(controller.canBeginStep)
    XCTAssertFalse(controller.isIdleForFinish)
    XCTAssertTrue(controller.isWaitingForCommitResult)

    let action = controller.handleCommitResult(
      generation: 1,
      stepID: step.id,
      update: stitchUpdate(outcome: .appended(deltaY: 80))
    )
    XCTAssertEqual(action, .keepScrolling)
    XCTAssertTrue(controller.isIdleForFinish)
    XCTAssertFalse(controller.canBeginStep)
  }

  func testBoundaryDetectionRequiresTwoObservations() throws {
    let controller = ScrollingCaptureAutoScrollController()
    let first = try requestCommit(on: controller)

    XCTAssertEqual(
      controller.handleCommitResult(
        generation: 1,
        stepID: first.id,
        update: stitchUpdate(outcome: .ignoredNoMovement, likelyReachedBoundary: true)
      ),
      .retryStep
    )

    let second = try requestCommit(on: controller, isRetry: true, eventAt: 2.0)
    XCTAssertEqual(
      controller.handleCommitResult(
        generation: 1,
        stepID: second.id,
        update: stitchUpdate(outcome: .ignoredNoMovement, likelyReachedBoundary: true)
      ),
      .finishCapture
    )
  }

  func testManualCommitLoopIsNotSuppressedWhileIdle() throws {
    let controller = ScrollingCaptureAutoScrollController()
    controller.start(generation: 1)
    XCTAssertFalse(controller.suppressesManualCommitLoop)

    XCTAssertNotNil(controller.beginStep(generation: 1, regionHeight: 400, isRetry: false))
    XCTAssertTrue(controller.suppressesManualCommitLoop)
  }

  func testRingRejectsFramesCapturedBeforeSyntheticEvent() {
    let ring = ScrollingCaptureFrameRing(capacity: 8)
    guard let image = TestImageFactory.solidColor(width: 20, height: 20) else {
      XCTFail("Failed to create frame image")
      return
    }

    ring.append(ScrollingCaptureFrame(sequenceNumber: 1, image: image, capturedAt: 1.0, motionScore: nil))
    ring.append(ScrollingCaptureFrame(sequenceNumber: 2, image: image, capturedAt: 1.4, motionScore: nil))
    ring.append(ScrollingCaptureFrame(sequenceNumber: 3, image: image, capturedAt: 1.8, motionScore: nil))

    let eligible = ring.latestFrame(capturedAfter: 1.5, afterSequenceNumber: 1)
    XCTAssertEqual(eligible?.sequenceNumber, 3)

    XCTAssertNil(ring.latestFrame(capturedAfter: 2.0, afterSequenceNumber: 1))
  }

  @discardableResult
  private func beginPostedStep(
    on controller: ScrollingCaptureAutoScrollController,
    generation: Int = 1,
    regionHeight: CGFloat = 400,
    isRetry: Bool = false,
    eventAt: TimeInterval = 1.0
  ) throws -> ScrollingCaptureAutoScrollStep {
    if controller.phase == .idle, controller.stopReason == .none {
      controller.start(generation: generation)
    }
    let step = try XCTUnwrap(
      controller.beginStep(generation: generation, regionHeight: regionHeight, isRetry: isRetry)
    )
    controller.noteSyntheticEvent(at: eventAt, generation: generation)
    return step
  }

  @discardableResult
  private func requestCommit(
    on controller: ScrollingCaptureAutoScrollController,
    generation: Int = 1,
    isRetry: Bool = false,
    eventAt: TimeInterval = 1.0
  ) throws -> ScrollingCaptureAutoScrollStep {
    let step = try beginPostedStep(
      on: controller,
      generation: generation,
      isRetry: isRetry,
      eventAt: eventAt
    )
    XCTAssertTrue(controller.finishEmitting(generation: generation))
    XCTAssertTrue(controller.markReadyToCommit(generation: generation))
    XCTAssertTrue(controller.noteCommitRequested(generation: generation, stepID: step.id))
    return step
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
