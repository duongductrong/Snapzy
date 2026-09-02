//
//  ScrollingCaptureAutoScrollControllerTests.swift
//  SnapzyTests
//
//  Closed-loop Auto Scroll sequencing: one step, one settled commit, no stale frames.
//

import XCTest
@testable import Snapzy

final class ScrollingCaptureAutoScrollControllerTests: XCTestCase {

  func testNoSecondStepStartsUntilPreviousCommitResolves() {
    let controller = ScrollingCaptureAutoScrollController()
    controller.start(generation: 1)

    XCTAssertNotNil(controller.beginStep(generation: 1, regionHeight: 400, isRetry: false))
    XCTAssertFalse(controller.canBeginStep)
    controller.noteSyntheticEvent(at: 1.0, generation: 1)

    XCTAssertTrue(controller.finishEmitting(generation: 1))
    XCTAssertFalse(controller.canBeginStep)
    XCTAssertTrue(controller.markReadyToCommit(generation: 1))
    XCTAssertFalse(controller.canBeginStep)

    let stepID = try! XCTUnwrap(controller.activeStep?.id)
    XCTAssertTrue(controller.noteCommitRequested(generation: 1, stepID: stepID))
    XCTAssertFalse(controller.canBeginStep)
    XCTAssertNil(controller.beginStep(generation: 1, regionHeight: 400, isRetry: false))

    _ = controller.handleCommitResult(
      generation: 1,
      stepID: stepID,
      update: stitchUpdate(outcome: .appended(deltaY: 80))
    )
    XCTAssertTrue(controller.canBeginStep)
  }

  func testSyntheticEventsInsideAStepDoNotCreateCommits() {
    let controller = ScrollingCaptureAutoScrollController()
    controller.start(generation: 1)
    XCTAssertNotNil(controller.beginStep(generation: 1, regionHeight: 400, isRetry: false))

    controller.noteSyntheticEvent(at: 1.0, generation: 1)
    controller.noteSyntheticEvent(at: 1.02, generation: 1)
    controller.noteSyntheticEvent(at: 1.04, generation: 1)

    XCTAssertEqual(controller.phase, .emittingBoundedStep)
    XCTAssertEqual(controller.settledCommitCount, 0)
    XCTAssertFalse(controller.noteCommitRequested(generation: 1, stepID: try! XCTUnwrap(controller.activeStep?.id)))
  }

  func testExactlyOneSettledCommitPerSuccessfulStep() {
    let controller = ScrollingCaptureAutoScrollController()
    controller.start(generation: 1)
    let step = try! XCTUnwrap(controller.beginStep(generation: 1, regionHeight: 400, isRetry: false))
    controller.noteSyntheticEvent(at: 2.0, generation: 1)
    XCTAssertTrue(controller.finishEmitting(generation: 1))
    XCTAssertTrue(controller.markReadyToCommit(generation: 1))
    XCTAssertTrue(controller.noteCommitRequested(generation: 1, stepID: step.id))
    XCTAssertFalse(controller.noteCommitRequested(generation: 1, stepID: step.id))
    XCTAssertEqual(controller.settledCommitCount, 1)
  }

  func testFrameOlderThanFinalSyntheticEventIsNotEligible() {
    let controller = ScrollingCaptureAutoScrollController()
    controller.start(generation: 1)
    XCTAssertNotNil(controller.beginStep(generation: 1, regionHeight: 400, isRetry: false))
    controller.noteSyntheticEvent(at: 5.0, generation: 1)

    XCTAssertFalse(controller.isFrameEligible(capturedAt: 4.9, generation: 1))
    XCTAssertTrue(controller.isFrameEligible(capturedAt: 5.01, generation: 1))
  }

