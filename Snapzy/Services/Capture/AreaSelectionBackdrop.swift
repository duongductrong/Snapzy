//
//  AreaSelectionBackdrop.swift
//  Snapzy
//
//  Shared models for area selection backdrops and results.
//

import CoreGraphics
import Foundation

typealias AreaSelectionResultCompletion = (AreaSelectionResult?) -> Void

nonisolated enum AreaSelectionInteractionMode {
  case manualRegion
  case applicationWindow
  /// Recording only: the pointer highlights the display under it and a click selects that
  /// whole display. Entered and left with Enter.
  case fullDisplay
}

nonisolated struct AreaSelectionBackdrop {
  let displayID: CGDirectDisplayID
  let image: CGImage
  let scaleFactor: CGFloat
  let isVisible: Bool

  init(displayID: CGDirectDisplayID, image: CGImage, scaleFactor: CGFloat, isVisible: Bool = true) {
    self.displayID = displayID
    self.image = image
    self.scaleFactor = scaleFactor
    self.isVisible = isVisible
  }
}

nonisolated enum WindowCaptureTargetKind: String, Sendable {
  case normal
  case menuBarPopover
}

nonisolated struct WindowCaptureTarget: Equatable, Sendable {
  let windowID: CGWindowID
  let frame: CGRect
  let displayID: CGDirectDisplayID
  let title: String?
  let bundleIdentifier: String?
  let ownerPID: Int32?

  let kind: WindowCaptureTargetKind

  init(
    windowID: CGWindowID,
    frame: CGRect,
    displayID: CGDirectDisplayID,
    title: String?,
    bundleIdentifier: String?,
    ownerPID: Int32?,
    kind: WindowCaptureTargetKind = .normal
  ) {
    self.windowID = windowID
    self.frame = frame
    self.displayID = displayID
    self.title = title
    self.bundleIdentifier = bundleIdentifier
    self.ownerPID = ownerPID
    self.kind = kind
  }
}

/// A menu-bar popover captured synchronously when the capture shortcut is received.
///
/// Menu extras may close as soon as Snapzy presents its selection UI. This preserves only
/// that already-visible popover's pixels; it is not a frozen-screen session.
nonisolated struct ImmediateMenuBarPopoverCapture {
  let target: WindowCaptureTarget
  let image: CGImage
  let scaleFactor: CGFloat
}

/// A Quick Look preview captured before Snapzy presents selection UI.
///
/// Quick Look is rendered by `QuickLookUIService` as a transient WindowServer
/// window. ScreenCaptureKit can enumerate that window but may report it as
/// off-screen, so the preview must be retained from a display snapshot and
/// restored over the filtered capture.
nonisolated struct ImmediateQuickLookCapture {
  let windowID: CGWindowID
  let displayID: CGDirectDisplayID
  let frame: CGRect
  let image: CGImage
  let scaleFactor: CGFloat
}

nonisolated enum AreaSelectionTarget: Equatable {
  case rect(CGRect)
  case window(WindowCaptureTarget)
  /// A whole display, picked in the recording overlay. `frame` is the display's `NSScreen.frame`
  /// in the same global AppKit coordinates as `.rect`.
  case display(CGDirectDisplayID, frame: CGRect)

  var rect: CGRect {
    switch self {
    case .rect(let rect):
      rect
    case .window(let target):
      target.frame
    case .display(_, let frame):
      frame
    }
  }

  var windowTarget: WindowCaptureTarget? {
    switch self {
    case .rect, .display:
      nil
    case .window(let target):
      target
    }
  }
}

nonisolated struct AreaSelectionApplicationConfiguration {
  let prefetchedContentTask: ShareableContentPrefetchTask?
  let excludeOwnApplication: Bool
  let immediateMenuBarPopoverCaptures: [ImmediateMenuBarPopoverCapture]

  init(
    prefetchedContentTask: ShareableContentPrefetchTask?,
    excludeOwnApplication: Bool,
    immediateMenuBarPopoverCaptures: [ImmediateMenuBarPopoverCapture] = []
  ) {
    self.prefetchedContentTask = prefetchedContentTask
    self.excludeOwnApplication = excludeOwnApplication
    self.immediateMenuBarPopoverCaptures = immediateMenuBarPopoverCaptures
  }
}

nonisolated struct AreaSelectionResult {
  let target: AreaSelectionTarget
  let displayID: CGDirectDisplayID
  let mode: SelectionMode
  let displayIDs: Set<CGDirectDisplayID>

  init(
    target: AreaSelectionTarget,
    displayID: CGDirectDisplayID,
    mode: SelectionMode,
    displayIDs: Set<CGDirectDisplayID>? = nil
  ) {
    self.target = target
    self.displayID = displayID
    self.mode = mode
    self.displayIDs = displayIDs ?? [displayID]
  }

  var rect: CGRect {
    target.rect
  }

  var spansMultipleDisplays: Bool {
    displayIDs.count > 1
  }
}
