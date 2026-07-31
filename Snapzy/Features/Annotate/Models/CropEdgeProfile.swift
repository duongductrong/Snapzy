//
//  CropEdgeProfile.swift
//  Snapzy
//
//  Value type describing detected content-border positions of a source image,
//  produced by `CropContentAnalyzer.edgeProfile(for:imagePointSize:)`.
//

import CoreGraphics
import Foundation

/// Detected content-border positions of a source image, expressed in image
/// points — the coordinate space of `AnnotateState.cropRect` (bottom-left
/// origin). Used as snap targets for crop border-snapping and as the basis
/// for auto-crop tightening.
///
/// The image-bounds edges (0 and width for vertical, 0 and height for
/// horizontal) are always included by the analyzer, with strength 0.
struct CropEdgeProfile: Sendable, Equatable {
  /// X positions of vertical content borders, ascending, in image points.
  var verticalEdges: [CGFloat]
  /// Y positions of horizontal content borders, ascending, in image points
  /// (already flipped from pixel top-left space: imageY = heightPoints - pixelY).
  var horizontalEdges: [CGFloat]
  /// Mean per-pixel gradient strengths aligned with `verticalEdges`.
  /// Image-bounds edges carry strength 0 so real content borders outrank them.
  var verticalStrengths: [CGFloat]
  /// Mean per-pixel gradient strengths aligned with `horizontalEdges`.
  var horizontalStrengths: [CGFloat]
}
