//
//  PixelMeasurement.swift
//  SnapzyMeasureCore
//
//  Screen Ruler values: what was measured (a span around a pixel or a box), in which unit,
//  and how it reads as text.
//

import CoreGraphics
import Foundation

/// Which directions a span measures.
public enum MeasureAxis: String, Equatable, CaseIterable, Sendable {
  case both
  case horizontal
  case vertical
}

public enum MeasureUnit: String, CaseIterable, Sendable {
  /// Logical points (pixels divided by the display's backing scale).
  case points
  /// Physical display pixels.
  case pixels

  public var suffix: String {
    switch self {
    case .points: return "pt"
    case .pixels: return "px"
    }
  }

  public var toggled: MeasureUnit {
    self == .points ? .pixels : .points
  }
}

/// Inclusive pixel rectangle, top-left origin.
public struct MeasurePixelRect: Equatable, Sendable {
  public var minX: Int
  public var minY: Int
  public var maxX: Int
  public var maxY: Int

  public var width: Int { maxX - minX + 1 }
  public var height: Int { maxY - minY + 1 }

  /// The rectangle spanned by two corner pixels in any order.
  public init(corner a: MeasurePixel, _ b: MeasurePixel) {
    minX = min(a.x, b.x)
    maxX = max(a.x, b.x)
    minY = min(a.y, b.y)
    maxY = max(a.y, b.y)
  }

  public init(minX: Int, minY: Int, maxX: Int, maxY: Int) {
    self.minX = minX
    self.minY = minY
    self.maxX = maxX
    self.maxY = maxY
  }
}

/// The run of matching pixels around `origin`. `left`…`right` and `top`…`bottom` are the
/// last pixels that still match the origin color, so lengths are inclusive.
public struct MeasureSpan: Equatable, Sendable {
  public var origin: MeasurePixel
  public var axis: MeasureAxis
  public var left: Int
  public var right: Int
  public var top: Int
  public var bottom: Int

  public var width: Int? { axis == .vertical ? nil : right - left + 1 }
  public var height: Int? { axis == .horizontal ? nil : bottom - top + 1 }

  public init(origin: MeasurePixel, axis: MeasureAxis, left: Int, right: Int, top: Int, bottom: Int) {
    self.origin = origin
    self.axis = axis
    self.left = left
    self.right = right
    self.top = top
    self.bottom = bottom
  }
}

public enum PixelMeasurement: Equatable, Sendable {
  case span(MeasureSpan)
  case box(MeasurePixelRect)

  public var pixelWidth: Int? {
    switch self {
    case .span(let span): return span.width
    case .box(let rect): return rect.width
    }
  }

  public var pixelHeight: Int? {
    switch self {
    case .span(let span): return span.height
    case .box(let rect): return rect.height
    }
  }
}

public enum MeasureFormatter {
  /// `pixels` in `unit`: whole numbers without decimals, otherwise one decimal (`120.5`).
  public static func value(pixels: Int, scale: CGFloat, unit: MeasureUnit) -> String {
    let amount: Double
    switch unit {
    case .pixels: amount = Double(pixels)
    case .points: amount = scale > 0 ? Double(pixels) / Double(scale) : Double(pixels)
    }
    let rounded = (amount * 10).rounded() / 10
    if rounded == rounded.rounded() {
      return String(Int(rounded))
    }
    return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded)
  }

  /// `120 × 48`, or a single value when only one axis was measured. Widths convert with
  /// `scaleX`, heights with `scaleY`.
  public static func label(
    for measurement: PixelMeasurement,
    scaleX: CGFloat,
    scaleY: CGFloat,
    unit: MeasureUnit
  ) -> String {
    let parts = [
      measurement.pixelWidth.map { value(pixels: $0, scale: scaleX, unit: unit) },
      measurement.pixelHeight.map { value(pixels: $0, scale: scaleY, unit: unit) },
    ]
    return parts.compactMap { $0 }.joined(separator: " × ")
  }

  public static func label(for measurement: PixelMeasurement, scale: CGFloat, unit: MeasureUnit) -> String {
    label(for: measurement, scaleX: scale, scaleY: scale, unit: unit)
  }

  /// What Copy puts on the pasteboard: the label plus its unit, e.g. `120 × 48 pt`.
  public static func copyText(
    for measurement: PixelMeasurement,
    scaleX: CGFloat,
    scaleY: CGFloat,
    unit: MeasureUnit
  ) -> String {
    "\(label(for: measurement, scaleX: scaleX, scaleY: scaleY, unit: unit)) \(unit.suffix)"
  }

  public static func copyText(for measurement: PixelMeasurement, scale: CGFloat, unit: MeasureUnit) -> String {
    copyText(for: measurement, scaleX: scale, scaleY: scale, unit: unit)
  }
}
