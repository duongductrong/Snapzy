//
//  AnnotationItem.swift
//  Snapzy
//
//  Model representing a single annotation element
//

import CoreGraphics
import Foundation
import SwiftUI

/// Blur effect type for blur annotations
enum BlurType: String, CaseIterable, Identifiable, Equatable {
  case pixelated
  case gaussian

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .pixelated: return L10n.AnnotateUI.pixelated
    case .gaussian: return L10n.AnnotateUI.gaussian
    }
  }

  var icon: String {
    switch self {
    case .pixelated: return "square.grid.3x3"
    case .gaussian: return "drop.halffull"
    }
  }
}

enum WatermarkStyle: String, CaseIterable, Identifiable, Equatable {
  case single
  case diagonal
  case tiled

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .single: return L10n.AnnotateUI.watermarkSingle
    case .diagonal: return L10n.AnnotateUI.watermarkDiagonal
    case .tiled: return L10n.AnnotateUI.watermarkTiled
    }
  }

  var icon: String {
    switch self {
    case .single: return "text.aligncenter"
    case .diagonal: return "line.diagonal"
    case .tiled: return "square.grid.3x3"
    }
  }

  var defaultRotationDegrees: CGFloat {
    switch self {
    case .single: return 0
    case .diagonal, .tiled: return -24
    }
  }
}

enum ArrowStyle: String, CaseIterable, Identifiable, Equatable {
  case straight
  case elbow
  case curve

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .straight: return L10n.AnnotateUI.straight
    case .elbow: return L10n.AnnotateUI.elbow
    case .curve: return L10n.AnnotateUI.curve
    }
  }

  var icon: String {
    switch self {
    case .straight: return "arrow.up.right"
    case .elbow: return "arrow.turn.up.right"
    case .curve: return "arrow.up.left.and.arrow.down.right"
    }
  }

  var helperText: String {
    switch self {
    case .straight: return L10n.AnnotateUI.straightArrowHelp
    case .elbow: return L10n.AnnotateUI.elbowArrowHelp
    case .curve: return L10n.AnnotateUI.curveArrowHelp
    }
  }
}

struct ArrowGeometry: Equatable {
  var start: CGPoint
  var end: CGPoint
  var style: ArrowStyle
  var controlPoint: CGPoint?

  init(start: CGPoint, end: CGPoint, style: ArrowStyle, controlPoint: CGPoint? = nil) {
    self.start = start
    self.end = end
    self.style = style
    self.controlPoint = Self.normalizedControlPoint(
      start: start,
      end: end,
      style: style,
      current: controlPoint
    )
  }

  var resolvedControlPoint: CGPoint? {
    Self.normalizedControlPoint(start: start, end: end, style: style, current: controlPoint)
  }

  var isRenderable: Bool {
    let points = sampledPoints()
    guard let first = points.first else { return false }
    return points.dropFirst().contains { $0 != first }
  }

  func path() -> CGPath {
    let path = CGMutablePath()
    path.move(to: start)

    switch style {
    case .straight:
      path.addLine(to: end)

    case .elbow:
      if let corner = resolvedControlPoint {
        if corner != start {
          path.addLine(to: corner)
        }
        if end != corner {
          path.addLine(to: end)
        }
      } else {
        path.addLine(to: end)
      }

    case .curve:
      if let control = resolvedControlPoint {
        path.addQuadCurve(to: end, control: control)
      } else {
        path.addLine(to: end)
      }
    }

    return path
  }

  func sampledPoints(curveSegments: Int = 16) -> [CGPoint] {
    switch style {
    case .straight:
      return deduplicated([start, end])

    case .elbow:
      guard let corner = resolvedControlPoint else {
        return deduplicated([start, end])
      }
      return deduplicated([start, corner, end])

    case .curve:
      guard let control = resolvedControlPoint else {
        return deduplicated([start, end])
      }

      var points: [CGPoint] = []
      points.reserveCapacity(curveSegments + 1)

      for segment in 0...curveSegments {
        let t = CGFloat(segment) / CGFloat(curveSegments)
        let oneMinusT = 1 - t
        let point = CGPoint(
          x: oneMinusT * oneMinusT * start.x + 2 * oneMinusT * t * control.x + t * t * end.x,
          y: oneMinusT * oneMinusT * start.y + 2 * oneMinusT * t * control.y + t * t * end.y
        )
        points.append(point)
      }

      return deduplicated(points)
    }
  }

