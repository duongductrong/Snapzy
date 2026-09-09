//
//  SnapzyOnboardingState.swift
//  Snapzy
//
//  Observable state manager for interactive onboarding, fully compatible with macOS 13.0+.
//

import AppKit
import Combine
import SwiftUI

enum MockAnnotateTool: String, CaseIterable, Identifiable {
  case arrow
  case rect
  case counter
  case blur

  var id: String { rawValue }

  var icon: String {
    switch self {
    case .arrow: return "arrow.up.right"
    case .rect: return "rectangle"
    case .counter: return "1.circle.fill"
    case .blur: return "checkerboard.rectangle"
    }
  }

  var label: String {
    switch self {
    case .arrow: return "Arrow"
    case .rect: return "Rectangle"
    case .counter: return "Counter"
    case .blur: return "Blur"
    }
  }
}

struct MockAnnotateItem: Identifiable, Equatable {
  let id = UUID()
  let tool: MockAnnotateTool
  var position: CGPoint
}

enum Step1WorkflowStage: Equatable {
  case readyToCapture
  case selectingArea
  case quickAccessFloating
  case annotateWindowOpen
}

enum Step2WorkflowStage: Equatable {
  case readyToRecord
  case prerecordArea
  case recordingActive
  case videoQuickAccess
  case videoEditorOpen
}

@MainActor
final class SnapzyOnboardingState: ObservableObject {
  @Published var currentStep: SnapzyOnboardingStep = .meetSnapzy
  @Published var completedSteps: Set<SnapzyOnboardingStep> = []
  @Published var completedChallenges: Set<SnapzyOnboardingChallenge> = []

  // Step 1: Capture > Quick Access > Annotate Lifecycle State
  @Published var step1Stage: Step1WorkflowStage = .readyToCapture
  @Published var screenFlashOpacity: Double = 0
  @Published var hasAreaSelection: Bool = false
  @Published var selectedTool: MockAnnotateTool? = nil
  @Published var annotationItems: [MockAnnotateItem] = []
  @Published var isSimulatingSelection: Bool = false

  // Step 2: Screen Recording & Video Editor Lifecycle State
  @Published var step2Stage: Step2WorkflowStage = .readyToRecord
  @Published var recordingSeconds: Int = 0
  @Published var isRecordingTimerRunning: Bool = false
  @Published var isPlayingPreview: Bool = false
  @Published var isQuickAccessHovered: Bool = false
  @Published var quickAccessFeedbackText: String? = nil
  @Published var isCardPinned: Bool = false
  private var recordingTimer: Timer? = nil

  // Step 3: Shortcuts & Config Mock State
  @Published var hasConflict: Bool = true
  @Published var hasFullscreenConflict: Bool = true
  @Published var hasAreaConflict: Bool = true
  @Published var hasRecordingConflict: Bool = true
  @Published var isCheckingConflict: Bool = false
  @Published var isConfigGranted: Bool = false
  @Published var diagnosticsOptIn: Bool = true

  var isCurrentStepComplete: Bool {
    let required = currentStep.challenges
    return required.allSatisfy { completedChallenges.contains($0) }
  }

  var canGoBack: Bool {
    currentStep.stepNumber > 1
  }

  var canGoForward: Bool {
    currentStep.stepNumber < SnapzyOnboardingStep.allCases.count
  }

