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

  // MARK: - Creation

  /// Space between a called-out area and its lens.
  static let calloutGap: CGFloat = 24
  /// Smallest lens a drag creates, so a tiny area still reads as a callout.
  static let minimumCreatedLensSide: CGFloat = 72

  /// A new magnifier from a creation gesture, the way most screenshot tools do it:
  /// - Click: a default-size lens right over the spot (an in-place loupe).
  /// - Drag: the dragged box is the area to magnify. The lens shows that area at the style's
  ///   zoom (lowered when the lens would not fit, raised when it would be tiny) and sits beside
  ///   it, on the side with the most room.
  static func creation(
    from start: CGPoint,
    to end: CGPoint,
    isDrag: Bool,
    style: MagnifierStyle,
    canvas canvasBounds: CGRect
  ) -> (lens: CGRect, geometry: MagnifierGeometry) {
    let canvas = canvasBounds.standardized
    guard isDrag else {
      let lens = lensBounds(centeredAt: start, size: defaultLensSize(for: canvas), within: canvas)
      return (lens, MagnifierGeometry(sourceCenter: start, style: style))
    }

    var region = CGRect(
      x: min(start.x, end.x),
      y: min(start.y, end.y),
      width: max(abs(end.x - start.x), 4),
      height: max(abs(end.y - start.y), 4)
    )
    if style.shape == .circle {
      // A round lens shows a round area: square the box around its center.
      let side = max(region.width, region.height)
      region = CGRect(x: region.midX - side / 2, y: region.midY - side / 2, width: side, height: side)
    }

    let regionLongSide = max(region.width, region.height)
    let canvasShortSide = canvas.isEmpty ? 600 : min(canvas.width, canvas.height)
    let maximumLensSide = max(minimumCreatedLensSide, canvasShortSide * 0.6)
    var zoom = clampedZoom(style.zoom)
    if regionLongSide * zoom > maximumLensSide {
      zoom = max(minimumZoom, maximumLensSide / regionLongSide)
    } else if regionLongSide * zoom < minimumCreatedLensSide {
      zoom = min(maximumZoom, minimumCreatedLensSide / regionLongSide)
    }
    var lensSize = CGSize(width: region.width * zoom, height: region.height * zoom)
    let lensLongSide = max(lensSize.width, lensSize.height)
    if lensLongSide > maximumLensSide {
      // Even the lowest zoom is too big: shrink the lens; it then shows the middle of the area.
      let scale = maximumLensSide / lensLongSide
      lensSize = CGSize(width: lensSize.width * scale, height: lensSize.height * scale)
    }

    var geometry = MagnifierGeometry(sourceCenter: CGPoint(x: region.midX, y: region.midY), style: style)
    geometry.zoom = zoom
    return (calloutLensBounds(size: lensSize, beside: region, within: canvas), geometry)
  }

  /// Where a lens of `size` goes next to `region`: right, left, above or below, trying the
  /// sides with the most free canvas first, keeping the lens inside the canvas and off the area.
  static func calloutLensBounds(size: CGSize, beside region: CGRect, within canvas: CGRect) -> CGRect {
    let gap = calloutGap
    let candidates: [(room: CGFloat, rect: CGRect)] = [
      (canvas.maxX - region.maxX, CGRect(x: region.maxX + gap, y: region.midY - size.height / 2, width: size.width, height: size.height)),
      (region.minX - canvas.minX, CGRect(x: region.minX - gap - size.width, y: region.midY - size.height / 2, width: size.width, height: size.height)),
      (canvas.maxY - region.maxY, CGRect(x: region.midX - size.width / 2, y: region.maxY + gap, width: size.width, height: size.height)),
      (region.minY - canvas.minY, CGRect(x: region.midX - size.width / 2, y: region.minY - gap - size.height, width: size.width, height: size.height)),
    ]
    guard !canvas.isEmpty else { return candidates[0].rect }
    for candidate in candidates.sorted(by: { $0.room > $1.room }) {
      var rect = candidate.rect
      // Slide along the side to stay inside the canvas.
      if rect.width <= canvas.width {
        rect.origin.x = min(max(rect.minX, canvas.minX), canvas.maxX - rect.width)
      }
      if rect.height <= canvas.height {
        rect.origin.y = min(max(rect.minY, canvas.minY), canvas.maxY - rect.height)
      }
      if canvas.contains(rect), !rect.intersects(region) {
        return rect
      }
    }
    return lensBounds(centeredAt: CGPoint(x: region.midX, y: region.midY), size: size, within: canvas)
  }

  // MARK: - Zoom steps

  /// The next zoom preset up or down from `zoom` (scroll wheel, `+` / `−`).
  static func steppedZoom(from zoom: CGFloat, up: Bool) -> CGFloat {
    let current = clampedZoom(zoom)
    if up {
      return zoomPresets.first(where: { $0 > current + 0.001 }) ?? maximumZoom
    }
    return zoomPresets.last(where: { $0 < current - 0.001 }) ?? minimumZoom
  }

  // MARK: - Callout cone

  /// The two lines that join the source outline to the lens along their outer edges (a
  /// "zoom callout" cone), as `[sourceA, lensA, lensB, sourceB]`. Nil when one shape holds the
  /// other or the shapes overlap too much to tell their outer edges apart.
  static func calloutCone(shape: MagnifierShape, source: CGRect, lens: CGRect) -> [CGPoint]? {
    guard source.width > 0, source.height > 0, lens.width > 0, lens.height > 0,
          !lens.contains(CGPoint(x: source.midX, y: source.midY)),
          !source.contains(CGPoint(x: lens.midX, y: lens.midY)) else { return nil }

    let samples = 96
    var points: [(point: CGPoint, isLens: Bool)] = []
    points.reserveCapacity(samples * 2)
    for (rect, isLens) in [(source, false), (lens, true)] {
      for index in 0 ..< samples {
        let angle = CGFloat(index) / CGFloat(samples) * 2 * .pi
        let target = CGPoint(x: rect.midX + cos(angle), y: rect.midY + sin(angle))
        points.append((boundaryPoint(of: shape, in: rect, toward: target), isLens))
      }
    }

    let hull = convexHull(points)
    guard hull.count >= 4 else { return nil }
    var bridges: [(from: CGPoint, to: CGPoint, toLens: Bool)] = []
    for index in hull.indices {
      let current = hull[index]
      let next = hull[(index + 1) % hull.count]
      if current.isLens != next.isLens {
        bridges.append((current.point, next.point, next.isLens))
      }
    }
    guard bridges.count == 2,
          let toLens = bridges.first(where: { $0.toLens }),
          let toSource = bridges.first(where: { !$0.toLens }) else { return nil }
    return [toLens.from, toLens.to, toSource.from, toSource.to]
  }

  /// Andrew's monotone chain, counter-clockwise, keeping each point's tag.
  private static func convexHull(_ points: [(point: CGPoint, isLens: Bool)]) -> [(point: CGPoint, isLens: Bool)] {
    let sorted = points.sorted { $0.point.x == $1.point.x ? $0.point.y < $1.point.y : $0.point.x < $1.point.x }
    guard sorted.count > 2 else { return sorted }
    func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }
    var lower: [(point: CGPoint, isLens: Bool)] = []
    for item in sorted {
      while lower.count >= 2, cross(lower[lower.count - 2].point, lower[lower.count - 1].point, item.point) <= 0 {
        lower.removeLast()
      }
      lower.append(item)
    }
    var upper: [(point: CGPoint, isLens: Bool)] = []
    for item in sorted.reversed() {
      while upper.count >= 2, cross(upper[upper.count - 2].point, upper[upper.count - 1].point, item.point) <= 0 {
        upper.removeLast()
      }
      upper.append(item)
    }
    return Array(lower.dropLast() + upper.dropLast())
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
      // In a corner zone, land on the corner's arc instead of the square corner.
      let point = CGPoint(x: center.x + ux * distance, y: center.y + uy * distance)
      let radius = min(cornerRadius(forLens: rect), min(a, b))
      let insetX = a - radius
      let insetY = b - radius
      guard radius > 0, abs(point.x - center.x) > insetX, abs(point.y - center.y) > insetY else { return point }
      let corner = CGPoint(
        x: center.x + (point.x > center.x ? insetX : -insetX),
        y: center.y + (point.y > center.y ? insetY : -insetY)
      )
      let cornerLength = hypot(point.x - corner.x, point.y - corner.y)
      guard cornerLength > 0 else { return point }
      return CGPoint(
        x: corner.x + (point.x - corner.x) / cornerLength * radius,
        y: corner.y + (point.y - corner.y) / cornerLength * radius
      )
    }
    return CGPoint(x: center.x + ux * distance, y: center.y + uy * distance)
  }
}
