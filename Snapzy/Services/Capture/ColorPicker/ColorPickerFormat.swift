//
//  ColorPickerFormat.swift
//  Snapzy
//
//  The notations a picked color can be copied as. Values are computed from the 8-bit sRGB
//  sample, so every format describes exactly the pixel that was picked.
//

import Foundation

nonisolated enum ColorPickerFormat: String, CaseIterable, Identifiable {
  case hex
  case rgb
  case hsl
  case hsb
  case cmyk
  case oklch
  case swiftUI

  var id: String { rawValue }

  /// Technical notation names; intentionally not localized.
  var title: String {
    switch self {
    case .hex: return "HEX"
    case .rgb: return "RGB"
    case .hsl: return "HSL"
    case .hsb: return "HSB"
    case .cmyk: return "CMYK"
    case .oklch: return "OKLCH"
    case .swiftUI: return "SwiftUI"
    }
  }

  func string(for color: ColorPickerColor) -> String {
    switch self {
    case .hex:
      return color.hex
    case .rgb:
      return "rgb(\(color.red), \(color.green), \(color.blue))"
    case .hsl:
      let (h, s, l) = color.hsl
      return "hsl(\(Self.degrees(h)), \(Self.percent(s)), \(Self.percent(l)))"
    case .hsb:
      let (h, s, b) = color.hsb
      return "hsb(\(Self.degrees(h)), \(Self.percent(s)), \(Self.percent(b)))"
    case .cmyk:
      let (c, m, y, k) = color.cmyk
      return "cmyk(\(Self.percent(c)), \(Self.percent(m)), \(Self.percent(y)), \(Self.percent(k)))"
    case .oklch:
      let (l, c, h) = color.oklch
      // CSS Color 4 notation; an achromatic color has no meaningful hue.
      let hue = c < 0.0005 ? "0" : Self.decimal(h, places: 1)
      return "oklch(\(Self.decimal(l * 100, places: 1))% \(Self.decimal(c, places: 3)) \(hue))"
    case .swiftUI:
      let (r, g, b) = color.unitComponents
      return "Color(red: \(Self.decimal(r, places: 3)), green: \(Self.decimal(g, places: 3)), blue: \(Self.decimal(b, places: 3)))"
    }
  }

  private static func degrees(_ value: Double) -> String {
    "\(Int(value.rounded()) % 360)"
  }

  private static func percent(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
  }

  /// Fixed-point with a dot separator regardless of locale, then trailing zeros trimmed.
  private static func decimal(_ value: Double, places: Int) -> String {
    var string = String(format: "%.\(places)f", locale: Locale(identifier: "en_US_POSIX"), value)
    if string.contains(".") {
      while string.hasSuffix("0") { string.removeLast() }
      if string.hasSuffix(".") { string.removeLast() }
    }
    return string == "-0" ? "0" : string
  }
}

nonisolated extension ColorPickerColor {
  var unitComponents: (red: Double, green: Double, blue: Double) {
    (Double(red) / 255, Double(green) / 255, Double(blue) / 255)
  }

  /// Hue in degrees [0, 360), saturation and lightness in [0, 1].
  var hsl: (hue: Double, saturation: Double, lightness: Double) {
    let (r, g, b) = unitComponents
    let maxValue = max(r, g, b)
    let minValue = min(r, g, b)
    let delta = maxValue - minValue
    let lightness = (maxValue + minValue) / 2
    guard delta > 0 else { return (0, 0, lightness) }
    let saturation = delta / (1 - abs(2 * lightness - 1))
    return (Self.hue(r: r, g: g, b: b, maxValue: maxValue, delta: delta), saturation, lightness)
  }

  /// Hue in degrees [0, 360), saturation and brightness in [0, 1].
  var hsb: (hue: Double, saturation: Double, brightness: Double) {
    let (r, g, b) = unitComponents
    let maxValue = max(r, g, b)
    let delta = maxValue - min(r, g, b)
    guard delta > 0 else { return (0, 0, maxValue) }
    return (Self.hue(r: r, g: g, b: b, maxValue: maxValue, delta: delta), delta / maxValue, maxValue)
  }

  /// Naive (profile-free) CMYK, components in [0, 1].
  var cmyk: (cyan: Double, magenta: Double, yellow: Double, key: Double) {
    let (r, g, b) = unitComponents
    let key = 1 - max(r, g, b)
    guard key < 1 else { return (0, 0, 0, 1) }
    return ((1 - r - key) / (1 - key), (1 - g - key) / (1 - key), (1 - b - key) / (1 - key), key)
  }

  /// OKLCH (Björn Ottosson's OKLab): lightness in [0, 1], chroma, hue in degrees [0, 360).
  var oklch: (lightness: Double, chroma: Double, hue: Double) {
    let (r, g, b) = unitComponents
    let lr = Self.linearize(r)
    let lg = Self.linearize(g)
    let lb = Self.linearize(b)

    let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
    let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
    let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)

    let okL = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    let okA = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    let okB = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s

    let chroma = (okA * okA + okB * okB).squareRoot()
    var hue = atan2(okB, okA) * 180 / .pi
    if hue < 0 { hue += 360 }
    return (okL, chroma, hue)
  }

  private static func hue(r: Double, g: Double, b: Double, maxValue: Double, delta: Double) -> Double {
    var hue: Double
    if maxValue == r {
      hue = (g - b) / delta
    } else if maxValue == g {
      hue = (b - r) / delta + 2
    } else {
      hue = (r - g) / delta + 4
    }
    hue *= 60
    return hue < 0 ? hue + 360 : hue
  }

  private static func linearize(_ value: Double) -> Double {
    value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
  }
}

// MARK: - Preferences

/// What Pick Color remembers between picks: the notation a pick copies, and recent colors.
nonisolated struct ColorPickerPreferences {
  static let recentLimit = 8

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// The notation a pick puts on the clipboard. HEX unless the user chose another.
  var copyFormat: ColorPickerFormat {
    get {
      defaults.string(forKey: PreferencesKeys.colorPickerCopyFormat)
        .flatMap(ColorPickerFormat.init(rawValue:)) ?? .hex
    }
    nonmutating set {
      defaults.set(newValue.rawValue, forKey: PreferencesKeys.colorPickerCopyFormat)
    }
  }

  /// Newest first, without duplicates.
  var recentColors: [ColorPickerColor] {
    (defaults.stringArray(forKey: PreferencesKeys.colorPickerRecentColors) ?? [])
      .compactMap(ColorPickerColor.init(hex:))
  }

  /// Moves `color` to the front of the recent colors and returns the updated list.
  @discardableResult
  func recordRecent(_ color: ColorPickerColor) -> [ColorPickerColor] {
    let colors = Array(([color] + recentColors.filter { $0 != color }).prefix(Self.recentLimit))
    defaults.set(colors.map(\.hex), forKey: PreferencesKeys.colorPickerRecentColors)
    return colors
  }
}

nonisolated extension ColorPickerColor {
  /// Parses `#RRGGBB` or `RRGGBB`.
  init?(hex: String) {
    var digits = hex.trimmingCharacters(in: .whitespaces)
    if digits.hasPrefix("#") { digits.removeFirst() }
    guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
    self.init(
      red: UInt8((value >> 16) & 0xFF),
      green: UInt8((value >> 8) & 0xFF),
      blue: UInt8(value & 0xFF)
    )
  }
}