  func tangentAngleAtEnd() -> CGFloat {
    switch style {
    case .straight:
      return atan2(end.y - start.y, end.x - start.x)

    case .elbow:
      if let corner = resolvedControlPoint, corner != end {
        return atan2(end.y - corner.y, end.x - corner.x)
      }
      return atan2(end.y - start.y, end.x - start.x)

    case .curve:
      if let control = resolvedControlPoint, control != end {
        return atan2(end.y - control.y, end.x - control.x)
      }
      return atan2(end.y - start.y, end.x - start.x)
    }
  }

  func bounds() -> CGRect {
    let points = sampledPoints()
    guard let first = points.first else { return CGRect(x: start.x, y: start.y, width: 1, height: 1) }

    var minX = first.x
    var maxX = first.x
    var minY = first.y
    var maxY = first.y

    for point in points.dropFirst() {
      minX = min(minX, point.x)
      maxX = max(maxX, point.x)
      minY = min(minY, point.y)
      maxY = max(maxY, point.y)
    }

    var rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).standardized
    if rect.width < 1 {
      rect.origin.x -= (1 - rect.width) / 2
      rect.size.width = 1
    }
    if rect.height < 1 {
      rect.origin.y -= (1 - rect.height) / 2
      rect.size.height = 1
    }
    return rect
  }

  func translatedBy(dx: CGFloat, dy: CGFloat) -> ArrowGeometry {
    ArrowGeometry(
      start: CGPoint(x: start.x + dx, y: start.y + dy),
      end: CGPoint(x: end.x + dx, y: end.y + dy),
      style: style,
      controlPoint: resolvedControlPoint.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
    )
  }

  func remapped(from oldBounds: CGRect, to newBounds: CGRect) -> ArrowGeometry {
    ArrowGeometry(
      start: Self.remap(point: start, from: oldBounds, to: newBounds),
      end: Self.remap(point: end, from: oldBounds, to: newBounds),
      style: style,
      controlPoint: resolvedControlPoint.map { Self.remap(point: $0, from: oldBounds, to: newBounds) }
    )
  }

  func withStyle(_ newStyle: ArrowStyle) -> ArrowGeometry {
    ArrowGeometry(start: start, end: end, style: newStyle)
  }

  private static func normalizedControlPoint(
    start: CGPoint,
    end: CGPoint,
    style: ArrowStyle,
    current: CGPoint?
  ) -> CGPoint? {
    switch style {
    case .straight:
      return nil
    case .elbow:
      return current ?? defaultElbowControlPoint(start: start, end: end)
    case .curve:
      return current ?? defaultCurveControlPoint(start: start, end: end)
    }
  }

  private static func defaultElbowControlPoint(start: CGPoint, end: CGPoint) -> CGPoint {
    let dx = abs(end.x - start.x)
    let dy = abs(end.y - start.y)

    if dx >= dy {
      return CGPoint(x: end.x, y: start.y)
    }
    return CGPoint(x: start.x, y: end.y)
  }

  private static func defaultCurveControlPoint(start: CGPoint, end: CGPoint) -> CGPoint {
    let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = max(hypot(dx, dy), 1)
    let normal = CGPoint(x: -dy / length, y: dx / length)
    let offset = min(max(length * 0.22, 18), 72)
    return CGPoint(
      x: mid.x + normal.x * offset,
      y: mid.y + normal.y * offset
    )
  }

  private static func remap(point: CGPoint, from oldBounds: CGRect, to newBounds: CGRect) -> CGPoint {
    CGPoint(
      x: remapCoordinate(point.x, oldMin: oldBounds.minX, oldSize: oldBounds.width, newMin: newBounds.minX, newSize: newBounds.width),
      y: remapCoordinate(point.y, oldMin: oldBounds.minY, oldSize: oldBounds.height, newMin: newBounds.minY, newSize: newBounds.height)
    )
  }

  private static func remapCoordinate(
    _ value: CGFloat,
    oldMin: CGFloat,
    oldSize: CGFloat,
    newMin: CGFloat,
    newSize: CGFloat
  ) -> CGFloat {
    guard oldSize != 0 else {
      return newMin + newSize / 2
    }

    let progress = (value - oldMin) / oldSize
    return newMin + progress * newSize
  }

  private func deduplicated(_ points: [CGPoint]) -> [CGPoint] {
    var result: [CGPoint] = []
    result.reserveCapacity(points.count)

    for point in points where result.last != point {
      result.append(point)
    }

    return result
  }
}

/// Single annotation element on the canvas
struct AnnotationItem: Identifiable, Equatable {
  let id: UUID
  var type: AnnotationType
  var bounds: CGRect
  var properties: AnnotationProperties

