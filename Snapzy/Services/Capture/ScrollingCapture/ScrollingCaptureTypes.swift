//
//  ScrollingCaptureTypes.swift
//  Snapzy
//
//  Shared state and configuration for scrolling capture.
//

import AppKit
import Combine
import Foundation

enum ScrollingCapturePhase {
  case ready
  case capturing
  case finalizing
  case saving
}

enum ScrollingCaptureRuntimeState {
  case ready
  case streaming
  case previewing
  case committing
  case paused
  case finalizing
  case saving

  var label: String {
    switch self {
    case .ready:
      return L10n.ScrollingCapture.runtimeReady
    case .streaming:
      return L10n.ScrollingCapture.runtimeCapturing
    case .previewing:
      return L10n.ScrollingCapture.runtimeLive
    case .committing:
      return L10n.ScrollingCapture.runtimeProcessing
    case .paused:
      return L10n.ScrollingCapture.runtimePaused
    case .finalizing:
      return L10n.ScrollingCapture.runtimeFinishing
    case .saving:
      return L10n.ScrollingCapture.runtimeSaving
    }
  }
}

enum ScrollingCapturePreviewTruthState: Equatable {
  case ready
  case committedOnly
  case liveSynced
  case liveAhead
  case pausedRecovery
  case finalizing
  case saving

  var badgeLabel: String? {
    switch self {
    case .ready:
      return nil
    case .committedOnly:
      return L10n.ScrollingCapture.badgeCaptured
    case .liveSynced:
      return L10n.ScrollingCapture.badgeLive
    case .liveAhead:
      return L10n.ScrollingCapture.badgeSyncing
    case .pausedRecovery:
      return L10n.ScrollingCapture.badgePaused
    case .finalizing:
      return L10n.ScrollingCapture.badgeFinishing
    case .saving:
      return L10n.ScrollingCapture.badgeSaving
    }
  }

  var prefersLiveViewport: Bool {
    switch self {
    case .liveSynced, .liveAhead:
      return true
    default:
      return false
    }
  }
}

enum ScrollingCaptureSelectionGuidanceTone {
  case neutral
  case active
  case warning
  case progress
}

struct ScrollingCaptureSelectionGuidance {
  let title: String
  let detail: String?
  let tone: ScrollingCaptureSelectionGuidanceTone
}

enum ScrollingCaptureSelectionGuidanceKind {
  case frameOnlyScrollingContent
  case releaseToLockArea
  case areaUpdated
  case keepOneDirection
  case keepCapturing
  case tryDoneAgain
  case placeMouseInsideSelection
  case heightLimitReached
  case pressDoneNoNewContent
  case pressDoneCurrentResultReady
  case continueManually
  case holdSteady
  case slowDown
  case keepSteadierPace
  case previewNeedsRecovery
  case keepScrollingDown
  case scrollDownSteadily
  case savingCurrentResult
  case lockingCurrentCapture
  case savingLongScreenshot

