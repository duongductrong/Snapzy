//
//  PPOCRGeometry.swift
//  Snapzy
//
//  Oriented box types shared by PP-OCR detection and recognition.
//

import CoreGraphics
import Foundation

/// An oriented box — PaddleOCR's `get_mini_boxes` minimum-area rectangle — in
/// whatever pixel space its points came from.
struct PPOCRRotatedRect: Equatable {
  var center: CGPoint
  var size: CGSize
  /// Rotation of the width axis in radians, clockwise-positive because the
  /// surrounding pixel space has y growing downward.
  var angle: CGFloat

  /// Close enough to upright that a plain crop is indistinguishable from a
  /// rotated one, and far cheaper. ~1.1°.
  static let axisAlignedTolerance: CGFloat = 0.02

  var isAxisAligned: Bool {
    abs(angle) < Self.axisAlignedTolerance
  }

  var isFinite: Bool {
    center.x.isFinite && center.y.isFinite
      && size.width.isFinite && size.height.isFinite
      && angle.isFinite
  }

  var corners: [CGPoint] {
    let widthAxis = CGPoint(x: cos(angle), y: sin(angle))
    let heightAxis = CGPoint(x: -sin(angle), y: cos(angle))
    let halfWidth = size.width / 2
    let halfHeight = size.height / 2
    return [(-1, -1), (1, -1), (1, 1), (-1, 1)].map { signX, signY in
      let alongWidth = CGFloat(signX) * halfWidth
      let alongHeight = CGFloat(signY) * halfHeight
      return CGPoint(
        x: center.x + alongWidth * widthAxis.x + alongHeight * heightAxis.x,
        y: center.y + alongWidth * widthAxis.y + alongHeight * heightAxis.y
      )
    }
  }

  var boundingRect: CGRect {
    let points = corners
    let xs = points.map(\.x)
    let ys = points.map(\.y)
    guard let minX = xs.min(), let maxX = xs.max(),
          let minY = ys.min(), let maxY = ys.max()
    else { return .zero }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  /// Grows the box by `padding` on all four sides, along its own axes.
  func padded(by padding: CGFloat) -> PPOCRRotatedRect {
    var result = self
    result.size = CGSize(width: size.width + 2 * padding, height: size.height + 2 * padding)
    return result
  }
}

/// A detected text-line box in original-image pixel coordinates
/// (top-left origin), plus the mean probability under the box.
struct PPOCRTextBox {
  /// Oriented box used for cropping the line out of the source image.
  var rotated: PPOCRRotatedRect
  /// `rotated`'s axis-aligned bounds, clipped to the image. Drives reading
  /// order and the Vision-compatible normalized bounding box.
  var rect: CGRect
  var score: Float

  init(rotated: PPOCRRotatedRect, rect: CGRect, score: Float) {
    self.rotated = rotated
    self.rect = rect
    self.score = score
  }

  /// Axis-aligned convenience for callers with no orientation to express.
  init(rect: CGRect, score: Float) {
    self.init(
      rotated: PPOCRRotatedRect(
        center: CGPoint(x: rect.midX, y: rect.midY),
        size: rect.size,
        angle: 0
      ),
      rect: rect,
      score: score
    )
  }
}
