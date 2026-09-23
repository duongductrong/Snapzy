//
//  RecordingDisplaySelectionLogic.swift
//  Snapzy
//
//  Pure decision logic for picking a whole display in the recording overlay (plain click
//  and the Enter "whole display" mode), extracted from AreaSelectionController and
//  RecordingCoordinator so it can be unit-tested without a session or real screens.
//

import CoreGraphics
import Foundation

enum RecordingDisplaySelectionLogic {
  /// Overlay keys that switch the interaction mode.
  enum ModeKey {
    /// The (remappable) app-window shortcut, `A` by default.
    case applicationToggle
    /// Return or keypad Enter. Recording sessions only.
    case enter
  }

  /// What a plain click (released before the drag threshold) in manual-region mode selects.
  enum ClickResolution: Equatable {
    case element
    case window
    case display
  }

  /// The mode a key switches to, or `nil` when the key must be ignored.
  ///
  /// `A` toggles window selection on and off; from whole-display mode it goes to window
  /// selection. Enter toggles whole-display mode on and off. Every transition refuses while
  /// a manual drag is committed, and `A` refuses when the session has no window data.
  static func nextMode(
    from mode: AreaSelectionInteractionMode,
    key: ModeKey,
    allowsApplicationWindow: Bool,
    isDragging: Bool
  ) -> AreaSelectionInteractionMode? {
    guard !isDragging else { return nil }
    switch key {
    case .applicationToggle:
      guard allowsApplicationWindow else { return nil }
      return mode == .applicationWindow ? .manualRegion : .applicationWindow
    case .enter:
      return mode == .fullDisplay ? .manualRegion : .fullDisplay
    }
  }

  /// Resolution order for a plain click: with auto-detect on, a hovered element wins, then a
  /// hovered window. Otherwise the click selects the display under the pointer.
  static func clickResolution(
    hasHoveredElement: Bool,
    hasHoveredWindow: Bool,
    autoDetect: Bool
  ) -> ClickResolution {
    guard autoDetect else { return .display }
    if hasHoveredElement { return .element }
    if hasHoveredWindow { return .window }
    return .display
  }

  /// The display containing `point`, in AppKit global coordinates. Uses `NSMouseInRect`
  /// semantics for an unflipped space (`minX <= x < maxX`, `minY < y <= maxY`), so a point on
  /// an edge shared by two displays resolves to exactly one of them. Returns `nil` for a
  /// point in a gap between displays.
  static func display(
    containing point: CGPoint,
    screens: [(id: CGDirectDisplayID, frame: CGRect)]
  ) -> (id: CGDirectDisplayID, frame: CGRect)? {
    screens.first { screen in
      point.x >= screen.frame.minX && point.x < screen.frame.maxX
        && point.y > screen.frame.minY && point.y <= screen.frame.maxY
    }
  }

  /// The frame of the display that overlaps `rect` the most, or `nil` when `rect` is `nil`
  /// or overlaps no display. Used to keep the toolbar's Fullscreen toggle on the display the
  /// user already picked.
  static func displayFrame(bestMatching rect: CGRect?, screenFrames: [CGRect]) -> CGRect? {
    guard let rect else { return nil }
    var best: (frame: CGRect, area: CGFloat)?
    for frame in screenFrames {
      let overlap = frame.intersection(rect)
      guard !overlap.isNull, !overlap.isEmpty else { continue }
      let area = overlap.width * overlap.height
      if area > (best?.area ?? 0) {
        best = (frame, area)
      }
    }
    return best?.frame
  }

  /// A whole-display selection must not replace the remembered recording area: with
  /// "Remember last area" on, the next Record Screen would reopen it as an Area recording.
  static func shouldSaveLastArea(for captureMode: RecordingCaptureMode) -> Bool {
    captureMode != .fullscreen
  }
}
