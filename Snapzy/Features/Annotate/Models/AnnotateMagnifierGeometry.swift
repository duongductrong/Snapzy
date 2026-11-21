//
//  AnnotateMagnifierGeometry.swift
//  Snapzy
//
//  What a Magnifier (loupe) annotation remembers. The item's `bounds` is the lens; the source
//  is a point in image space (bottom-left origin, like every annotation) plus the zoom. The
//  source area is always the lens's size divided by the zoom, centered on `sourceCenter`, so it
//  follows the lens shape and a resize keeps the zoom. Pixels are sampled from the current
//  source image at draw time, so rotate, flip, cut out and the cutout overlay never leave a
//  stale copy behind.
//

import CoreGraphics
import Foundation

nonisolated enum MagnifierShape: String, CaseIterable, Codable, Equatable {
  case circle
  case roundedRect
}

/// The look of a magnifier: new items take the tool's style, and the quick properties bar
/// edits the selected items' style.
nonisolated struct MagnifierStyle: Codable, Equatable {
  var zoom: CGFloat = MagnifierGeometry.defaultZoom
  var shape: MagnifierShape = .circle
  var showsConnector = true
  var showsShadow = true
}

nonisolated struct MagnifierGeometry: Equatable {
  static let minimumZoom: CGFloat = 1.5
  static let maximumZoom: CGFloat = 8
  static let defaultZoom: CGFloat = 2
  /// Zoom choices offered in the quick properties bar.
  static let zoomPresets: [CGFloat] = [1.5, 2, 3, 4, 6, 8]

  /// Center of the magnified area, in image points.
  var sourceCenter: CGPoint
  var zoom: CGFloat
  var shape: MagnifierShape
  /// Draws the source outline and a line to the lens when they are apart.
  var showsConnector: Bool
  var showsShadow: Bool

  init(
    sourceCenter: CGPoint,
    zoom: CGFloat = MagnifierGeometry.defaultZoom,
    shape: MagnifierShape = .circle,
    showsConnector: Bool = true,
    showsShadow: Bool = true
  ) {
    self.sourceCenter = sourceCenter
    self.zoom = Self.clampedZoom(zoom)
    self.shape = shape
    self.showsConnector = showsConnector
    self.showsShadow = showsShadow
  }

  init(sourceCenter: CGPoint, style: MagnifierStyle) {
    self.init(
      sourceCenter: sourceCenter,
      zoom: style.zoom,
      shape: style.shape,
      showsConnector: style.showsConnector,
      showsShadow: style.showsShadow
    )
  }

  var style: MagnifierStyle {
    get { MagnifierStyle(zoom: zoom, shape: shape, showsConnector: showsConnector, showsShadow: showsShadow) }
    set {
      zoom = Self.clampedZoom(newValue.zoom)
      shape = newValue.shape
      showsConnector = newValue.showsConnector
      showsShadow = newValue.showsShadow
    }
  }

  static func clampedZoom(_ zoom: CGFloat) -> CGFloat {
    guard zoom.isFinite else { return defaultZoom }
    return min(max(zoom, minimumZoom), maximumZoom)
  }

  /// The magnified area for a lens of `lensBounds`.
  func sourceRect(forLens lensBounds: CGRect) -> CGRect {
    let lens = lensBounds.standardized
    let width = lens.width / zoom
    let height = lens.height / zoom
    return CGRect(x: sourceCenter.x - width / 2, y: sourceCenter.y - height / 2, width: width, height: height)
  }

  func translated(dx: CGFloat, dy: CGFloat) -> MagnifierGeometry {
    var copy = self
    copy.sourceCenter = CGPoint(x: sourceCenter.x + dx, y: sourceCenter.y + dy)
    return copy
  }

  func movingSource(_ transform: (CGPoint) -> CGPoint) -> MagnifierGeometry {
    var copy = self
    copy.sourceCenter = transform(sourceCenter)
    return copy
  }

  /// Corner radius of the rounded-rect shape for a lens of `lensBounds`.
  static func cornerRadius(forLens lensBounds: CGRect) -> CGFloat {
    min(lensBounds.width, lensBounds.height) * 0.18
  }

  static func path(for shape: MagnifierShape, in rect: CGRect) -> CGPath {
    switch shape {
    case .circle:
      return CGPath(ellipseIn: rect, transform: nil)
    case .roundedRect:
      let radius = min(cornerRadius(forLens: rect), min(rect.width, rect.height) / 2)
      return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
  }

  /// Lens size for a new magnifier on a canvas of `canvasBounds`.
  static func defaultLensSize(for canvasBounds: CGRect) -> CGSize {
    let shortSide = min(canvasBounds.width, canvasBounds.height)
    let side = min(max(shortSide * 0.28, 72), 220)
    return CGSize(width: side, height: side)
  }

  /// A new lens centered on `center`, nudged inside `canvasBounds` when it fits.
  static func lensBounds(centeredAt center: CGPoint, size: CGSize, within canvasBounds: CGRect) -> CGRect {
    var rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    let canvas = canvasBounds.standardized
    guard !canvas.isEmpty else { return rect }
    if rect.width <= canvas.width {
      rect.origin.x = min(max(rect.minX, canvas.minX), canvas.maxX - rect.width)
    }
    if rect.height <= canvas.height {
      rect.origin.y = min(max(rect.minY, canvas.minY), canvas.maxY - rect.height)
    }
    return rect
  }

  /// Point on the boundary of `shape` in `rect` in the direction of `target` from its center.
  static func boundaryPoint(of shape: MagnifierShape, in rect: CGRect, toward target: CGPoint) -> CGPoint {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let dx = target.x - center.x
    let dy = target.y - center.y
    let length = hypot(dx, dy)
    guard length > 0, rect.width > 0, rect.height > 0 else { return center }
    let ux = dx / length
    let uy = dy / length
    let a = rect.width / 2
    let b = rect.height / 2
    let distance: CGFloat
    switch shape {
    case .circle:
      distance = 1 / sqrt((ux * ux) / (a * a) + (uy * uy) / (b * b))
    case .roundedRect:
      let tx = ux == 0 ? CGFloat.infinity : a / abs(ux)
      let ty = uy == 0 ? CGFloat.infinity : b / abs(uy)
      distance = min(tx, ty)
    }
    return CGPoint(x: center.x + ux * distance, y: center.y + uy * distance)
  }
}
