//
//  VisionImageGeometry.swift
//  Snapzy
//
//  Converts Vision's normalized boxes into image coordinates.
//

import CoreGraphics

/// Vision boxes are normalized (0...1) with a bottom-left origin.
///
/// Two image spaces are in use:
/// - **Top-left** (y grows downward): pixel/reading-order analysis, e.g. the
///   sensitive-data heuristics that look for a cardholder "below" the card number.
/// - **Annotate** (bottom-left, y grows upward): `AnnotationItem.bounds`. The canvas
///   view is not flipped and the blur renderer samples with `height - maxY`.
///
/// Anything inserted into the Annotate canvas must end up in annotate space.
nonisolated enum VisionImageGeometry {
  /// Normalized Vision box → annotate image rect (bottom-left origin).
  static func annotateRect(fromVisionBoundingBox box: CGRect, imageSize: CGSize) -> CGRect {
    CGRect(
      x: box.minX * imageSize.width,
      y: box.minY * imageSize.height,
      width: box.width * imageSize.width,
      height: box.height * imageSize.height
    ).standardized
  }

  /// Normalized Vision box → top-left image rect (y grows downward).
  static func topLeftRect(fromVisionBoundingBox box: CGRect, imageSize: CGSize) -> CGRect {
    CGRect(
      x: box.minX * imageSize.width,
      y: (1 - box.maxY) * imageSize.height,
      width: box.width * imageSize.width,
      height: box.height * imageSize.height
    ).standardized
  }

  /// Flips a rect between top-left and annotate space. The flip is its own inverse.
  static func flippedVertically(_ rect: CGRect, imageHeight: CGFloat) -> CGRect {
    let rect = rect.standardized
    return CGRect(
      x: rect.minX,
      y: imageHeight - rect.maxY,
      width: rect.width,
      height: rect.height
    )
  }
}
