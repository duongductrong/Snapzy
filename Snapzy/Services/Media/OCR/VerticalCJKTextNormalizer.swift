//
//  VerticalCJKTextNormalizer.swift
//  Snapzy
//
//  Builds a horizontal OCR recovery image from upright CJK glyphs arranged vertically.
//

import CoreGraphics
import Foundation

nonisolated enum VerticalCJKTextNormalizer {
  static func normalizedImage(from image: CGImage) -> CGImage? {
    guard image.height >= Int(Double(image.width) * 1.35), image.width >= 16, image.height >= 64 else {
      return nil
    }

    guard let bitmap = VerticalCJKBitmap(image: image) else { return nil }
    let background = bitmap.estimatedBackgroundColor()
    let rowData = bitmap.foregroundRows(background: background)
    let bands = mergeDetachedGlyphStrokes(rowBands(from: rowData, imageHeight: image.height))
    guard (2...32).contains(bands.count) else { return nil }

    let cropPadding = max(3, min(image.width, image.height) / 48)
    let paddedBands = bands.map { $0.padded(by: cropPadding, width: image.width, height: image.height) }
    guard hasCJKLikeGlyphBands(paddedBands) else { return nil }

    let tallestBand = paddedBands.map(\.height).max() ?? 0
    guard tallestBand >= 8 else { return nil }

    let outerPadding = max(10, tallestBand / 5)
    let interGlyphGap = max(8, tallestBand / 6)
    let normalizedWidth = paddedBands.map(\.width).reduce(outerPadding * 2, +)
      + interGlyphGap * max(paddedBands.count - 1, 0)
    let normalizedHeight = tallestBand + outerPadding * 2

    guard
      normalizedWidth > normalizedHeight,
      let context = makeContext(width: normalizedWidth, height: normalizedHeight)
    else {
      return nil
    }

    context.setFillColor(background.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: normalizedWidth, height: normalizedHeight))

    var x = outerPadding
    for band in paddedBands {
      guard let crop = image.cropping(to: band.cropRect) else { continue }
      let y = (normalizedHeight - band.height) / 2
      context.draw(crop, in: CGRect(x: x, y: y, width: band.width, height: band.height))
      x += band.width + interGlyphGap
    }

    return context.makeImage()
  }

  private static func rowBands(from rowData: [VerticalCJKForegroundRow], imageHeight: Int) -> [VerticalCJKGlyphBand] {
    let mergeableGap = max(3, imageHeight / 80)
    let minimumBandHeight = max(6, imageHeight / 96)
    var bands: [VerticalCJKGlyphBand] = []
    var activeBand: VerticalCJKGlyphBand?
    var emptyRowCount = 0

    for row in rowData {
      if row.hasInk {
        if var band = activeBand {
          band.endY = row.y
          band.minX = min(band.minX, row.minX)
          band.maxX = max(band.maxX, row.maxX)
          activeBand = band
        } else {
          activeBand = VerticalCJKGlyphBand(startY: row.y, endY: row.y, minX: row.minX, maxX: row.maxX)
        }
        emptyRowCount = 0
      } else if let band = activeBand {
        emptyRowCount += 1
        if emptyRowCount > mergeableGap {
          let finishedBand = band.trimmingTrailingGap(emptyRowCount)
          if finishedBand.height >= minimumBandHeight {
            bands.append(finishedBand)
          }
          activeBand = nil
          emptyRowCount = 0
        }
      }
    }

    if let activeBand {
      let finishedBand = activeBand.trimmingTrailingGap(emptyRowCount)
      if finishedBand.height >= minimumBandHeight {
        bands.append(finishedBand)
      }
    }

    return bands
  }

  private static func mergeDetachedGlyphStrokes(_ bands: [VerticalCJKGlyphBand]) -> [VerticalCJKGlyphBand] {
    guard bands.count > 2 else { return bands }

    let sortedHeights = bands.map(\.height).sorted()
    let medianHeight = sortedHeights[sortedHeights.count / 2]
    let smallStrokeHeight = max(6, Int(Double(medianHeight) * 0.45))
    let closeStrokeGap = max(8, Int(Double(medianHeight) * 0.35))
    let maximumMergedHeight = max(medianHeight + closeStrokeGap, Int(Double(medianHeight) * 1.9))
    var merged: [VerticalCJKGlyphBand] = []
    var index = 0

    while index < bands.count {
      var current = bands[index]

      while index + 1 < bands.count {
        let next = bands[index + 1]
        let gap = next.startY - current.endY - 1
        let hasSmallDetachedStroke = current.height <= smallStrokeHeight || next.height <= smallStrokeHeight
        let mergedHeight = next.endY - current.startY + 1

        guard hasSmallDetachedStroke, gap <= closeStrokeGap, mergedHeight <= maximumMergedHeight else {
          break
        }

        current = current.merged(with: next)
        index += 1
      }

      merged.append(current)
      index += 1
    }

    return merged
  }

  private static func makeContext(width: Int, height: Int) -> CGContext? {
    CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: VerticalCJKBitmapFormat.rgbaBitmapInfo
    )
  }

  private static func hasCJKLikeGlyphBands(_ bands: [VerticalCJKGlyphBand]) -> Bool {
    let glyphLikeCount = bands.filter { band in
      guard band.width >= 8, band.height >= 8 else { return false }
      let aspectRatio = Double(band.width) / Double(band.height)
      return (0.35...1.75).contains(aspectRatio)
    }.count

    return glyphLikeCount >= max(2, Int(ceil(Double(bands.count) * 0.65)))
  }
}
