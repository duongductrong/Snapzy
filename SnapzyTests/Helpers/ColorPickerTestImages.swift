//
//  ColorPickerTestImages.swift
//  SnapzyTests
//
//  Synthetic images shared by the Pick Color tests.
//

import CoreGraphics
import Foundation

enum ColorPickerTestImages {
  static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

  static func splitImage(width: Int, height: Int) -> CGImage {
    image(width: width, height: height, colorSpace: sRGB) { x, _ in
      x < width / 2 ? (255, 0, 0) : (0, 0, 255)
    }
  }

  /// `pixel(x, y)` uses top-left pixel coordinates, like `ColorPickerPixel`.
  static func image(
    width: Int,
    height: Int,
    colorSpace: CGColorSpace,
    pixel: (Int, Int) -> (UInt8, UInt8, UInt8)
  ) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let (r, g, b) = pixel(x, y)
        let offset = (y * width + x) * 4
        bytes[offset] = r
        bytes[offset + 1] = g
        bytes[offset + 2] = b
      }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )!
  }
}
