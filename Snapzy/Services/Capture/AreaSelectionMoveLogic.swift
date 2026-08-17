//
//  AreaSelectionMoveLogic.swift
//  Snapzy
//
//  Pure geometry for space-to-move, extracted so it can be tested without a live overlay session.
//

import CoreGraphics

/// Anchors captured at the instant a space-to-move begins.
struct AreaSelectionMoveAnchors: Equatable {
  /// The selection's start point when the move began.
  var originStart: CGPoint
  /// The point the translation is measured from — the selection's current point when the move
  /// began, not a fresh pointer read. Anchoring here makes both seams zero: the selection neither
  /// resizes when Space goes down nor snaps when it comes back up.
  var anchor: CGPoint
}

enum AreaSelectionMoveLogic {
  /// Translate the selection to follow `pointer`, preserving its size.
  ///
  /// Computed absolutely rather than accumulated per event. Four sources feed the selection — the
  /// local and global drag monitors, the overlay's drag delegate and the live-passthrough tap —
  /// and they sample the pointer at different instants. Absolute means a stale, duplicate or
  /// out-of-order sample lands on the same rect instead of accumulating into its position.
  static func movedSelection(
    pointer: CGPoint,
    anchors: AreaSelectionMoveAnchors
  ) -> (start: CGPoint, current: CGPoint) {
    let dx = pointer.x - anchors.anchor.x
    let dy = pointer.y - anchors.anchor.y
    return (
      start: CGPoint(x: anchors.originStart.x + dx, y: anchors.originStart.y + dy),
      current: CGPoint(x: anchors.anchor.x + dx, y: anchors.anchor.y + dy)
    )
  }
}