  var guidance: ScrollingCaptureSelectionGuidance {
    switch self {
    case .frameOnlyScrollingContent:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidanceFrameOnlyScrollingContent,
        detail: L10n.ScrollingCapture.guidanceThenPressStartCapture,
        tone: .neutral
      )
    case .releaseToLockArea:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidanceReleaseToLockArea,
        detail: L10n.ScrollingCapture.guidanceKeepOnlyScrollingContent,
        tone: .active
      )
    case .areaUpdated:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidanceAreaUpdated,
        detail: L10n.ScrollingCapture.guidanceKeepOnlyScrollingContent,
        tone: .active
      )
    case .keepOneDirection:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidanceKeepOneDirection,
        detail: L10n.ScrollingCapture.guidanceReverseScrollingCanBreakStitch,
        tone: .warning
      )
    case .keepCapturing:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidanceKeepCapturing,
        detail: L10n.ScrollingCapture.guidanceThenTryDoneAgain,
        tone: .warning
      )
    case .tryDoneAgain:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidanceTryDoneAgain,
        detail: L10n.ScrollingCapture.guidanceCurrentResultStillReady,
        tone: .warning
      )
    case .placeMouseInsideSelection:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidancePlaceMouseInsideSelection,
        detail: L10n.ScrollingCapture.guidanceReturnMouseInsideSelection,
        tone: .warning
      )
    case .heightLimitReached:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidanceHeightLimitReached,
        detail: L10n.ScrollingCapture.guidancePressDoneToSave,
        tone: .warning
      )
    case .pressDoneNoNewContent:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidancePressDoneToSave,
        detail: L10n.ScrollingCapture.guidanceNoNewContentDetected,
        tone: .active
      )
    case .pressDoneCurrentResultReady:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidancePressDoneToSave,
        detail: L10n.ScrollingCapture.guidanceCurrentStitchedResultReady,
        tone: .active
      )
    case .continueManually:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidanceContinueManually,
        detail: L10n.ScrollingCapture.guidancePressDoneWhenReady,
        tone: .active
      )
    case .holdSteady:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidanceHoldSteady,
        detail: L10n.ScrollingCapture.guidanceSnapzyLockingFirstFrame,
        tone: .progress
      )
    case .slowDown:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidanceSlowDown,
        detail: L10n.ScrollingCapture.guidanceKeepOneDirectionSoSnapzyCanRealign,
        tone: .warning
      )
    case .keepSteadierPace:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidanceKeepSteadierPace,
        detail: L10n.ScrollingCapture.guidanceStayOnOneDirection,
        tone: .warning
      )
    case .previewNeedsRecovery:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidancePreviewNeedsRecovery,
        detail: L10n.ScrollingCapture.guidanceKeepOneDirectionOrRestart,
        tone: .warning
      )
    case .keepScrollingDown:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidanceKeepScrollingDown,
        detail: L10n.ScrollingCapture.guidanceOneDirectionSteadyPace,
        tone: .progress
      )
    case .scrollDownSteadily:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidanceScrollDownSteadily,
        detail: L10n.ScrollingCapture.guidanceKeepOneDirectionForCleanStitch,
        tone: .progress
      )
    case .savingCurrentResult:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidanceSavingCurrentResult,
        detail: L10n.ScrollingCapture.guidanceHeightLimitReached,
        tone: .active
      )
    case .lockingCurrentCapture:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidanceLockingCurrentCapture,
        detail: L10n.ScrollingCapture.guidanceSnapzySealingStitchedResult,
        tone: .progress
      )
    case .savingLongScreenshot:
      return ScrollingCaptureSelectionGuidance(
        title: L10n.ScrollingCapture.guidanceSavingLongScreenshot,
        detail: L10n.ScrollingCapture.guidancePleaseWait,
        tone: .progress
      )
    }
  }
}

enum ScrollingCaptureConfiguration {
  static var showHints: Bool {
    UserDefaults.standard.object(forKey: PreferencesKeys.scrollingCaptureShowHints) as? Bool ?? true
  }

  static let maxOutputHeight = 32_768
}

enum ScrollingCaptureAutoScrollStitchAction: Equatable {
  case keepScrolling
  case retryStep
  case retryCommit
  case stopScrolling
  case finishCapture
}

enum ScrollingCaptureAutoScrollPhase: Equatable {
  case idle
  case emittingBoundedStep
  case waitingForSettle
  case requestingCommit
  case waitingForCommitResult
  case decidingNextAction
}

enum ScrollingCaptureAutoScrollStopReason: Equatable {
  case none
  case userToggle
  case finishRequested
  case cancelRequested
}

enum ScrollingCaptureAutoScrollPolicy {
  struct StepPlan: Equatable {
    let tickCount: Int
    let postedDistancePoints: CGFloat
    let tickIntervalNanoseconds: UInt64
    let settleNanoseconds: UInt64
  }

