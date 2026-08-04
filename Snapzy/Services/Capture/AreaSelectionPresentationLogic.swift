//
//  AreaSelectionPresentationLogic.swift
//  Snapzy
//
//  Pure presentation-state evaluation for pooled area-selection windows,
//  extracted from AreaSelectionController so it can be unit-tested without
//  presenting overlay windows. The controller's session watchdog builds an
//  `AreaSelectionPresentationState` per pooled window and uses this logic to
//  decide whether the window is actually presenting on screen — `isVisible`
//  alone is not sufficient: an off-screen-positioned, occluded, or
//  wrong-space window can report `isVisible == true` while compositing
//  nothing, which leaves live-passthrough sessions fully functional but
//  invisible (the event tap drives selection from screen coordinates).
//

import CoreGraphics
import Foundation

enum AreaSelectionPresentationIssue: String, CaseIterable {
  /// Window is not ordered in on any space.
  case notVisible
  /// Window is not a member of the active space.
  case offActiveSpace
  /// Window frame no longer matches its screen's frame (stale after a display
  /// reconfiguration; content composites off the visible display).
  case frameMismatch
  /// Window alpha was dragged away from opaque by an animation or outside actor.
  case unexpectedAlpha
  /// WindowServer believes the window is fully covered; layer commits do not
  /// present while occluded.
  case occluded
  /// The WindowServer's on-screen window list (CGWindowList `.optionOnScreenOnly`) does not
  /// include the window even though AppKit considers it ordered in — the compositor is
  /// presenting nothing for this window on the active space. This is the ground-truth check
  /// every AppKit-side property above can miss: for a `.canJoinAllSpaces` panel
  /// `isOnActiveSpace` reports true even when the WindowServer dropped the all-spaces
  /// membership (the field failure where the overlay shows on one desktop Space but not
  /// another while every other property looks healthy).
  case notOnScreenPerWindowServer
}

struct AreaSelectionPresentationState: Equatable {
  var isVisible: Bool
  var isOnActiveSpace: Bool
  var occlusionVisible: Bool
  var alphaValue: CGFloat
  var windowFrame: CGRect
  var screenFrame: CGRect
  /// WindowServer ground truth from CGWindowList `.optionOnScreenOnly`. `nil` means the
  /// query failed or is not applicable (unknown) and is never treated as an anomaly.
  var onScreenPerWindowServer: Bool?
}

enum AreaSelectionPresentationLogic {
  /// Ordered list of detected presentation anomalies; empty when the window is
  /// presenting normally.
  static func issues(for state: AreaSelectionPresentationState) -> [AreaSelectionPresentationIssue] {
    var issues: [AreaSelectionPresentationIssue] = []
    if !state.isVisible {
      issues.append(.notVisible)
    }
    if !state.isOnActiveSpace {
      issues.append(.offActiveSpace)
    }
    if state.windowFrame != state.screenFrame {
      issues.append(.frameMismatch)
    }
    if state.alphaValue != 1 {
      issues.append(.unexpectedAlpha)
    }
    if !state.occlusionVisible {
      issues.append(.occluded)
    }
    if state.onScreenPerWindowServer == false {
      issues.append(.notOnScreenPerWindowServer)
    }
    return issues
  }
}
