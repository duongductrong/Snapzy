//
//  SnapzyOnboardingStateTests.swift
//  SnapzyTests
//
//  Unit tests for interactive onboarding state management and Step 1 core workflow.
//

import XCTest
@testable import Snapzy

final class SnapzyOnboardingStateTests: XCTestCase {
  override func setUp() {
    super.setUp()
    UserDefaults.standard.removeObject(forKey: PreferencesKeys.onboardingActiveStep)
  }

  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: PreferencesKeys.onboardingActiveStep)
    super.tearDown()
  }

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

  @MainActor
  func testStep2ScreenRecordingWorkflow() {
    let state = SnapzyOnboardingState()
    state.transition(to: .quickAccess)
    XCTAssertEqual(state.currentStep, .quickAccess)
    XCTAssertEqual(state.step2Stage, .readyToRecord)
    XCTAssertFalse(state.isCurrentStepComplete)

    // 1. Trigger ⇧⌘5 simulation
    state.simulateStartPrerecord()
    XCTAssertEqual(state.step2Stage, .prerecordArea)
    XCTAssertTrue(state.completedChallenges.contains(.selectRecordArea))
    XCTAssertFalse(state.isCurrentStepComplete)

    // 2. Start recording (active stage)
    state.simulateStartRecording()
    XCTAssertEqual(state.step2Stage, .recordingActive)
    XCTAssertTrue(state.isRecordingTimerRunning)

    // 3. Finish recording -> Video Quick Access Card
    state.simulateFinishRecording()
    let exp = expectation(description: "Wait for video quick access transition")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      XCTAssertEqual(state.step2Stage, .videoQuickAccess)
      XCTAssertTrue(state.completedChallenges.contains(.recordVideo3s))
      XCTAssertFalse(state.isCurrentStepComplete)

      // 4. Open Video Editor from Quick Access Card
      state.openVideoEditorFromQuickAccess()
      XCTAssertEqual(state.step2Stage, .videoEditorOpen)
      XCTAssertTrue(state.completedChallenges.contains(.openVideoEditor))
      XCTAssertTrue(state.isCurrentStepComplete)
      XCTAssertTrue(state.completedSteps.contains(.quickAccess))

      // 5. Reset Step 2 flow
      state.resetStep2Flow()
      XCTAssertEqual(state.step2Stage, .readyToRecord)
      XCTAssertEqual(state.recordingSeconds, 0)
      XCTAssertFalse(state.isRecordingTimerRunning)

      exp.fulfill()
    }

    waitForExpectations(timeout: 1.0)
  }

  @MainActor
  func testStep3ShortcutConflictResolution() {
    let state = SnapzyOnboardingState()
    state.transition(to: .shortcuts)
    XCTAssertEqual(state.currentStep, .shortcuts)
    XCTAssertTrue(state.hasConflict)
    XCTAssertTrue(state.hasFullscreenConflict)
    XCTAssertTrue(state.hasAreaConflict)
    XCTAssertTrue(state.hasRecordingConflict)
    XCTAssertFalse(state.isCurrentStepComplete)

    // 1. Resolve fullscreen conflict only
    state.updateShortcutConflicts(fullscreenConflict: false, areaConflict: true, recordingConflict: true)
    XCTAssertTrue(state.hasConflict)
    XCTAssertFalse(state.hasFullscreenConflict)
    XCTAssertTrue(state.hasAreaConflict)
    XCTAssertTrue(state.hasRecordingConflict)
    XCTAssertFalse(state.isCurrentStepComplete)

    // 2. Resolve area conflict too (recording still active)
    state.updateShortcutConflicts(fullscreenConflict: false, areaConflict: false, recordingConflict: true)
    XCTAssertTrue(state.hasConflict)
    XCTAssertFalse(state.hasFullscreenConflict)
    XCTAssertFalse(state.hasAreaConflict)
    XCTAssertTrue(state.hasRecordingConflict)
    XCTAssertFalse(state.isCurrentStepComplete)

    // 3. Resolve recording conflict too -> All resolved
    state.updateShortcutConflicts(fullscreenConflict: false, areaConflict: false, recordingConflict: false)
    XCTAssertFalse(state.hasConflict)
    XCTAssertFalse(state.hasFullscreenConflict)
    XCTAssertFalse(state.hasAreaConflict)
    XCTAssertFalse(state.hasRecordingConflict)
    XCTAssertTrue(state.completedChallenges.contains(.checkShortcuts))
    XCTAssertTrue(state.isCurrentStepComplete)
    XCTAssertTrue(state.completedSteps.contains(.shortcuts))

    // 4. Reactivate a conflict -> marks step incomplete
    state.updateShortcutConflicts(fullscreenConflict: true, areaConflict: false, recordingConflict: false)
    XCTAssertTrue(state.hasConflict)
    XCTAssertFalse(state.isCurrentStepComplete)
    XCTAssertFalse(state.completedChallenges.contains(.checkShortcuts))

    // 5. Resolve all at once via helper
    state.resolveShortcutConflicts()
    XCTAssertFalse(state.hasConflict)
    XCTAssertFalse(state.hasFullscreenConflict)
    XCTAssertFalse(state.hasAreaConflict)
    XCTAssertFalse(state.hasRecordingConflict)
    XCTAssertTrue(state.isCurrentStepComplete)
  }

  @MainActor
  func testStepStateRestorationFromUserDefaults() {
    let defaults = UserDefaults.standard
    let original = defaults.string(forKey: PreferencesKeys.onboardingActiveStep)
    defer {
      if let original {
        defaults.set(original, forKey: PreferencesKeys.onboardingActiveStep)
      } else {
        defaults.removeObject(forKey: PreferencesKeys.onboardingActiveStep)
      }
    }

    defaults.set(SnapzyOnboardingStep.permissions.rawValue, forKey: PreferencesKeys.onboardingActiveStep)
    let restoredState = SnapzyOnboardingState()
    XCTAssertEqual(restoredState.currentStep, .permissions)

    restoredState.transition(to: .shortcuts)
    XCTAssertEqual(
      defaults.string(forKey: PreferencesKeys.onboardingActiveStep),
      SnapzyOnboardingStep.shortcuts.rawValue
    )
  }

  @MainActor
  func testStep4PermissionChallenges() {
    let state = SnapzyOnboardingState()
    state.transition(to: .permissions)
    XCTAssertEqual(state.currentStep, .permissions)
    XCTAssertFalse(state.isCurrentStepComplete)

    state.setChallenge(.grantScreenRecording, completed: true)
    XCTAssertTrue(state.completedChallenges.contains(.grantScreenRecording))
    XCTAssertFalse(state.isCurrentStepComplete)

    state.setChallenge(.grantSaveFolder, completed: true)
    XCTAssertTrue(state.completedChallenges.contains(.grantSaveFolder))
    XCTAssertTrue(state.isCurrentStepComplete)
    XCTAssertTrue(state.completedSteps.contains(.permissions))

    state.setChallenge(.grantScreenRecording, completed: false)
    XCTAssertFalse(state.isCurrentStepComplete)
    XCTAssertFalse(state.completedSteps.contains(.permissions))
  }
}