  static let hoverPadding: CGFloat = 16
  static let alignmentFailureStopThreshold = 3
  static let noMovementFinishThreshold = 2
  static let wheelDeltaY: Int32 = -3
  static let tickIntervalNanoseconds: UInt64 = 16_000_000
  static let settleNanoseconds: UInt64 = 120_000_000
  static let retrySettleNanoseconds: UInt64 = 180_000_000
  static let pausedIntervalNanoseconds: UInt64 = 150_000_000
  static let freshFrameTimeoutNanoseconds: UInt64 = 600_000_000
  static let targetViewportFraction: CGFloat = 0.18
  static let maxSafeViewportFraction: CGFloat = 0.26
  static let minStepPoints: CGFloat = 36
  static let maxStepPoints: CGFloat = 90

  static func canToggle(
    phase: ScrollingCapturePhase,
    acceptedFrameCount: Int,
    isAutoScrolling: Bool
  ) -> Bool {
    switch phase {
    case .capturing:
      return isAutoScrolling || acceptedFrameCount > 0
    case .ready, .finalizing, .saving:
      return false
    }
  }

  static func scrollTargetPoint(mouseLocation: CGPoint, selectedRect: CGRect) -> CGPoint? {
    let hoverRect = selectedRect.insetBy(dx: -hoverPadding, dy: -hoverPadding)
    guard hoverRect.contains(mouseLocation) else { return nil }
    // Padding keeps the pause forgiving without sending input to a neighboring pane.
    return CGPoint(
      x: min(max(mouseLocation.x, selectedRect.minX + 1), selectedRect.maxX - 1),
      y: min(max(mouseLocation.y, selectedRect.minY + 1), selectedRect.maxY - 1)
    )
  }

  static func stepDistancePoints(regionHeight: CGFloat) -> CGFloat {
    let height = max(1, regionHeight)
    let preferred = height * targetViewportFraction
    let maxSafe = height * maxSafeViewportFraction
    let clampedPreferred = min(maxStepPoints, max(minStepPoints, preferred))
    return min(clampedPreferred, max(1, maxSafe))
  }

  static func tickCount(forStepDistancePoints step: CGFloat) -> Int {
    let tickMagnitude = CGFloat(abs(wheelDeltaY))
    guard tickMagnitude > 0 else { return 1 }
    return max(1, Int((step / tickMagnitude).rounded(.down)))
  }

  static func stepPlan(regionHeight: CGFloat, isRetry: Bool) -> StepPlan {
    let fullStep = stepDistancePoints(regionHeight: regionHeight)
    let step = isRetry ? max(1, fullStep * 0.55) : fullStep
    let ticks = tickCount(forStepDistancePoints: step)
    return StepPlan(
      tickCount: ticks,
      postedDistancePoints: CGFloat(ticks) * CGFloat(abs(wheelDeltaY)),
      tickIntervalNanoseconds: tickIntervalNanoseconds,
      settleNanoseconds: isRetry ? retrySettleNanoseconds : settleNanoseconds
    )
  }

  static func expectedSignedDeltaPixels(
    postedDistancePoints: CGFloat,
    observedDistancePoints: CGFloat,
    scaleFactor: CGFloat
  ) -> Int {
    let scale = max(scaleFactor, 1)
    let observedPixels = Int(round(observedDistancePoints * scale))
    if abs(observedPixels) > 2 {
      return observedPixels
    }

    let sign: CGFloat = wheelDeltaY < 0 ? -1 : 1
    return Int(round(abs(postedDistancePoints) * scale * sign))
  }

  static func isCommitFrameEligible(
    capturedAt: TimeInterval,
    lastSyntheticEventAt: TimeInterval?
  ) -> Bool {
    guard let lastSyntheticEventAt else { return true }
    return capturedAt > lastSyntheticEventAt
  }

  static func stitchAction(
    for update: ScrollingCaptureStitchUpdate,
    consecutiveNoMovementCount: Int = 0
  ) -> ScrollingCaptureAutoScrollStitchAction {
    switch update.outcome {
    case .reachedHeightLimit:
      return .finishCapture
    case .ignoredAlignmentFailed where update.matchFailureCount >= alignmentFailureStopThreshold:
      return .stopScrolling
    case .ignoredAlignmentFailed:
      return .retryCommit
    case .ignoredNoMovement:
      if update.likelyReachedBoundary, consecutiveNoMovementCount >= noMovementFinishThreshold {
        return .finishCapture
      }
      return .retryStep
    case .initialized, .appended:
      return .keepScrolling
    }
  }

