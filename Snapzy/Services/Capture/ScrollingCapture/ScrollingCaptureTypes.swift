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

  var isShowingLiveViewport: Bool {
    phase == .capturing
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
