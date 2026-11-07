//
//  VerticalCJKBitmapAnalysis.swift
//  Snapzy
//
//  Bitmap foreground helpers for vertical CJK OCR recovery.
//

import CoreGraphics
import Foundation

nonisolated enum VerticalCJKBitmapFormat {
  static let rgbaBitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
    | CGImageAlphaInfo.premultipliedLast.rawValue
}

nonisolated struct VerticalCJKBitmap {
  let width: Int
  let height: Int
  let bytesPerRow: Int
  let pixels: [UInt8]

  init?(image: CGImage) {
    let imageWidth = image.width
    let imageHeight = image.height
    let imageBytesPerRow = imageWidth * 4
    width = imageWidth
    height = imageHeight
    bytesPerRow = imageBytesPerRow
    var data = [UInt8](repeating: 0, count: imageBytesPerRow * imageHeight)

    let didDraw = data.withUnsafeMutableBytes { bytes -> Bool in
      guard
        let baseAddress = bytes.baseAddress,
        let context = CGContext(
          data: baseAddress,
          width: imageWidth,
          height: imageHeight,
          bitsPerComponent: 8,
          bytesPerRow: imageBytesPerRow,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: VerticalCJKBitmapFormat.rgbaBitmapInfo
        )
      else {
        return false
      }

      context.draw(image, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
      return true
    }

    guard didDraw else { return nil }
    pixels = data
  }

  func estimatedBackgroundColor() -> VerticalCJKRGBColor {
    let step = max(1, min(width, height) / 80)
    var redTotal = 0
    var greenTotal = 0
    var blueTotal = 0
    var sampleCount = 0

    func addSample(x: Int, y: Int) {
      let color = colorAt(x: x, y: y)
      redTotal += color.red
      greenTotal += color.green
      blueTotal += color.blue
      sampleCount += 1
    }

    for x in stride(from: 0, to: width, by: step) {
      addSample(x: x, y: 0)
      addSample(x: x, y: height - 1)
    }
    for y in stride(from: 0, to: height, by: step) {
      addSample(x: 0, y: y)
      addSample(x: width - 1, y: y)
    }

    guard sampleCount > 0 else { return VerticalCJKRGBColor(red: 255, green: 255, blue: 255) }
    return VerticalCJKRGBColor(
      red: redTotal / sampleCount,
      green: greenTotal / sampleCount,
      blue: blueTotal / sampleCount
    )
  }

  func foregroundRows(background: VerticalCJKRGBColor) -> [VerticalCJKForegroundRow] {
    let minimumInkPixels = max(2, width / 25)
    return (0..<height).map { y in
      var inkCount = 0
      var minX = width
      var maxX = 0

      for x in 0..<width where isForeground(x: x, y: y, background: background) {
        inkCount += 1
        minX = min(minX, x)
        maxX = max(maxX, x)
      }

      let hasInk = inkCount >= minimumInkPixels
      return VerticalCJKForegroundRow(y: y, hasInk: hasInk, minX: hasInk ? minX : width, maxX: hasInk ? maxX : 0)
    }
  }

  private func isForeground(x: Int, y: Int, background: VerticalCJKRGBColor) -> Bool {
    let color = colorAt(x: x, y: y)
    let colorDistance = abs(color.red - background.red)
      + abs(color.green - background.green)
      + abs(color.blue - background.blue)
    let luminanceDelta = abs(color.luminance - background.luminance)

    return colorDistance >= 58 || luminanceDelta >= 34
  }

  private func colorAt(x: Int, y: Int) -> VerticalCJKRGBColor {
    let offset = (y * bytesPerRow) + (x * 4)
    return VerticalCJKRGBColor(
      red: Int(pixels[offset]),
      green: Int(pixels[offset + 1]),
      blue: Int(pixels[offset + 2])
    )
  }
}

nonisolated struct VerticalCJKForegroundRow {
  let y: Int
  let hasInk: Bool
  let minX: Int
  let maxX: Int
}

nonisolated struct VerticalCJKGlyphBand {
  var startY: Int
  var endY: Int
  var minX: Int
  var maxX: Int

  var width: Int { maxX - minX + 1 }
  var height: Int { endY - startY + 1 }
  var cropRect: CGRect { CGRect(x: minX, y: startY, width: width, height: height) }

  func trimmingTrailingGap(_ gap: Int) -> VerticalCJKGlyphBand {
    VerticalCJKGlyphBand(startY: startY, endY: max(startY, endY - gap), minX: minX, maxX: maxX)
  }

  func merged(with other: VerticalCJKGlyphBand) -> VerticalCJKGlyphBand {
    VerticalCJKGlyphBand(
      startY: min(startY, other.startY),
      endY: max(endY, other.endY),
      minX: min(minX, other.minX),
      maxX: max(maxX, other.maxX)
    )
  }

  func padded(by padding: Int, width imageWidth: Int, height imageHeight: Int) -> VerticalCJKGlyphBand {
    VerticalCJKGlyphBand(
      startY: max(0, startY - padding),
      endY: min(imageHeight - 1, endY + padding),
      minX: max(0, minX - padding),
      maxX: min(imageWidth - 1, maxX + padding)
    )
  }
}

nonisolated struct VerticalCJKRGBColor {
  let red: Int
  let green: Int
  let blue: Int

  var luminance: Int {
    Int((Double(red) * 0.299) + (Double(green) * 0.587) + (Double(blue) * 0.114))
  }

  var cgColor: CGColor {
    CGColor(
      red: CGFloat(red) / 255,
      green: CGFloat(green) / 255,
      blue: CGFloat(blue) / 255,
      alpha: 1
    )
  }
}
