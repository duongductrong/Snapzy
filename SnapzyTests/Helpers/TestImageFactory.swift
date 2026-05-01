//
//  TestImageFactory.swift
//  SnapzyTests
//
//  Synthetic CGImage generator for unit tests.
//

import CoreGraphics
import Foundation

enum TestImageFactory {

  /// Create a solid-color CGImage of the given size.
  static func solidColor(
    width: Int,
    height: Int,
    red: UInt8 = 128,
    green: UInt8 = 128,
    blue: UInt8 = 128,
    alpha: UInt8 = 255
  ) -> CGImage? {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    for y in 0..<height {
      for x in 0..<width {
        let offset = y * bytesPerRow + x * 4
        pixels[offset] = red
        pixels[offset + 1] = green
        pixels[offset + 2] = blue
        pixels[offset + 3] = alpha
      }
    }

    return makeCGImage(width: width, height: height, bytesPerRow: bytesPerRow, pixels: pixels)
  }

  /// Create a vertical gradient image.
  /// Top row starts at `topGray`, bottom row ends at `bottomGray`.
  static func verticalGradient(
    width: Int,
    height: Int,
    topGray: UInt8 = 0,
    bottomGray: UInt8 = 255
  ) -> CGImage? {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    for y in 0..<height {
      let t = height > 1 ? Double(y) / Double(height - 1) : 0
      let gray = UInt8(Double(topGray) * (1 - t) + Double(bottomGray) * t)

      for x in 0..<width {
        let offset = y * bytesPerRow + x * 4
        pixels[offset] = gray
        pixels[offset + 1] = gray
        pixels[offset + 2] = gray
        pixels[offset + 3] = 255
      }
    }

    return makeCGImage(width: width, height: height, bytesPerRow: bytesPerRow, pixels: pixels)
  }

  /// Create an image that is a vertically shifted copy of a gradient.
  /// Simulates scroll by shifting `shiftPixels` rows down and filling
  /// the top with new content (incrementing gray values).
  static func shiftedGradient(
    width: Int,
    height: Int,
    topGray: UInt8 = 0,
    bottomGray: UInt8 = 255,
    shiftPixels: Int
  ) -> CGImage? {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    for y in 0..<height {
      // The shifted source row in the original gradient
      let sourceY = y + shiftPixels
      let t = height > 1 ? Double(sourceY) / Double(height - 1) : 0
      let gray = UInt8(max(0, min(255, Int(Double(topGray) * (1 - t) + Double(bottomGray) * t))))

      for x in 0..<width {
        let offset = y * bytesPerRow + x * 4
        pixels[offset] = gray
        pixels[offset + 1] = gray
        pixels[offset + 2] = gray
        pixels[offset + 3] = 255
      }
    }

    return makeCGImage(width: width, height: height, bytesPerRow: bytesPerRow, pixels: pixels)
  }

  // MARK: - Private

  private static func makeCGImage(
    width: Int,
    height: Int,
    bytesPerRow: Int,
    pixels: [UInt8]
  ) -> CGImage? {
    let data = Data(pixels) as CFData
    guard let provider = CGDataProvider(data: data) else { return nil }

    let bitmapInfo = CGBitmapInfo(rawValue:
      CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    )

    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: bitmapInfo,
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }
}