  func markCurrentStepVisited() {
    withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
      _ = completedSteps.insert(currentStep)
    }
  }

  func completeChallenge(_ challenge: SnapzyOnboardingChallenge) {
    withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
      completedChallenges.insert(challenge)
      if isCurrentStepComplete {
        completedSteps.insert(currentStep)
      }
    }
  }

  func setChallenge(_ challenge: SnapzyOnboardingChallenge, completed: Bool) {
    guard completedChallenges.contains(challenge) != completed else { return }
    withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
      if completed {
        completedChallenges.insert(challenge)
        if isCurrentStepComplete { completedSteps.insert(currentStep) }
      } else {
        completedChallenges.remove(challenge)
        completedSteps.remove(currentStep)
      }
    }
  }

  func nextStep() {
    guard let currentIndex = SnapzyOnboardingStep.allCases.firstIndex(of: currentStep),
          currentIndex + 1 < SnapzyOnboardingStep.allCases.count else { return }
    let next = SnapzyOnboardingStep.allCases[currentIndex + 1]
    transition(to: next)
  }

  func previousStep() {
    guard let currentIndex = SnapzyOnboardingStep.allCases.firstIndex(of: currentStep),
          currentIndex > 0 else { return }
    let prev = SnapzyOnboardingStep.allCases[currentIndex - 1]
    transition(to: prev)
  }

  func transition(to step: SnapzyOnboardingStep) {
    withAnimation(SnapzyMotionPreferences.shared.spec(.morph).animation) {
      currentStep = step
      resetStateForStep(step)
    }
  }

  private func resetStateForStep(_ step: SnapzyOnboardingStep) {
    switch step {
    case .meetSnapzy:
      step1Stage = .readyToCapture
      screenFlashOpacity = 0
      hasAreaSelection = false
      selectedTool = nil
      annotationItems = []
    case .quickAccess:
      resetStep2Flow()
    case .shortcuts:
      hasFullscreenConflict = true
      hasAreaConflict = true
      hasRecordingConflict = true
      hasConflict = true
    case .permissions:
      break
    }
  }

  // MARK: - Interactive Simulation Actions

  func simulateAreaCapture() {
    withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
      step1Stage = .selectingArea
      hasAreaSelection = true
      completeChallenge(.selectArea)
    }
  }

  func completeCaptureToQuickAccess() {
    withAnimation(.easeOut(duration: 0.12)) {
      screenFlashOpacity = 0.65
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
      withAnimation(SnapzyMotionPreferences.shared.spec(.morph).animation) {
        self?.screenFlashOpacity = 0
        self?.step1Stage = .quickAccessFloating
        self?.completeChallenge(.captureToQuickAccess)
      }
    }
  }

  func openAnnotateFromQuickAccess() {
    withAnimation(SnapzyMotionPreferences.shared.spec(.morph).animation) {
      step1Stage = .annotateWindowOpen
      completeChallenge(.openAnnotateWindow)
    }
  }

  func resetStep1Flow() {
    withAnimation(SnapzyMotionPreferences.shared.spec(.morph).animation) {
      step1Stage = .readyToCapture
      hasAreaSelection = false
      selectedTool = nil
      annotationItems = []
    }
  }

  func selectAnnotationTool(_ tool: MockAnnotateTool) {
    withAnimation(SnapzyMotionPreferences.shared.spec(.hover).animation) {
      selectedTool = tool
      if !annotationItems.contains(where: { $0.tool == tool }) {
        let defaultPosition: CGPoint
        switch tool {
        case .arrow: defaultPosition = CGPoint(x: 220, y: 150)
        case .rect: defaultPosition = CGPoint(x: 140, y: 110)
        case .counter: defaultPosition = CGPoint(x: 80, y: 80)
        case .blur: defaultPosition = CGPoint(x: 180, y: 200)
        }
        annotationItems.append(MockAnnotateItem(tool: tool, position: defaultPosition))
      }
      completeChallenge(.addAnnotation)
    }
  }

  func simulateQuickAccessAction(_ actionName: String) {
    withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
      quickAccessFeedbackText = actionName
      completeChallenge(.triggerQuickAction)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
      withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
        self?.quickAccessFeedbackText = nil
      }
    }
  }

  // MARK: - Step 2: Screen Recording Simulation Actions

  func simulateStartPrerecord() {
    withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
      step2Stage = .prerecordArea
      completeChallenge(.selectRecordArea)
    }
  }

  func simulateStartRecording() {
    recordingTimer?.invalidate()
    recordingTimer = nil
    recordingSeconds = 0
    isRecordingTimerRunning = true

    withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
      step2Stage = .recordingActive
    }

    recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
      guard let self else {
        timer.invalidate()
        return
      }
      Task { @MainActor in
        if self.recordingSeconds < 3 {
          self.recordingSeconds += 1
        }
        if self.recordingSeconds >= 3 {
          timer.invalidate()
          self.simulateFinishRecording()
        }
      }
    }
  }

  func simulateFinishRecording() {
    recordingTimer?.invalidate()
    recordingTimer = nil
    isRecordingTimerRunning = false

    withAnimation(.easeOut(duration: 0.12)) {
      screenFlashOpacity = 0.65
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
      withAnimation(SnapzyMotionPreferences.shared.spec(.morph).animation) {
        self?.screenFlashOpacity = 0
        self?.step2Stage = .videoQuickAccess
        self?.completeChallenge(.recordVideo3s)
      }
    }
  }

  func openVideoEditorFromQuickAccess() {
    withAnimation(SnapzyMotionPreferences.shared.spec(.morph).animation) {
      step2Stage = .videoEditorOpen
      completeChallenge(.openVideoEditor)
    }
  }

  func resetStep2Flow() {
    recordingTimer?.invalidate()
    recordingTimer = nil
    isRecordingTimerRunning = false
    recordingSeconds = 0
    isPlayingPreview = false
    isQuickAccessHovered = false
    quickAccessFeedbackText = nil
    isCardPinned = false

    withAnimation(SnapzyMotionPreferences.shared.spec(.morph).animation) {
      step2Stage = .readyToRecord
    }
  }

  // MARK: - Step 3: Shortcuts & Conflict Resolution

  func updateShortcutConflicts(fullscreenConflict: Bool, areaConflict: Bool, recordingConflict: Bool) {
    withAnimation(SnapzyMotionPreferences.shared.spec(.settle).animation) {
      hasFullscreenConflict = fullscreenConflict
      hasAreaConflict = areaConflict
      hasRecordingConflict = recordingConflict
      hasConflict = fullscreenConflict || areaConflict || recordingConflict
      if !hasConflict {
        completeChallenge(.checkShortcuts)
      } else {
        completedChallenges.remove(.checkShortcuts)
        completedSteps.remove(.shortcuts)
      }
    }
  }

  func resolveShortcutConflicts() {
    updateShortcutConflicts(fullscreenConflict: false, areaConflict: false, recordingConflict: false)
  }
}
