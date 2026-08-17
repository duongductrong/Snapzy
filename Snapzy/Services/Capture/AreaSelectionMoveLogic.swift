//
//  AreaSelectionMoveLogic.swift
//  Snapzy
//

import CoreGraphics

/// Anchors captured at the instant a space-to-move begins.
struct AreaSelectionMoveAnchors: Equatable {
  var originStart: CGPoint
  /// The selection's current point when the move began, not a fresh pointer read.
  var anchor: CGPoint
}

enum AreaSelectionMoveLogic {
  /// Translate the selection to follow `pointer`, preserving its size. Computed absolutely so a
  /// stale or duplicate sample from another event source cannot accumulate into the position.
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
