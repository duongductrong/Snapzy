//
//  ScreenRulerRaster.swift
//  Snapzy
//
//  Screen Ruler pixels: one display snapshot redrawn once into 8-bit sRGB RGBA bytes, so
//  edge scans walk whole rows and columns with plain byte reads.
//

import CoreGraphics
import Foundation

nonisolated final class ScreenRulerRaster: @unchecked Sendable {
  let width: Int
  let height: Int
  let bytesPerRow: Int
  private let bytes: [UInt8]

  private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

  init?(image: CGImage) {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }
    let bytesPerRow = width * 4
    var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard let context = CGContext(
        data: buffer.baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: Self.sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
      ) else { return false }
      context.interpolationQuality = .none
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return nil }
    self.width = width
    self.height = height
    self.bytesPerRow = bytesPerRow
    self.bytes = bytes
  }

  /// Largest per-channel difference between two pixels (top-left pixel coordinates).
  @inline(__always)
  func delta(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int) -> Int {
    let a = y1 * bytesPerRow + x1 * 4
    let b = y2 * bytesPerRow + x2 * 4
    return max(
      abs(Int(bytes[a]) - Int(bytes[b])),
      abs(Int(bytes[a + 1]) - Int(bytes[b + 1])),
      abs(Int(bytes[a + 2]) - Int(bytes[b + 2]))
    )
  }

  /// One channel (0 red, 1 green, 2 blue) of a pixel, top-left pixel coordinates.
  @inline(__always)
  func channel(_ x: Int, _ y: Int, _ channel: Int) -> Int {
    Int(bytes[y * bytesPerRow + x * 4 + channel])
  }

  /// Raw RGBA bytes for hot loops; the pointer is valid only inside `body`.
  func withPixels<R>(_ body: (UnsafePointer<UInt8>) throws -> R) rethrows -> R {
    try bytes.withUnsafeBufferPointer { try body($0.baseAddress!) }
  }

  func contains(_ pixel: ColorPickerPixel) -> Bool {
    pixel.x >= 0 && pixel.y >= 0 && pixel.x < width && pixel.y < height
  }
}
