//
//  AnnotationRotationGesture.swift
//  Snapzy
//
//  Pure geometry for the rotation handle and for resizing rotated annotations.
//

import CoreGraphics
import Foundation

nonisolated enum AnnotationRotationGesture {
  /// Shift snaps to this step.
  static let shiftSnapStepDegrees: CGFloat = 15
  /// Without Shift, angles this close to a right angle stick to it.
  static let magnetToleranceDegrees: CGFloat = 3
  private static let magnetAngles: [CGFloat] = [0, 90, -90, 180, -180]

  /// The angle after dragging the handle from `press` to `current` around
  /// `center`, starting at `originalDegrees`. Uses the pointer's angular delta,
  /// so grabbing the handle slightly off-center does not make the item jump.
  static func rotationDegrees(
    originalDegrees: CGFloat,
    center: CGPoint,
    press: CGPoint,
    current: CGPoint,
    shiftHeld: Bool
  ) -> CGFloat {
    let pressAngle = atan2(press.y - center.y, press.x - center.x)
    let currentAngle = atan2(current.y - center.y, current.x - center.x)
    guard pressAngle.isFinite, currentAngle.isFinite else { return originalDegrees }
    let raw = originalDegrees + (currentAngle - pressAngle) * 180 / .pi
    return snappedDegrees(raw, shiftHeld: shiftHeld)
  }

  /// Shift rounds to 15° steps; otherwise 0/±90/180 attract within ±3°.
  /// The result is wrapped into (-180, 180].
  static func snappedDegrees(_ degrees: CGFloat, shiftHeld: Bool) -> CGFloat {
    let normalized = AnnotationProperties.normalizedRotationDegrees(degrees)
    if shiftHeld {
      let stepped = (normalized / shiftSnapStepDegrees).rounded() * shiftSnapStepDegrees
      return AnnotationProperties.normalizedRotationDegrees(stepped)
    }
    for angle in magnetAngles where abs(normalized - angle) <= magnetToleranceDegrees {
      return AnnotationProperties.normalizedRotationDegrees(angle)
    }
    return normalized
  }

  /// Turns a resize computed in the original item's unrotated local frame into
  /// the bounds to store. The item rotates around its own center, so the new
  /// box is shifted until, once rotated, it lands where the local resize put
  /// it on screen; the opposite corner therefore stays fixed.
  static func anchoredBounds(
    forLocalResize localBounds: CGRect,
    originalTransform transform: CGAffineTransform
  ) -> CGRect {
    let center = CGPoint(x: localBounds.midX, y: localBounds.midY)
    let placedCenter = center.applying(transform)
    return localBounds.offsetBy(dx: placedCenter.x - center.x, dy: placedCenter.y - center.y)
  }

  /// Center of the rotation handle in image coordinates: `offset` image points
  /// beyond the middle of the item's local top edge (maxY, as image space is
  /// y-up), carried along with the item's rotation.
  static func handleCenter(for item: AnnotationItem, offset: CGFloat) -> CGPoint {
    let bounds = item.resizeBounds
    let local = CGPoint(x: bounds.midX, y: bounds.maxY + offset)
    return item.rotationTransform.map { local.applying($0) } ?? local
  }

  /// Middle of the item's local top edge, where the handle's stem starts.
  static func handleStemStart(for item: AnnotationItem) -> CGPoint {
    let bounds = item.resizeBounds
    let local = CGPoint(x: bounds.midX, y: bounds.maxY)
    return item.rotationTransform.map { local.applying($0) } ?? local
  }
}
