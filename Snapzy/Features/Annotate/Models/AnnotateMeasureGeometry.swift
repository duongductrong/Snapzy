//
//  AnnotateMeasureGeometry.swift
//  Snapzy
//
//  What a Measure annotation remembers. The measured extent is the item's `bounds` (image
//  points, bottom-left origin): a box is exactly its bounds, a span runs edge to edge across
//  them through `origin`. Labels are computed from the bounds, the source pixel density at
//  measuring time and the unit, so a saved measurement reads the same after export or reopen
//  without scanning pixels again.
//

import CoreGraphics
import Foundation
import SnapzyMeasureCore

nonisolated struct MeasureSegment: Equatable {
  var start: CGPoint
  var end: CGPoint
}

nonisolated struct MeasureGeometry: Equatable {
  enum Kind: String {
    case span
    case box
  }

  var kind: Kind
  /// Which directions a span measures. Boxes always measure both.
  var axis: MeasureAxis
  /// Span only: where the measuring lines cross, in image points. Always inside `bounds`.
  var origin: CGPoint
  /// Source pixels per point when measured (x, y), so values stay in source pixels after crop.
  var pixelScale: CGSize
  var unit: MeasureUnit

  static func span(axis: MeasureAxis, origin: CGPoint, pixelScale: CGSize, unit: MeasureUnit) -> MeasureGeometry {
    MeasureGeometry(kind: .span, axis: axis, origin: origin, pixelScale: pixelScale, unit: unit)
  }

  static func box(pixelScale: CGSize, unit: MeasureUnit) -> MeasureGeometry {
    MeasureGeometry(kind: .box, axis: .both, origin: .zero, pixelScale: pixelScale, unit: unit)
  }

  var measuresWidth: Bool { kind == .box || axis != .vertical }
  var measuresHeight: Bool { kind == .box || axis != .horizontal }

  /// The measuring lines of a span across `bounds`. Boxes draw their outline instead.
  func segments(in bounds: CGRect) -> [MeasureSegment] {
    guard kind == .span else { return [] }
    var segments: [MeasureSegment] = []
    if measuresWidth {
      segments.append(MeasureSegment(
        start: CGPoint(x: bounds.minX, y: origin.y),
        end: CGPoint(x: bounds.maxX, y: origin.y)
      ))
    }
    if measuresHeight {
      segments.append(MeasureSegment(
        start: CGPoint(x: origin.x, y: bounds.minY),
        end: CGPoint(x: origin.x, y: bounds.maxY)
      ))
    }
    return segments
  }

  /// Source pixels covered by `bounds` on each measured axis.
  func pixelSize(of bounds: CGRect) -> (width: Int?, height: Int?) {
    (
      measuresWidth ? Int((bounds.width * max(pixelScale.width, 0.01)).rounded()) : nil,
      measuresHeight ? Int((bounds.height * max(pixelScale.height, 0.01)).rounded()) : nil
    )
  }

  /// `120 × 48 pt`, or one value for a single-axis span.
  func label(for bounds: CGRect) -> String {
    let size = pixelSize(of: bounds)
    let values = [
      size.width.map { MeasureFormatter.value(pixels: $0, scale: pixelScale.width, unit: unit) },
      size.height.map { MeasureFormatter.value(pixels: $0, scale: pixelScale.height, unit: unit) },
    ].compactMap { $0 }
    return "\(values.joined(separator: " × ")) \(unit.suffix)"
  }

  func translated(dx: CGFloat, dy: CGFloat) -> MeasureGeometry {
    var copy = self
    copy.origin = CGPoint(x: origin.x + dx, y: origin.y + dy)
    return copy
  }

  /// After a quarter turn of the image: the origin moves with the image and the axes swap.
  func rotated(_ rotatePoint: (CGPoint) -> CGPoint) -> MeasureGeometry {
    var copy = self
    copy.origin = rotatePoint(origin)
    copy.pixelScale = CGSize(width: pixelScale.height, height: pixelScale.width)
    switch axis {
    case .horizontal: copy.axis = .vertical
    case .vertical: copy.axis = .horizontal
    case .both: break
    }
    return copy
  }

  /// The span's bounds for a scan result: zero-thickness on an unmeasured axis.
  static func spanBounds(axis: MeasureAxis, origin: CGPoint, horizontal: ClosedRange<CGFloat>, vertical: ClosedRange<CGFloat>) -> CGRect {
    let minX = axis == .vertical ? origin.x : horizontal.lowerBound
    let maxX = axis == .vertical ? origin.x : horizontal.upperBound
    let minY = axis == .horizontal ? origin.y : vertical.lowerBound
    let maxY = axis == .horizontal ? origin.y : vertical.upperBound
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }
}
