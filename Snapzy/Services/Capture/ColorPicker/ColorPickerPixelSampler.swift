//
//  ColorPickerPixelSampler.swift
//  Snapzy
//
//  Pixel-exact helpers for Pick Color: maps view points to snapshot pixels, cuts the
//  neighborhood the loupe magnifies, and reads a pixel's color converted to sRGB.
//

import CoreGraphics
import Foundation

/// A pixel in a snapshot image, top-left origin (CGImage convention).
nonisolated struct ColorPickerPixel: Equatable {
  var x: Int
  var y: Int
}

/// A sampled color, 8-bit sRGB.
nonisolated struct ColorPickerColor: Equatable {
  let red: UInt8
  let green: UInt8
  let blue: UInt8

  var hex: String {
    String(format: "#%02X%02X%02X", red, green, blue)
  }

  var rgbDescription: String {
    "\(red), \(green), \(blue)"
  }

  var cgColor: CGColor {
    CGColor(
      srgbRed: CGFloat(red) / 255,
      green: CGFloat(green) / 255,
      blue: CGFloat(blue) / 255,
      alpha: 1
    )
  }

  /// Relative luminance, used to pick a readable outline over the sampled color.
  var isLight: Bool {
    (0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue)) / 255 > 0.6
  }
}

nonisolated enum ColorPickerPixelSampler {
  private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

  /// Pixel under `point`, where `point` is in a view whose `bounds` show `image` stretched
  /// to fill (AppKit, bottom-left origin).
  static func pixel(at point: CGPoint, bounds: CGRect, imageWidth: Int, imageHeight: Int) -> ColorPickerPixel {
    guard bounds.width > 0, bounds.height > 0 else { return ColorPickerPixel(x: 0, y: 0) }
    let scaleX = CGFloat(imageWidth) / bounds.width
    let scaleY = CGFloat(imageHeight) / bounds.height
    let x = Int(floor((point.x - bounds.minX) * scaleX))
    let y = Int(floor((bounds.maxY - point.y) * scaleY))
    return clamp(ColorPickerPixel(x: x, y: y), imageWidth: imageWidth, imageHeight: imageHeight)
  }

  /// Center of `pixel` in the same view coordinates `pixel(at:...)` reads.
  static func point(forCenterOf pixel: ColorPickerPixel, bounds: CGRect, imageWidth: Int, imageHeight: Int) -> CGPoint {
    let scaleX = imageWidth > 0 ? bounds.width / CGFloat(imageWidth) : 1
    let scaleY = imageHeight > 0 ? bounds.height / CGFloat(imageHeight) : 1
    return CGPoint(
      x: bounds.minX + (CGFloat(pixel.x) + 0.5) * scaleX,
      y: bounds.maxY - (CGFloat(pixel.y) + 0.5) * scaleY
    )
  }

  static func clamp(_ pixel: ColorPickerPixel, imageWidth: Int, imageHeight: Int) -> ColorPickerPixel {
    ColorPickerPixel(
      x: min(max(pixel.x, 0), max(imageWidth - 1, 0)),
      y: min(max(pixel.y, 0), max(imageHeight - 1, 0))
    )
  }

  /// The `(2 * radius + 1)²` pixels centered on `pixel`, with black where the window runs
  /// off the image. Keeps the snapshot's color space so the loupe renders exactly what the
  /// display showed.
  static func neighborhood(of pixel: ColorPickerPixel, radius: Int, in image: CGImage) -> CGImage? {
    let side = radius * 2 + 1
    guard side > 0 else { return nil }
    let colorSpace = image.colorSpace.flatMap { $0.supportsOutput ? $0 : nil } ?? sRGB
    guard let context = CGContext(
      data: nil,
      width: side,
      height: side,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) ?? CGContext(
      data: nil,
      width: side,
      height: side,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: sRGB,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.interpolationQuality = .none
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))

    let window = CGRect(x: pixel.x - radius, y: pixel.y - radius, width: side, height: side)
    let visible = window.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    if !visible.isNull, !visible.isEmpty, let crop = image.cropping(to: visible) {
      // `window`/`visible` are top-left based; the context draws bottom-left based.
      let drawRect = CGRect(
        x: visible.minX - window.minX,
        y: window.maxY - visible.maxY,
        width: visible.width,
        height: visible.height
      )
      context.draw(crop, in: drawRect)
    }
    return context.makeImage()
  }

  /// `pixel`'s color converted from the snapshot's color space (the display profile) to sRGB,
  /// the space hex colors are written in.
  static func color(of pixel: ColorPickerPixel, in image: CGImage) -> ColorPickerColor? {
    let clamped = clamp(pixel, imageWidth: image.width, imageHeight: image.height)
    guard image.width > 0, image.height > 0,
          let crop = image.cropping(to: CGRect(x: clamped.x, y: clamped.y, width: 1, height: 1)),
          let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
          ) else { return nil }

    context.setRenderingIntent(.relativeColorimetric)
    context.interpolationQuality = .none
    context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    guard let data = context.data else { return nil }
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    return ColorPickerColor(red: bytes[0], green: bytes[1], blue: bytes[2])
  }
}
