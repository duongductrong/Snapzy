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
  /// Repeating visual bands plus a unique interior marker so false overlap can
  /// be distinguished from a genuine known-step delta.
  static func repeatedScrollingFrame(
    width: Int,
    height: Int,
    logicalYOffset: Int,
    period: Int = 48
  ) -> CGImage? {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let safePeriod = max(8, period)

    for y in 0..<height {
      let logicalY = logicalYOffset + y
      let phase = logicalY % safePeriod
      let repeatingR = UInt8((phase * 17) % 200 + 20)
      let repeatingG = UInt8((phase * 43) % 200 + 20)
      let repeatingB = UInt8((phase * 89) % 200 + 20)
      let uniqueR = UInt8(logicalY % 256)
      let uniqueG = UInt8((logicalY * 47) % 256)
      let uniqueB = UInt8((logicalY * 113) % 256)

      for x in 0..<width {
        let offset = y * bytesPerRow + x * 4
        let useUniqueMarker = x >= 40 && x < 96
        pixels[offset] = useUniqueMarker ? uniqueR : repeatingR
        pixels[offset + 1] = useUniqueMarker ? uniqueG : repeatingG
        pixels[offset + 2] = useUniqueMarker ? uniqueB : repeatingB
        pixels[offset + 3] = 255
      }
    }

    return makeCGImage(width: width, height: height, bytesPerRow: bytesPerRow, pixels: pixels)
  }

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

  /// Create a scrolling frame whose rows carry contrast along their width, like
  /// text on a page. The bottom `fadeDepth` rows are washed toward white, the
  /// way pages fade content that sits against the bottom of a scroll view.
  static func texturedScrollingFrame(
    width: Int,
    height: Int,
    logicalYOffset: Int,
    fadeDepth: Int = 0,
    fadeStrength: Double = 0.6
  ) -> CGImage? {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    for y in 0..<height {
      let logicalY = logicalYOffset + y
      let distanceFromBottom = height - 1 - y
      let fade = fadeDepth > 0 && distanceFromBottom < fadeDepth
        ? fadeStrength * Double(fadeDepth - distanceFromBottom) / Double(fadeDepth)
        : 0

      for x in 0..<width {
        let cell = (logicalY &* 73_856_093) ^ ((x / 6) &* 19_349_663)
        let base = Double(abs(cell) % 200 + 28)
        let value = UInt8((base + (255 - base) * fade).rounded())
        let offset = y * bytesPerRow + x * 4
        pixels[offset] = value
        pixels[offset + 1] = UInt8((Int(value) * 7 / 8))
        pixels[offset + 2] = UInt8((Int(value) * 3 / 4))
        pixels[offset + 3] = 255
      }
    }

    return makeCGImage(width: width, height: height, bytesPerRow: bytesPerRow, pixels: pixels)
  }

  /// Create a textured scrolling frame with fixed chrome: a header across the
  /// top and a footer along the bottom. When `footerChromeWidth` is set, only
  /// that many trailing columns of the footer are fixed, like a floating
  /// banner, and content scrolls past beside it.
  static func chromeScrollingFrame(
    width: Int,
    height: Int,
    logicalYOffset: Int,
    headerHeight: Int,
    footerHeight: Int,
    footerChromeWidth: Int? = nil
  ) -> CGImage? {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let footerTop = height - footerHeight
    let chromeStartColumn = width - (footerChromeWidth ?? width)

    for y in 0..<height {
      for x in 0..<width {
        let cell: Int
        if y < headerHeight {
          cell = (y &* 2_654_435_761) ^ ((x / 5) &* 40_503)
        } else if y >= footerTop, x >= chromeStartColumn {
          cell = ((y - footerTop) &* 97_531) ^ ((x / 7) &* 2_246_822_519)
        } else {
          cell = ((logicalYOffset + y) &* 73_856_093) ^ ((x / 6) &* 19_349_663)
        }
        let value = UInt8(abs(cell) % 200 + 28)
        let offset = y * bytesPerRow + x * 4
        pixels[offset] = value
        pixels[offset + 1] = UInt8(Int(value) * 7 / 8)
        pixels[offset + 2] = UInt8(Int(value) * 3 / 4)
        pixels[offset + 3] = 255
      }
    }

    return makeCGImage(width: width, height: height, bytesPerRow: bytesPerRow, pixels: pixels)
  }

  /// Create a frame of a whole app window: a fixed toolbar across the top, a
  /// fixed textured sidebar along the leading edge, and textured content
  /// scrolling beside it.
  static func windowScrollingFrame(
    width: Int,
    height: Int,
    logicalYOffset: Int,
    toolbarHeight: Int,
    sidebarWidth: Int
  ) -> CGImage? {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    for y in 0..<height {
      for x in 0..<width {
        let cell: Int
        if y < toolbarHeight {
          cell = (y &* 2_654_435_761) ^ ((x / 5) &* 40_503)
        } else if x < sidebarWidth {
          cell = ((y / 3) &* 1_103_515_245) ^ ((x / 4) &* 12_345)
        } else {
          cell = ((logicalYOffset + y) &* 73_856_093) ^ ((x / 6) &* 19_349_663)
        }
        let value = UInt8(abs(cell) % 200 + 28)
        let offset = y * bytesPerRow + x * 4
        pixels[offset] = value
        pixels[offset + 1] = UInt8(Int(value) * 7 / 8)
        pixels[offset + 2] = UInt8(Int(value) * 3 / 4)
        pixels[offset + 3] = 255
      }
    }

    return makeCGImage(width: width, height: height, bytesPerRow: bytesPerRow, pixels: pixels)
  }

  /// Create a frame of a mostly blank page: short lines of text-like texture
  /// every `lineSpacing` rows on a flat light background.
  static func sparseTextScrollingFrame(
    width: Int,
    height: Int,
    logicalYOffset: Int,
    lineSpacing: Int = 28,
    lineHeight: Int = 7
  ) -> CGImage? {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let margin = width / 12

    for y in 0..<height {
      let logicalY = logicalYOffset + y
      let line = logicalY / lineSpacing
      let isTextRow = logicalY % lineSpacing < lineHeight
      // Lines end at different lengths, like real paragraphs.
      let lineEnd = width - margin - (abs(line &* 2_654_435_761) % (width / 3))

      for x in 0..<width {
        var value: UInt8 = 244
        if isTextRow, x >= margin, x < lineEnd, (x / 9) % 5 != 4 {
          let cell = (logicalY &* 73_856_093) ^ ((x / 2) &* 19_349_663)
          value = UInt8(abs(cell) % 150 + 20)
        }
        let offset = y * bytesPerRow + x * 4
        pixels[offset] = value
        pixels[offset + 1] = value
        pixels[offset + 2] = value
        pixels[offset + 3] = 255
      }
    }

    return makeCGImage(width: width, height: height, bytesPerRow: bytesPerRow, pixels: pixels)
  }

  /// Create a page of centred content with wide blank margins and a thin fixed
  /// line down the leading edge, like a window border or a scrollbar track.
  static func centredColumnScrollingFrame(
    width: Int,
    height: Int,
    logicalYOffset: Int,
    edgeLineWidth: Int = 6
  ) -> CGImage? {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let columnStart = width * 5 / 16
    let columnEnd = width * 11 / 16

    for y in 0..<height {
      let logicalY = logicalYOffset + y
      let isTextRow = logicalY % 30 < 12
      for x in 0..<width {
        var value = 246
        if x < edgeLineWidth {
          value = 120
        } else if isTextRow, x >= columnStart, x < columnEnd, (x / 7) % 6 != 5 {
          value = abs((logicalY &* 73_856_093) ^ ((x / 3) &* 19_349_663)) % 170 + 20
        }
        let offset = y * bytesPerRow + x * 4
        pixels[offset] = UInt8(value)
        pixels[offset + 1] = UInt8(value)
        pixels[offset + 2] = UInt8(value)
        pixels[offset + 3] = 255
      }
    }

    return makeCGImage(width: width, height: height, bytesPerRow: bytesPerRow, pixels: pixels)
  }

  /// RGBA bytes of the first `rowCount` rows of `image`, drawn into a known
  /// pixel format so images from different sources compare byte for byte.
  static func rgbaRows(of image: CGImage, rowCount: Int) -> [UInt8] {
    let bytesPerRow = image.width * 4
    var pixels = [UInt8](repeating: 0, count: image.height * bytesPerRow)
    pixels.withUnsafeMutableBytes { buffer in
      let context = CGContext(
        data: buffer.baseAddress,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
      )
      context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return Array(pixels[0..<(min(rowCount, image.height) * bytesPerRow)])
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
