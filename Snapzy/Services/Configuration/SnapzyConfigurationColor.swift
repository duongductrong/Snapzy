//
//  SnapzyConfigurationColor.swift
//  Snapzy
//
//  Hex color conversion for TOML config.
//

import AppKit
import Foundation

nonisolated enum SnapzyConfigurationColor {
  static func hexString(from color: NSColor) -> String {
    let srgb = color.usingColorSpace(.sRGB) ?? color
    let red = clampByte(srgb.redComponent)
    let green = clampByte(srgb.greenComponent)
    let blue = clampByte(srgb.blueComponent)
    let alpha = clampByte(srgb.alphaComponent)

    if alpha == 255 {
      return String(format: "#%02X%02X%02X", red, green, blue)
    }
    return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
  }

  static func color(from hex: String) -> NSColor? {
    let value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.hasPrefix("#") else { return nil }

    let body = String(value.dropFirst())
    guard body.count == 6 || body.count == 8,
          let raw = UInt64(body, radix: 16) else {
      return nil
    }

    let red: UInt64
    let green: UInt64
    let blue: UInt64
    let alpha: UInt64

    if body.count == 6 {
      red = (raw >> 16) & 0xff
      green = (raw >> 8) & 0xff
      blue = raw & 0xff
      alpha = 0xff
    } else {
      red = (raw >> 24) & 0xff
      green = (raw >> 16) & 0xff
      blue = (raw >> 8) & 0xff
      alpha = raw & 0xff
    }

    return NSColor(
      srgbRed: CGFloat(red) / 255,
      green: CGFloat(green) / 255,
      blue: CGFloat(blue) / 255,
      alpha: CGFloat(alpha) / 255
    )
  }

  private static func clampByte(_ value: CGFloat) -> Int {
    Int((min(max(value, 0), 1) * 255).rounded())
  }
}
