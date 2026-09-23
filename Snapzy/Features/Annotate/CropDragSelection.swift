//
//  CropDragSelection.swift
//  Snapzy
//
//  Pure geometry for drawing a fresh crop rect by dragging (Shottr style):
//  the mouse-down point is the fixed anchor, the pointer is the moving corner.
//  Bottom-left origin image points, matching `handleCropResize`.
//

import CoreGraphics
import Foundation

enum CropDragSelection {
  /// Rect spanned by `anchor` and `current`, both clamped to `bounds`.
  /// With `aspectRatio` (width / height) the rect shrinks toward the anchor
  /// to fit that ratio, so it never leaves `bounds`.
  static func rect(
    anchor: CGPoint,
    current: CGPoint,
    bounds: CGRect,
    aspectRatio: CGFloat? = nil
  ) -> CGRect {
    let bounds = bounds.standardized
    let anchor = clamp(anchor, to: bounds)
    let current = clamp(current, to: bounds)

    let dx = current.x - anchor.x
    let dy = current.y - anchor.y
    var width = abs(dx)
    var height = abs(dy)

    if let ratio = aspectRatio, ratio > 0, width > 0, height > 0 {
      if width / height > ratio {
        width = height * ratio
      } else {
        height = width / ratio
      }
    }

    return CGRect(
      x: dx >= 0 ? anchor.x : anchor.x - width,
      y: dy >= 0 ? anchor.y : anchor.y - height,
      width: width,
      height: height
    )
  }

  /// The corner that follows the pointer, so edge snapping only moves the
  /// edges being drawn and keeps the anchor edges fixed.
  static func movingHandle(anchor: CGPoint, current: CGPoint) -> CropHandle {
    switch (current.x >= anchor.x, current.y >= anchor.y) {
    case (true, true): return .topRight
    case (false, true): return .topLeft
    case (true, false): return .bottomRight
    case (false, false): return .bottomLeft
    }
  }

  /// Whether a mouse-down that missed every handle should draw a new rect
  /// instead of moving the existing one: always outside the rect, and inside
  /// it while the rect still covers the whole image (nothing chosen yet).
  static func shouldBeginDrawing(
    at point: CGPoint,
    cropRect: CGRect,
    imageBounds: CGRect,
    tolerance: CGFloat = 0.5
  ) -> Bool {
    guard cropRect.contains(point) else { return true }
    let crop = cropRect.standardized
    let image = imageBounds.standardized
    return abs(crop.minX - image.minX) <= tolerance
      && abs(crop.minY - image.minY) <= tolerance
      && abs(crop.width - image.width) <= tolerance
      && abs(crop.height - image.height) <= tolerance
  }

  private static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
    CGPoint(
      x: min(max(point.x, bounds.minX), bounds.maxX),
      y: min(max(point.y, bounds.minY), bounds.maxY)
    )
  }
}
