//
//  AnnotateSelectionChromeMetrics.swift
//  Snapzy
//

import CoreGraphics

/// Converts editor-only selection chrome from screen points into the two
/// coordinate spaces used by the annotation canvas. Image-space drawing is
/// scaled by both fit and zoom; AppKit hit testing receives canvas-local points
/// after fit scale, so it only needs the inverse zoom factor.
struct AnnotateSelectionChromeMetrics {
  static let handleSize: CGFloat = 8
  static let selectionLineWidth: CGFloat = 1
  static let selectionDashLength: CGFloat = 4
  static let selectionHaloWidth: CGFloat = 4

  private let fitScale: CGFloat
  private let zoomScale: CGFloat

  init(fitScale: CGFloat, zoomScale: CGFloat) {
    self.fitScale = max(fitScale, 0.0001)
    self.zoomScale = max(zoomScale, 0.0001)
  }

  /// Length for a Core Graphics context expressed in image coordinates.
  func imageLength(forScreenPoints length: CGFloat) -> CGFloat {
    length / (fitScale * zoomScale)
  }

  /// Length for an AppKit event point expressed in canvas-local coordinates.
  func canvasLength(forScreenPoints length: CGFloat) -> CGFloat {
    length / zoomScale
  }
}
