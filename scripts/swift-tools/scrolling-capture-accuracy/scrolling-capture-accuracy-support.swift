//
//  scrolling-capture-accuracy-support.swift
//  Snapzy
//
//  Synthetic corpus and pixel metrics for Scroll Capture accuracy benchmark.
//

import AppKit
import Foundation

struct ScrollAccuracyBenchmarkCase {
  let name: String
  let width: Int
  let viewportHeight: Int
  let contentHeight: Int
  let headerHeight: Int
  let footerHeight: Int
  let offsets: [Int]
  let minimumOverallAccuracy: Double

  var movingViewportHeight: Int {
    viewportHeight - headerHeight - footerHeight
  }
}

struct ScrollAccuracyMetrics {
  let exactAccuracy: Double
  let overallAccuracy: Double
  let meanAbsoluteError: Double
  let maxSeamError: Double
}

struct ScrollAccuracyBenchmarkResult {
  let name: String
  let frameCount: Int
  let appendedCount: Int
  let failedCount: Int
  let outputHeight: Int
  let expectedHeight: Int
  let metrics: ScrollAccuracyMetrics
  let averageConfidence: Double
  let passed: Bool
}

struct ScrollAccuracyRGBA {
  let width: Int
  let height: Int
  let bytesPerRow: Int
  let pixels: [UInt8]

  init?(cgImage: CGImage) {
    let imageWidth = cgImage.width
    let imageHeight = cgImage.height
    let imageBytesPerRow = imageWidth * 4
    var buffer = [UInt8](repeating: 0, count: imageHeight * imageBytesPerRow)
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    let drew = buffer.withUnsafeMutableBytes { rawBuffer -> Bool in
      guard let baseAddress = rawBuffer.baseAddress else { return false }
      guard let context = CGContext(
        data: baseAddress,
        width: imageWidth,
        height: imageHeight,
        bitsPerComponent: 8,
        bytesPerRow: imageBytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo
      ) else { return false }
      context.interpolationQuality = .none
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
      return true
    }
    guard drew else { return nil }
    width = imageWidth
    height = imageHeight
    bytesPerRow = imageBytesPerRow
    pixels = buffer
  }
}

enum ScrollAccuracyFixture {
  static func frame(for benchmark: ScrollAccuracyBenchmarkCase, offset: Int) -> CGImage? {
    makeImage(width: benchmark.width, height: benchmark.viewportHeight) { x, y in
      if y < benchmark.headerHeight {
        return staticPixel(x: x, y: y, salt: 17)
      }

      if y >= benchmark.viewportHeight - benchmark.footerHeight {
        return staticPixel(x: x, y: y, salt: 91)
      }

      return contentPixel(x: x, logicalY: offset + y - benchmark.headerHeight)
    }
  }

  static func expectedImage(for benchmark: ScrollAccuracyBenchmarkCase) -> CGImage? {
    let expectedHeight = benchmark.movingViewportHeight + (benchmark.offsets.last ?? 0)
    guard expectedHeight <= benchmark.contentHeight else { return nil }
    return makeImage(width: benchmark.width, height: expectedHeight) { x, y in
      contentPixel(x: x, logicalY: y)
    }
  }

  static func seamRows(for benchmark: ScrollAccuracyBenchmarkCase) -> [Int] {
    guard benchmark.offsets.count > 1 else { return [] }
    return benchmark.offsets.dropLast().map { benchmark.movingViewportHeight + $0 }
  }

  private static func makeImage(
    width: Int,
    height: Int,
    pixel: (_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8)
  ) -> CGImage? {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    for y in 0..<height {
      for x in 0..<width {
        let color = pixel(x, y)
        let index = y * bytesPerRow + x * 4
        pixels[index] = color.0
        pixels[index + 1] = color.1
        pixels[index + 2] = color.2
        pixels[index + 3] = 255
      }
    }

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

  private static func contentPixel(x: Int, logicalY: Int) -> (UInt8, UInt8, UInt8) {
    let value = UInt64(logicalY) &* 1_103_515_245
      &+ UInt64(x) &* 2_654_435_761
      &+ 0x9E37_79B9_7F4A_7C15
    let mixed = value ^ (value >> 29) ^ (value >> 47)
    return (
      UInt8(truncatingIfNeeded: mixed),
      UInt8(truncatingIfNeeded: mixed >> 11),
      UInt8(truncatingIfNeeded: mixed >> 23)
    )
  }

  private static func staticPixel(x: Int, y: Int, salt: Int) -> (UInt8, UInt8, UInt8) {
    let value = UInt64(x + salt) &* 97 &+ UInt64(y + salt) &* 53
    return (
      UInt8(truncatingIfNeeded: 36 + value % 120),
      UInt8(truncatingIfNeeded: 42 + (value >> 2) % 110),
      UInt8(truncatingIfNeeded: 48 + (value >> 4) % 100)
    )
  }
}
