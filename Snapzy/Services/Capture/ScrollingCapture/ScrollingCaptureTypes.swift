//
//  ScrollingCaptureTypes.swift
//  Snapzy
//
//  Shared state and feature toggles for scrolling capture.
//

import AppKit
import ApplicationServices
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
      return "Ready"
    case .streaming:
      return "Streaming"
    case .previewing:
      return "Preview Live"
    case .committing:
      return "Syncing Capture"
    case .paused:
      return "Needs Recovery"
    case .finalizing:
      return "Finalizing"
    case .saving:
      return "Saving"
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
      return "Stitched"
    case .liveSynced:
      return "Live Synced"
    case .liveAhead:
      return "Live Ahead"
    case .pausedRecovery:
      return "Recovery"
    case .finalizing:
      return "Finalizing"
    case .saving:
      return "Saving"
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

enum ScrollingCaptureFeature {
  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: PreferencesKeys.scrollingCaptureEnabled) as? Bool ?? false
  }

  static var defaultAutoScrollEnabled: Bool {
    UserDefaults.standard.object(forKey: PreferencesKeys.scrollingCaptureAutoScrollEnabled) as? Bool ?? false
  }

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
  @Published var statusText =
    "Adjust the region so only the moving content stays inside, then press Start Capture. Press Esc to cancel."
  @Published var previewCaption = "Start Capture to lock the first frame"
  @Published var previewImage: CGImage?
  @Published var livePreviewImage: CGImage?
  @Published var isUsingLivePreview = false
  @Published var previewTruthState: ScrollingCapturePreviewTruthState = .ready
  @Published var previewCommitLagMs = 0
  @Published var pendingCommitCount = 0
  @Published var acceptedFrameCount = 0
  @Published var stitchedPixelHeight = 0
  @Published var autoScrollEnabled: Bool
  @Published var autoScrollAvailable: Bool
  @Published var autoScrollStatusText: String
  @Published var isAutoScrolling = false

  init(selectedRect: CGRect) {
    let autoScrollAvailable = AXIsProcessTrusted()
    self.selectedRect = selectedRect
    self.autoScrollEnabled = ScrollingCaptureFeature.defaultAutoScrollEnabled
    self.autoScrollAvailable = autoScrollAvailable
    self.autoScrollStatusText = autoScrollAvailable
      ? "Auto-scroll can start after the first frame is locked."
      : "Auto-scroll needs Accessibility permission."
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
    if isShowingLiveViewport, let livePreviewImage {
      return livePreviewImage
    }

    return previewImage ?? livePreviewImage
  }

  var previewTruthDescription: String {
    switch previewTruthState {
    case .ready:
      return "Preview will switch to the live viewport after Start Capture."
    case .committedOnly:
      return "Showing the latest stitched result."
    case .liveSynced:
      return "Showing the live viewport. The stitched result is in sync."
    case .liveAhead:
      if pendingCommitCount > 1 {
        return
          "Showing the live viewport while Snapzy catches up \(pendingCommitCount) pending commits."
      }
      if previewCommitLagMs > 0 {
        return
          "Showing the live viewport while Snapzy syncs the stitched result (\(previewCommitLagMs) ms lag)."
      }
      return "Showing the live viewport while Snapzy syncs the stitched result."
    case .pausedRecovery:
      return "Preview is frozen to avoid mismatched output while Snapzy recovers alignment."
    case .finalizing:
      return "Live capture is locked while Snapzy seals the final stitched result."
    case .saving:
      return "Saving the stitched image."
    }
  }
}
