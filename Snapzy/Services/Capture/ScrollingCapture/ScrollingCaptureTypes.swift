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
      return "Capturing"
    case .previewing:
      return "Live"
    case .committing:
      return "Processing"
    case .paused:
      return "Paused"
    case .finalizing:
      return "Finishing"
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
      return "Captured"
    case .liveSynced:
      return "Live"
    case .liveAhead:
      return "Syncing"
    case .pausedRecovery:
      return "Paused"
    case .finalizing:
      return "Finishing"
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
      return "Press Start Capture to begin."
    case .committedOnly:
      return "Showing the latest captured result."
    case .liveSynced:
      return "Live preview is up to date."
    case .liveAhead:
      return "Processing the latest capture…"
    case .pausedRecovery:
      return "Preview paused — scroll slowly so Snapzy can re-align."
    case .finalizing:
      return "Finishing up — saving your capture."
    case .saving:
      return "Saving your capture…"
    }
  }

  var selectionGuidance: ScrollingCaptureSelectionGuidance {
    let normalizedStatus = statusText.lowercased()

    switch phase {
    case .ready:
      if normalizedStatus.contains("release to lock") {
        return ScrollingCaptureSelectionGuidance(
          title: "Release to lock area",
          detail: "Keep only the scrolling content",
          tone: .active
        )
      }

      if normalizedStatus.contains("region updated") {
        return ScrollingCaptureSelectionGuidance(
          title: "Area updated",
          detail: "Keep only the scrolling content",
          tone: .active
        )
      }

      let readyDetail: String
      if autoScrollEnabled && !autoScrollAvailable {
        readyDetail = "Auto-scroll needs Accessibility permission"
      } else {
        readyDetail = "Then press Start Capture"
      }

      return ScrollingCaptureSelectionGuidance(
        title: "Frame only the scrolling content",
        detail: readyDetail,
        tone: .neutral
      )

    case .capturing:
      if normalizedStatus.contains("direction changed")
        || normalizedStatus.contains("mixed scroll directions")
      {
        return ScrollingCaptureSelectionGuidance(
          title: "Keep one direction",
          detail: "Reverse scrolling can break the stitch",
          tone: .warning
        )
      }

      if normalizedStatus.contains("no savable") {
        return ScrollingCaptureSelectionGuidance(
          title: "Keep capturing",
          detail: "Then try Done again",
          tone: .warning
        )
      }

      if normalizedStatus.contains("save failed") {
        return ScrollingCaptureSelectionGuidance(
          title: "Try Done again",
          detail: "Current result is still ready",
          tone: .warning
        )
      }

      if normalizedStatus.contains("height limit reached")
        || normalizedStatus.contains("output limit")
      {
        return ScrollingCaptureSelectionGuidance(
          title: "Height limit reached",
          detail: "Press Done to save",
          tone: .warning
        )
      }

      if normalizedStatus.contains("no new content detected")
        || normalizedStatus.contains("probably at the end")
      {
        return ScrollingCaptureSelectionGuidance(
          title: "Press Done to save",
          detail: "No new content was detected",
          tone: .active
        )
      }

      if normalizedStatus.contains("press done")
        || normalizedStatus.contains("reached the end")
      {
        return ScrollingCaptureSelectionGuidance(
          title: "Press Done to save",
          detail: "Current stitched result is ready",
          tone: .active
        )
      }

      if normalizedStatus.contains("continue scrolling manually") {
        return ScrollingCaptureSelectionGuidance(
          title: "Continue manually",
          detail: "Press Done when you're ready",
          tone: .active
        )
      }

      if normalizedStatus.contains("first frame") {
        return ScrollingCaptureSelectionGuidance(
          title: "Hold steady",
          detail: "Snapzy is locking the first frame",
          tone: .progress
        )
      }

      if normalizedStatus.contains("alignment paused")
        || normalizedStatus.contains("slow down")
      {
        return ScrollingCaptureSelectionGuidance(
          title: "Slow down",
          detail: "Keep one direction so Snapzy can re-align",
          tone: .warning
        )
      }

      if normalizedStatus.contains("couldn't align") {
        return ScrollingCaptureSelectionGuidance(
          title: "Keep a steadier pace",
          detail: "Stay on one direction",
          tone: .warning
        )
      }

      if normalizedStatus.contains("unable to capture")
        || normalizedStatus.contains("unable to render")
        || normalizedStatus.contains("preview refresh failed")
      {
        return ScrollingCaptureSelectionGuidance(
          title: "Preview needs recovery",
          detail: "Keep one direction or restart",
          tone: .warning
        )
      }

      if isAutoScrolling {
        return ScrollingCaptureSelectionGuidance(
          title: "Auto-scrolling",
          detail: "Press Done when the page ends",
          tone: .progress
        )
      }

      if normalizedStatus.contains("waiting for new content") {
        return ScrollingCaptureSelectionGuidance(
          title: "Keep scrolling down",
          detail: "One direction, steady pace",
          tone: .progress
        )
      }

      return ScrollingCaptureSelectionGuidance(
        title: "Scroll down steadily",
        detail: "Keep one direction for a clean stitch",
        tone: .progress
      )

    case .finalizing:
      if normalizedStatus.contains("height limit reached") {
        return ScrollingCaptureSelectionGuidance(
          title: "Saving current result",
          detail: "Height limit reached",
          tone: .active
        )
      }

      return ScrollingCaptureSelectionGuidance(
        title: "Locking current capture",
        detail: "Snapzy is sealing the stitched result",
        tone: .progress
      )

    case .saving:
      return ScrollingCaptureSelectionGuidance(
        title: "Saving long screenshot",
        detail: "Please wait",
        tone: .progress
      )
    }
  }
}