  init(type: AnnotationType, bounds: CGRect, properties: AnnotationProperties) {
    self.id = UUID()
    self.type = type
    self.bounds = bounds
    self.properties = properties
  }

  static func == (lhs: AnnotationItem, rhs: AnnotationItem) -> Bool {
    lhs.id == rhs.id
  }
}

/// Types of annotations
enum AnnotationType: Equatable {
  case path([CGPoint])
  case rectangle
  case filledRectangle
  case oval
  case arrow(ArrowGeometry)
  case line(start: CGPoint, end: CGPoint)
  case text(String)
  case highlight([CGPoint])
  case blur(BlurType)
  case counter(Int)
  case watermark(String)
  case embeddedImage(UUID)

  /// Corresponding toolbar tool type for this annotation
  var toolType: AnnotationToolType {
    switch self {
    case .path: return .pencil
    case .rectangle: return .rectangle
    case .filledRectangle: return .filledRectangle
    case .oval: return .oval
    case .arrow: return .arrow
    case .line: return .line
    case .text: return .text
    case .highlight: return .highlighter
    case .blur: return .blur
    case .counter: return .counter
    case .watermark: return .watermark
    case .embeddedImage: return .selection
    }
  }

  /// Whether this annotation type exposes the standard property sidebar controls.
  var supportsPropertyEditing: Bool {
    switch self {
    case .embeddedImage:
      return false
    default:
      return true
    }
  }

  var supportsQuickPropertiesBar: Bool {
    supportsPropertyEditing && toolType.supportsQuickPropertiesBar
  }

  var supportsQuickStrokeColor: Bool {
    supportsQuickPropertiesBar && toolType.supportsQuickStrokeColor
  }

  var supportsQuickFillColor: Bool {
    supportsQuickPropertiesBar && toolType.supportsQuickFillColor
  }

  var supportsQuickStrokeWidth: Bool {
    supportsQuickPropertiesBar && toolType.supportsQuickStrokeWidth
  }
}

/// Visual properties for an annotation
struct AnnotationProperties: Equatable {
  static let controlValueRange: ClosedRange<CGFloat> = 1...20

  var strokeColor: Color
  var fillColor: Color
  var strokeWidth: CGFloat
  var cornerRadius: CGFloat
  var fontSize: CGFloat
  var fontName: String
  var opacity: CGFloat
  var rotationDegrees: CGFloat
  var watermarkStyle: WatermarkStyle

  init(
    strokeColor: Color = .red,
    fillColor: Color = .clear,
    strokeWidth: CGFloat = 3,
    cornerRadius: CGFloat = 0,
    fontSize: CGFloat = 16,
    fontName: String = "SF Pro",
    opacity: CGFloat = 1,
    rotationDegrees: CGFloat = 0,
    watermarkStyle: WatermarkStyle = .single
  ) {
    self.strokeColor = strokeColor
    self.fillColor = fillColor
    self.strokeWidth = strokeWidth
    self.cornerRadius = cornerRadius
    self.fontSize = fontSize
    self.fontName = fontName
    self.opacity = opacity
    self.rotationDegrees = rotationDegrees
    self.watermarkStyle = watermarkStyle
  }

  static func clampedControlValue(_ value: CGFloat) -> CGFloat {
    min(max(value, controlValueRange.lowerBound), controlValueRange.upperBound)
  }

  static func counterDiameter(for controlValue: CGFloat) -> CGFloat {
    12 + clampedControlValue(controlValue) * 4
  }

  static func controlValue(forCounterDiameter diameter: CGFloat) -> CGFloat {
    clampedControlValue((max(diameter, 16) - 12) / 4)
  }

  static func pixelatedBlurSize(for controlValue: CGFloat) -> CGFloat {
    6 + clampedControlValue(controlValue) * 2
  }

  static func gaussianBlurRadius(for controlValue: CGFloat) -> CGFloat {
    8 + clampedControlValue(controlValue) * 4
  }

  static func clampedOpacity(_ value: CGFloat) -> CGFloat {
    min(max(value, 0.05), 0.65)
  }

  static func clampedRotationDegrees(_ value: CGFloat) -> CGFloat {
    min(max(value, -45), 45)
  }
}

// MARK: - Hit Testing

extension AnnotationItem {
  var supportsResize: Bool {
    switch type {
    case .path(let points), .highlight(let points):
      return points.count > 1
    default:
      return true
    }
  }

