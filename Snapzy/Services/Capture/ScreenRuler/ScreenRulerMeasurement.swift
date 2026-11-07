//
//  ScreenRulerMeasurement.swift
//  Snapzy
//
//  Screen Ruler values: what was measured (a span around a pixel or a box), in which unit,
//  and how it reads as text.
//

import CoreGraphics
import Foundation

/// Which directions a span measures.
nonisolated enum ScreenRulerAxis: Equatable {
  case both
  case horizontal
  case vertical
}

nonisolated enum ScreenRulerUnit: String, CaseIterable {
  /// Logical points (pixels divided by the display's backing scale).
  case points
  /// Physical display pixels.
  case pixels

  var suffix: String {
    switch self {
    case .points: return "pt"
    case .pixels: return "px"
    }
  }

  var toggled: ScreenRulerUnit {
    self == .points ? .pixels : .points
  }
}

/// Inclusive pixel rectangle, top-left origin.
nonisolated struct ScreenRulerPixelRect: Equatable {
  var minX: Int
  var minY: Int
  var maxX: Int
  var maxY: Int

  var width: Int { maxX - minX + 1 }
  var height: Int { maxY - minY + 1 }

  /// The rectangle spanned by two corner pixels in any order.
  init(corner a: ColorPickerPixel, _ b: ColorPickerPixel) {
    minX = min(a.x, b.x)
    maxX = max(a.x, b.x)
    minY = min(a.y, b.y)
    maxY = max(a.y, b.y)
  }

  init(minX: Int, minY: Int, maxX: Int, maxY: Int) {
    self.minX = minX
    self.minY = minY
    self.maxX = maxX
    self.maxY = maxY
  }
}

/// The run of matching pixels around `origin`. `left`…`right` and `top`…`bottom` are the
/// last pixels that still match the origin color, so lengths are inclusive.
nonisolated struct ScreenRulerSpan: Equatable {
  var origin: ColorPickerPixel
  var axis: ScreenRulerAxis
  var left: Int
  var right: Int
  var top: Int
  var bottom: Int

  var width: Int? { axis == .vertical ? nil : right - left + 1 }
  var height: Int? { axis == .horizontal ? nil : bottom - top + 1 }
}

nonisolated enum ScreenRulerMeasurement: Equatable {
  case span(ScreenRulerSpan)
  case box(ScreenRulerPixelRect)

  var pixelWidth: Int? {
    switch self {
    case .span(let span): return span.width
    case .box(let rect): return rect.width
    }
  }

  var pixelHeight: Int? {
    switch self {
    case .span(let span): return span.height
    case .box(let rect): return rect.height
    }
  }
}

nonisolated enum ScreenRulerFormatter {
  /// `pixels` in `unit`: whole numbers without decimals, otherwise one decimal (`120.5`).
  static func value(pixels: Int, scale: CGFloat, unit: ScreenRulerUnit) -> String {
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
  static func label(
    for measurement: ScreenRulerMeasurement,
    scaleX: CGFloat,
    scaleY: CGFloat,
    unit: ScreenRulerUnit
  ) -> String {
    let parts = [
      measurement.pixelWidth.map { value(pixels: $0, scale: scaleX, unit: unit) },
      measurement.pixelHeight.map { value(pixels: $0, scale: scaleY, unit: unit) },
    ]
    return parts.compactMap { $0 }.joined(separator: " × ")
  }

  static func label(for measurement: ScreenRulerMeasurement, scale: CGFloat, unit: ScreenRulerUnit) -> String {
    label(for: measurement, scaleX: scale, scaleY: scale, unit: unit)
  }

  /// What Copy puts on the pasteboard: the label plus its unit, e.g. `120 × 48 pt`.
  static func copyText(
    for measurement: ScreenRulerMeasurement,
    scaleX: CGFloat,
    scaleY: CGFloat,
    unit: ScreenRulerUnit
  ) -> String {
    "\(label(for: measurement, scaleX: scaleX, scaleY: scaleY, unit: unit)) \(unit.suffix)"
  }

  static func copyText(for measurement: ScreenRulerMeasurement, scale: CGFloat, unit: ScreenRulerUnit) -> String {
    copyText(for: measurement, scaleX: scale, scaleY: scale, unit: unit)
  }
}