  func testKnownStepExpectedDeltaUsesCurrentStepNotPreviousAccepted() {
    let controller = ScrollingCaptureAutoScrollController()
    controller.start(generation: 1)
    let step = try! XCTUnwrap(controller.beginStep(generation: 1, regionHeight: 800, isRetry: false))
    controller.noteSyntheticEvent(at: 1.0, generation: 1)

    let expected = try! XCTUnwrap(
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

  func testFailedAlignmentCausesRetryRatherThanImmediateNextFullStep() {
    let controller = ScrollingCaptureAutoScrollController()
    controller.start(generation: 1)
    let step = try! XCTUnwrap(controller.beginStep(generation: 1, regionHeight: 400, isRetry: false))
    controller.noteSyntheticEvent(at: 1.0, generation: 1)
    XCTAssertTrue(controller.finishEmitting(generation: 1))
    XCTAssertTrue(controller.markReadyToCommit(generation: 1))
    XCTAssertTrue(controller.noteCommitRequested(generation: 1, stepID: step.id))

    let action = controller.handleCommitResult(
      generation: 1,
      stepID: step.id,
      update: stitchUpdate(outcome: .ignoredAlignmentFailed, matchFailureCount: 1)
    )
    XCTAssertEqual(action, .retryStep)

    let retry = try! XCTUnwrap(controller.beginStep(generation: 1, regionHeight: 400, isRetry: true))
    XCTAssertTrue(retry.isRetry)
    XCTAssertLessThan(retry.plan.postedDistancePoints, step.plan.postedDistancePoints)
  }

  func testPointerLeavingAbortsUnsettledStepWithoutCommit() {
    let controller = ScrollingCaptureAutoScrollController()
    controller.start(generation: 1)
    XCTAssertNotNil(controller.beginStep(generation: 1, regionHeight: 400, isRetry: false))
    controller.noteSyntheticEvent(at: 1.0, generation: 1)

    XCTAssertTrue(controller.abortActiveStepWithoutCommit(generation: 1))
    XCTAssertEqual(controller.phase, .idle)
    XCTAssertNil(controller.activeStep)
    XCTAssertEqual(controller.settledCommitCount, 0)
  }

  func testCancelInvalidatesLateCommitResults() {
    let controller = ScrollingCaptureAutoScrollController()
    controller.start(generation: 1)
    let step = try! XCTUnwrap(controller.beginStep(generation: 1, regionHeight: 400, isRetry: false))
    controller.noteSyntheticEvent(at: 1.0, generation: 1)
    XCTAssertTrue(controller.finishEmitting(generation: 1))
    XCTAssertTrue(controller.markReadyToCommit(generation: 1))
    XCTAssertTrue(controller.noteCommitRequested(generation: 1, stepID: step.id))

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

  func testDoneWaitsForActiveStepAndDoesNotStartAnother() {
    let controller = ScrollingCaptureAutoScrollController()
    controller.start(generation: 1)
    let step = try! XCTUnwrap(controller.beginStep(generation: 1, regionHeight: 400, isRetry: false))
    controller.noteSyntheticEvent(at: 1.0, generation: 1)
    XCTAssertTrue(controller.finishEmitting(generation: 1))
    XCTAssertTrue(controller.markReadyToCommit(generation: 1))
    XCTAssertTrue(controller.noteCommitRequested(generation: 1, stepID: step.id))

    controller.requestStop(.finishRequested)
    XCTAssertFalse(controller.canBeginStep)
    XCTAssertFalse(controller.isIdleForFinish)
    XCTAssertTrue(controller.isWaitingForCommitResult)

    _ = controller.handleCommitResult(
      generation: 1,
      stepID: step.id,
      update: stitchUpdate(outcome: .appended(deltaY: 80))
    )
    XCTAssertTrue(controller.isIdleForFinish)
    XCTAssertFalse(controller.canBeginStep)
  }

  func testBoundaryDetectionRequiresTwoObservations() {
    let controller = ScrollingCaptureAutoScrollController()
    controller.start(generation: 1)

    let first = try! XCTUnwrap(controller.beginStep(generation: 1, regionHeight: 400, isRetry: false))
    controller.noteSyntheticEvent(at: 1.0, generation: 1)
    XCTAssertTrue(controller.finishEmitting(generation: 1))
    XCTAssertTrue(controller.markReadyToCommit(generation: 1))
    XCTAssertTrue(controller.noteCommitRequested(generation: 1, stepID: first.id))
    XCTAssertEqual(
      controller.handleCommitResult(
        generation: 1,
        stepID: first.id,
        update: stitchUpdate(outcome: .ignoredNoMovement, likelyReachedBoundary: true)
      ),
      .retryStep
    )

    let second = try! XCTUnwrap(controller.beginStep(generation: 1, regionHeight: 400, isRetry: true))
    controller.noteSyntheticEvent(at: 2.0, generation: 1)
    XCTAssertTrue(controller.finishEmitting(generation: 1))
    XCTAssertTrue(controller.markReadyToCommit(generation: 1))
    XCTAssertTrue(controller.noteCommitRequested(generation: 1, stepID: second.id))
    XCTAssertEqual(
      controller.handleCommitResult(
        generation: 1,
        stepID: second.id,
        update: stitchUpdate(outcome: .ignoredNoMovement, likelyReachedBoundary: true)
      ),
      .finishCapture
    )
  }

  func testManualCommitLoopIsNotSuppressedWhileIdle() {
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