  var resizeBounds: CGRect {
    switch type {
    case .arrow(let geometry):
      return geometry.bounds()
    case .line(let start, let end):
      return Self.normalizedBounds(Self.bounds(containing: [start, end]) ?? bounds)
    case .path(let points), .highlight(let points):
      return Self.normalizedBounds(Self.bounds(containing: points) ?? bounds)
    case .counter:
      let counterBounds = bounds.isEmpty ? Self.counterBounds(center: bounds.origin, properties: properties) : bounds
      return Self.normalizedBounds(counterBounds)
    default:
      return Self.normalizedBounds(bounds)
    }
  }

  var selectionBounds: CGRect {
    let padding = max(6, properties.strokeWidth / 2)
    return resizeBounds.insetBy(dx: -padding, dy: -padding)
  }

  /// Check if point hits this annotation with appropriate tolerance
  func containsPoint(_ point: CGPoint, baseTolerance: CGFloat = 6) -> Bool {
    let tolerance = baseTolerance + properties.strokeWidth / 2

    switch type {
    case .rectangle, .filledRectangle, .blur(_), .watermark, .embeddedImage:
      return bounds.contains(point)

    case .oval:
      return pointInEllipse(point, in: bounds)

    case .arrow(let geometry):
      return distanceToPolyline(point, points: geometry.sampledPoints()) <= tolerance

    case .line(let start, let end):
      return distanceToSegment(point, from: start, to: end) <= tolerance

    case .path(let points), .highlight(let points):
      let adjustedTolerance = type.isHighlight ? tolerance * 3 : tolerance
      return distanceToPolyline(point, points: points) <= adjustedTolerance

    case .text:
      return bounds.contains(point)

    case .counter:
      let counterBounds = bounds.isEmpty ? Self.counterBounds(center: bounds.origin, properties: properties) : bounds
      return pointInEllipse(point, in: counterBounds.insetBy(dx: -baseTolerance, dy: -baseTolerance))
    }
  }

  // MARK: - Geometry Helpers

  private static func bounds(containing points: [CGPoint]) -> CGRect? {
    guard let first = points.first else { return nil }

    var minX = first.x
    var maxX = first.x
    var minY = first.y
    var maxY = first.y

    for point in points.dropFirst() {
      minX = min(minX, point.x)
      maxX = max(maxX, point.x)
      minY = min(minY, point.y)
      maxY = max(maxY, point.y)
    }

    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).standardized
  }

  private static func normalizedBounds(_ rect: CGRect, minimumDimension: CGFloat = 1) -> CGRect {
    var normalized = rect.standardized

    if normalized.width < minimumDimension {
      normalized.origin.x -= (minimumDimension - normalized.width) / 2
      normalized.size.width = minimumDimension
    }

    if normalized.height < minimumDimension {
      normalized.origin.y -= (minimumDimension - normalized.height) / 2
      normalized.size.height = minimumDimension
    }

    return normalized
  }

  private func pointInEllipse(_ point: CGPoint, in rect: CGRect) -> Bool {
    let cx = rect.midX
    let cy = rect.midY
    let rx = rect.width / 2
    let ry = rect.height / 2

    guard rx > 0, ry > 0 else { return false }

    let dx = (point.x - cx) / rx
    let dy = (point.y - cy) / ry
    return (dx * dx + dy * dy) <= 1
  }

  private static func counterBounds(center: CGPoint, properties: AnnotationProperties) -> CGRect {
    let diameter = AnnotationProperties.counterDiameter(for: properties.strokeWidth)
    return CGRect(
      x: center.x - diameter / 2,
      y: center.y - diameter / 2,
      width: diameter,
      height: diameter
    )
  }

  private func distanceToSegment(_ point: CGPoint, from start: CGPoint, to end: CGPoint) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = dx * dx + dy * dy

    guard lengthSquared > 0 else {
      return hypot(point.x - start.x, point.y - start.y)
    }

    // Project point onto line, clamped to segment
    var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
    t = max(0, min(1, t))

    let projX = start.x + t * dx
    let projY = start.y + t * dy

    return hypot(point.x - projX, point.y - projY)
  }

  private func distanceToPolyline(_ point: CGPoint, points: [CGPoint]) -> CGFloat {
    guard points.count >= 2 else {
      if let first = points.first {
        return hypot(point.x - first.x, point.y - first.y)
      }
      return .infinity
    }

    var minDistance: CGFloat = .infinity
    for i in 0..<(points.count - 1) {
      let dist = distanceToSegment(point, from: points[i], to: points[i + 1])
      minDistance = min(minDistance, dist)
    }
    return minDistance
  }
}
