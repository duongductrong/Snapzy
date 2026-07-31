//
//  CropEdgeSnapping.swift
//  Snapzy
//
//  Pure snap math: snap the moving edges of a proposed crop rect to detected
//  content borders (CropEdgeProfile). Bottom-left origin image points,
//  mirroring `handleCropResize` semantics (top = maxY, bottom = minY).
//

import CoreGraphics
import Foundation

enum CropEdgeSnapping {
  /// Snap the edge(s) moved by `handle` to the nearest target within
  /// `tolerance` points. Corners move two edges independently, edge handles
  /// one, `.body` returns `proposed` unchanged. The opposite edge(s) stay
  /// anchored to `proposed` (which `handleCropResize` derives from the
  /// gesture's original rect). A snap is skipped when it would shrink the
  /// rect below `minSize` or invert it; returns `proposed` when nothing is
  /// within tolerance.
  static func resolve(
    handle: CropHandle,
    proposed: CGRect,
    targets: CropEdgeProfile,
    tolerance: CGFloat,
    minSize: CGFloat = 20
  ) -> CGRect {
    guard handle != .body else { return proposed }
    var rect = proposed.standardized

    if handle.movesMinX,
       let snap = nearestTarget(to: rect.minX, in: targets.verticalEdges, tolerance: tolerance),
       snap <= rect.maxX - minSize {
      rect.size.width = rect.maxX - snap
      rect.origin.x = snap
    }
    if handle.movesMaxX,
       let snap = nearestTarget(to: rect.maxX, in: targets.verticalEdges, tolerance: tolerance),
       snap >= rect.minX + minSize {
      rect.size.width = snap - rect.minX
    }
    if handle.movesMinY,
       let snap = nearestTarget(to: rect.minY, in: targets.horizontalEdges, tolerance: tolerance),
       snap <= rect.maxY - minSize {
      rect.size.height = rect.maxY - snap
      rect.origin.y = snap
    }
    if handle.movesMaxY,
       let snap = nearestTarget(to: rect.maxY, in: targets.horizontalEdges, tolerance: tolerance),
       snap >= rect.minY + minSize {
      rect.size.height = snap - rect.minY
    }
    return rect
  }

  /// Nearest target within `tolerance` (inclusive), or nil.
  private static func nearestTarget(
    to value: CGFloat, in targets: [CGFloat], tolerance: CGFloat
  ) -> CGFloat? {
    var best: (target: CGFloat, distance: CGFloat)?
    for target in targets {
      let distance = abs(target - value)
      guard distance <= tolerance else { continue }
      if let current = best, distance >= current.distance { continue }
      best = (target, distance)
    }
    return best?.target
  }
}

// MARK: - Handle edge mapping

private extension CropHandle {
  var movesMinX: Bool { [.topLeft, .left, .bottomLeft].contains(self) }
  var movesMaxX: Bool { [.topRight, .right, .bottomRight].contains(self) }
  var movesMinY: Bool { [.bottomLeft, .bottom, .bottomRight].contains(self) }
  var movesMaxY: Bool { [.topLeft, .top, .topRight].contains(self) }
}
