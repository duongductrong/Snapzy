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
    case .pixelated: return "Pixelated"
    case .gaussian: return "Gaussian"
    }
  }

  var icon: String {
    switch self {
    case .pixelated: return "square.grid.3x3"
    case .gaussian: return "drop.halffull"
    }
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
  case oval
  case arrow(start: CGPoint, end: CGPoint)
  case line(start: CGPoint, end: CGPoint)
  case text(String)
  case highlight([CGPoint])
  case blur(BlurType)
  case counter(Int)
}

/// Visual properties for an annotation
struct AnnotationProperties: Equatable {
  var strokeColor: Color
  var fillColor: Color
  var strokeWidth: CGFloat
  var fontSize: CGFloat
  var fontName: String

  init(
    strokeColor: Color = .red,
    fillColor: Color = .clear,
    strokeWidth: CGFloat = 3,
    fontSize: CGFloat = 16,
    fontName: String = "SF Pro"
  ) {
    self.strokeColor = strokeColor
    self.fillColor = fillColor
    self.strokeWidth = strokeWidth
    self.fontSize = fontSize
    self.fontName = fontName
  }
}

// MARK: - Hit Testing

extension AnnotationItem {
  /// Check if point hits this annotation with appropriate tolerance
  func containsPoint(_ point: CGPoint, baseTolerance: CGFloat = 6) -> Bool {
    let tolerance = baseTolerance + properties.strokeWidth / 2

    switch type {
    case .rectangle, .blur(_):
      return bounds.contains(point)

    case .oval:
      return pointInEllipse(point, in: bounds)

    case .arrow(let start, let end), .line(let start, let end):
      return distanceToSegment(point, from: start, to: end) <= tolerance

    case .path(let points), .highlight(let points):
      let adjustedTolerance = type.isHighlight ? tolerance * 3 : tolerance
      return distanceToPolyline(point, points: points) <= adjustedTolerance

    case .text:
      return bounds.contains(point)

    case .counter:
      let center = CGPoint(x: bounds.midX, y: bounds.midY)
      let radius: CGFloat = 12 + baseTolerance
      return hypot(point.x - center.x, point.y - center.y) <= radius
    }
  }

  // MARK: - Geometry Helpers

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
