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

  /// Create a solid grayscale background with additional grayscale-filled
  /// rects. Rects use pixel coordinates with a top-left origin (row 0 = top
  /// row) and are clipped to the image; later fills paint over earlier ones.
  static func solidWithRects(
    width: Int,
    height: Int,
    backgroundGray: UInt8 = 255,
    rects: [(rect: CGRect, gray: UInt8)]
  ) -> CGImage? {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    for i in 0..<(width * height) {
      let offset = i * 4
      pixels[offset] = backgroundGray
      pixels[offset + 1] = backgroundGray
      pixels[offset + 2] = backgroundGray
      pixels[offset + 3] = 255
    }

    for entry in rects {
      let minX = max(0, Int(entry.rect.minX.rounded(.down)))
      let minY = max(0, Int(entry.rect.minY.rounded(.down)))
      let maxX = min(width, Int(entry.rect.maxX.rounded(.up)))
      let maxY = min(height, Int(entry.rect.maxY.rounded(.up)))
      guard minX < maxX, minY < maxY else { continue }

      for y in minY..<maxY {
        for x in minX..<maxX {
          let offset = y * bytesPerRow + x * 4
          pixels[offset] = entry.gray
          pixels[offset + 1] = entry.gray
          pixels[offset + 2] = entry.gray
          pixels[offset + 3] = 255
        }
      }
    }

    return makeCGImage(width: width, height: height, bytesPerRow: bytesPerRow, pixels: pixels)
  }

  /// Checkerboard background with optional solid rects painted on top.
  /// Adjacent cells differ by `oddGray - evenGray`, so a flood-fill whose
  /// color tolerance sits between that delta and the object contrast will
  /// peel the noise and still keep the object.
  static func checkerboardWithRects(
    width: Int,
    height: Int,
    evenGray: UInt8,
    oddGray: UInt8,
    rects: [(rect: CGRect, gray: UInt8)] = []
  ) -> CGImage? {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    for y in 0..<height {
      for x in 0..<width {
        let gray = ((x + y) % 2 == 0) ? evenGray : oddGray
        let offset = y * bytesPerRow + x * 4
        pixels[offset] = gray
        pixels[offset + 1] = gray
        pixels[offset + 2] = gray
        pixels[offset + 3] = 255
      }
    }

    for entry in rects {
      let minX = max(0, Int(entry.rect.minX.rounded(.down)))
      let minY = max(0, Int(entry.rect.minY.rounded(.down)))
      let maxX = min(width, Int(entry.rect.maxX.rounded(.up)))
      let maxY = min(height, Int(entry.rect.maxY.rounded(.up)))
      guard minX < maxX, minY < maxY else { continue }

      for y in minY..<maxY {
        for x in minX..<maxX {
          let offset = y * bytesPerRow + x * 4
          pixels[offset] = entry.gray
          pixels[offset + 1] = entry.gray
          pixels[offset + 2] = entry.gray
          pixels[offset + 3] = 255
        }
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

  /// Create a hard vertical luminance edge for resampling assertions.
  static func verticalEdge(
    width: Int,
    height: Int,
    edgeX: Int? = nil,
    leftGray: UInt8 = 0,
    rightGray: UInt8 = 255
  ) -> CGImage? {
    let splitX = min(max(edgeX ?? width / 2, 0), width)
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    for y in 0..<height {
      for x in 0..<width {
        let gray = x < splitX ? leftGray : rightGray
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

  /// Create a frame for scrolling-capture tests where each row has a
  /// deterministic color signature based on its logical content position.
  /// Two frames with overlapping logical ranges produce pixel-perfect overlap,
  /// yielding deterministic `appended` outcomes with an exact `deltaY`.
  static func scrollingFrame(
    width: Int,
    height: Int,
    logicalYOffset: Int = 0
  ) -> CGImage? {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    for y in 0..<height {
      let logicalY = logicalYOffset + y
      // Deterministic, high-variation row color
      let r = UInt8(logicalY % 256)
      let g = UInt8((logicalY * 47) % 256)
      let b = UInt8((logicalY * 113) % 256)

      for x in 0..<width {
        let offset = y * bytesPerRow + x * 4
        pixels[offset] = r
        pixels[offset + 1] = g
        pixels[offset + 2] = b
        pixels[offset + 3] = 255
      }
    }

    return makeCGImage(width: width, height: height, bytesPerRow: bytesPerRow, pixels: pixels)
  }

  /// Create a soft-edged dark radial blob on a uniform background. The edge
  /// falloff is wide enough that per-pixel-pair gradients stay below the edge
  /// detector's noise floor, so `CropContentAnalyzer` finds no content borders
  /// (used to force the Vision fallback path in auto-crop tests). `center` is
  /// in pixel coordinates with a top-left origin (row 0 = top row).
  static func softRadialBlob(
    width: Int,
    height: Int,
    backgroundGray: UInt8 = 242,
    blobGray: UInt8 = 40,
    center: CGPoint,
    radius: Double,
    falloff: Double = 40
  ) -> CGImage? {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    for y in 0..<height {
      for x in 0..<width {
        let distance = hypot(Double(x) - Double(center.x), Double(y) - Double(center.y))
        let f = min(max((radius - distance) / falloff, 0), 1)
        let gray = UInt8((Double(backgroundGray) + (Double(blobGray) - Double(backgroundGray)) * f).rounded())
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
