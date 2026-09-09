//
//  SnapzyOnboardingStateTests.swift
//  SnapzyTests
//
//  Unit tests for interactive onboarding state management and Step 1 core workflow.
//

import XCTest
@testable import Snapzy

final class SnapzyOnboardingStateTests: XCTestCase {

  @MainActor
  func testInitialState() {
    let state = SnapzyOnboardingState()
    XCTAssertEqual(state.currentStep, .meetSnapzy)
    XCTAssertEqual(state.step1Stage, .readyToCapture)
    XCTAssertTrue(state.completedSteps.isEmpty)
    XCTAssertTrue(state.completedChallenges.isEmpty)
    XCTAssertFalse(state.canGoBack)
    XCTAssertTrue(state.canGoForward)
    XCTAssertFalse(state.isCurrentStepComplete)
  }

  @MainActor
  func testStep1FullWorkflowProgression() {
    let state = SnapzyOnboardingState()
    XCTAssertEqual(state.step1Stage, .readyToCapture)

    // 1. User selects area
    state.simulateAreaCapture()
    XCTAssertEqual(state.step1Stage, .selectingArea)
    XCTAssertTrue(state.hasAreaSelection)
    XCTAssertTrue(state.completedChallenges.contains(.selectArea))
    XCTAssertFalse(state.isCurrentStepComplete)

    // 2. User captures to Quick Access
    state.completeCaptureToQuickAccess()
    let exp = expectation(description: "Wait for quick access transition")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      XCTAssertEqual(state.step1Stage, .quickAccessFloating)
      XCTAssertTrue(state.completedChallenges.contains(.captureToQuickAccess))
      XCTAssertFalse(state.isCurrentStepComplete)

      // 3. User opens Annotate window from Quick Access
      state.openAnnotateFromQuickAccess()
      XCTAssertEqual(state.step1Stage, .annotateWindowOpen)
      XCTAssertTrue(state.completedChallenges.contains(.openAnnotateWindow))
      XCTAssertTrue(state.isCurrentStepComplete)
      XCTAssertTrue(state.completedSteps.contains(.meetSnapzy))

      // 4. Replay flow
      state.resetStep1Flow()
      XCTAssertEqual(state.step1Stage, .readyToCapture)
      XCTAssertFalse(state.hasAreaSelection)

      exp.fulfill()
    }

    waitForExpectations(timeout: 1.0)
  }

  @MainActor
  func testStepNavigation() {
    let state = SnapzyOnboardingState()

    // Step 1 -> Step 2
    state.nextStep()
    XCTAssertEqual(state.currentStep, .quickAccess)
    XCTAssertTrue(state.canGoBack)
    XCTAssertTrue(state.canGoForward)

    // Step 2 -> Step 3
    state.nextStep()
    XCTAssertEqual(state.currentStep, .shortcuts)

    // Step 3 -> Step 4
    state.nextStep()
    XCTAssertEqual(state.currentStep, .permissions)
    XCTAssertTrue(state.canGoBack)
    XCTAssertFalse(state.canGoForward)

    // Can't advance past permissions
    state.nextStep()
    XCTAssertEqual(state.currentStep, .permissions)

    // Step 4 -> Step 3
    state.previousStep()
    XCTAssertEqual(state.currentStep, .shortcuts)

    // Direct transition
    state.transition(to: .meetSnapzy)
    XCTAssertEqual(state.currentStep, .meetSnapzy)
    XCTAssertEqual(state.step1Stage, .readyToCapture)
  }

  @MainActor
  func testAnnotationToolsSimulation() {
    let state = SnapzyOnboardingState()
    state.simulateAreaCapture()

    state.selectAnnotationTool(.arrow)
    XCTAssertEqual(state.selectedTool, .arrow)
    XCTAssertEqual(state.annotationItems.count, 1)
    XCTAssertEqual(state.annotationItems.first?.tool, .arrow)
  }

  @MainActor
  func testQuickAccessActionSimulation() {
    let state = SnapzyOnboardingState()

    state.simulateQuickAccessAction("Copied")
    XCTAssertEqual(state.quickAccessFeedbackText, "Copied")
    XCTAssertTrue(state.completedChallenges.contains(.triggerQuickAction))
  }

  @MainActor
  func testSetChallengeToggle() {
    let state = SnapzyOnboardingState()

    state.setChallenge(.grantScreenRecording, completed: true)
    XCTAssertTrue(state.completedChallenges.contains(.grantScreenRecording))

    state.setChallenge(.grantScreenRecording, completed: false)
    XCTAssertFalse(state.completedChallenges.contains(.grantScreenRecording))
  }
}