  static func actionForMissingStitchUpdate(
    consecutiveFailureCount: Int
  ) -> ScrollingCaptureAutoScrollStitchAction {
    consecutiveFailureCount >= alignmentFailureStopThreshold ? .stopScrolling : .retryCommit
  }

  static func shouldTakeSmallerFollowUpStep(
    acceptedDeltaPixels: Int,
    expectedSignedDeltaPixels: Int?
  ) -> Bool {
    guard let expected = expectedSignedDeltaPixels.map(abs), expected > 24 else { return false }
    return acceptedDeltaPixels < max(18, expected / 2)
  }
}

@MainActor
final class ScrollingCaptureSessionModel: ObservableObject {
  @Published var selectedRect: CGRect
  @Published var phase: ScrollingCapturePhase = .ready
  @Published var runtimeState: ScrollingCaptureRuntimeState = .ready
  @Published var statusText = L10n.ScrollingCaptureStatus.adjustRegion
  @Published var guidanceKind: ScrollingCaptureSelectionGuidanceKind = .frameOnlyScrollingContent
  @Published var previewCaption = L10n.ScrollingCapture.captionStartCaptureToLockFirstFrame
  @Published var previewImage: CGImage?
  @Published var livePreviewImage: CGImage?
  @Published var isUsingLivePreview = false
  @Published var previewTruthState: ScrollingCapturePreviewTruthState = .ready
  @Published var previewCommitLagMs = 0
  @Published var pendingCommitCount = 0
  @Published var acceptedFrameCount = 0
  @Published var stitchedPixelHeight = 0
  @Published var isAutoScrolling = false
  @Published var isAutoScrollStopping = false

  init(selectedRect: CGRect) {
    self.selectedRect = selectedRect
  }

  func setStatus(_ text: String, guidance: ScrollingCaptureSelectionGuidanceKind) {
    statusText = text
    guidanceKind = guidance
  }

  var selectionSummary: String {
    "\(Int(selectedRect.width)) x \(Int(selectedRect.height))"
  }

  var isInteractionLocked: Bool {
    phase == .finalizing || phase == .saving
  }

  var canStartCapture: Bool {
    phase == .ready && !isInteractionLocked
  }

  var canCancelSession: Bool {
    !isInteractionLocked
  }

  var canFinishCapture: Bool {
    phase == .capturing && !isInteractionLocked
  }

  var canToggleAutoScroll: Bool {
    !isAutoScrollStopping && ScrollingCaptureAutoScrollPolicy.canToggle(
      phase: phase,
      acceptedFrameCount: acceptedFrameCount,
      isAutoScrolling: isAutoScrolling
    )
  }

  var isShowingLiveViewport: Bool {
    phase == .capturing
      && previewImage == nil
      && previewTruthState.prefersLiveViewport
      && livePreviewImage != nil
  }

  var activePreviewImage: CGImage? {
    previewImage ?? livePreviewImage
  }

  var previewTruthDescription: String {
    switch previewTruthState {
    case .ready:
      return L10n.ScrollingCapture.previewPressStartToBegin
    case .committedOnly:
      return L10n.ScrollingCapture.previewShowingLatestStitchedCapture
    case .liveSynced:
      return L10n.ScrollingCapture.previewMatchesStitchedCapture
    case .liveAhead:
      return L10n.ScrollingCapture.previewShowingLatestWhileLockingNewerContent
    case .pausedRecovery:
      return L10n.ScrollingCapture.previewPausedScrollSlowly
    case .finalizing:
      return L10n.ScrollingCapture.previewFinishingSavingCapture
    case .saving:
      return L10n.ScrollingCapture.previewSavingCapture
    }
  }

  var selectionGuidance: ScrollingCaptureSelectionGuidance {
    guidanceKind.guidance
  }
}
