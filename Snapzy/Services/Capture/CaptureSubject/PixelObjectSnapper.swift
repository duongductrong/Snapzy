//
//  PixelObjectSnapper.swift
//  Snapzy
//
//  PixelSnap-style object bounds: flood-fill background from the search
//  corners, then return the tight box of the remaining pixels.
//

import CoreGraphics
import Foundation

enum PixelObjectSnapper: Sendable {
  struct Options: Equatable, Sendable {
    /// Per-channel RGB delta for background flood-fill. High on purpose so
    /// noisy or slightly shaded backgrounds still peel away from the object.
    var colorTolerance: UInt8 = 112
    var minSide: Int = 4
    var minArea: Int = 16
    /// If remaining content covers this much of the search rect, treat it as
    /// "no distinct object" and leave the original selection alone.
    var fullFillRatio: CGFloat = 0.995
    var maxAnalysisDimension: Int = 512
  }

  /// Tight object box inside `searchRect`, in the image's top-left pixel space.
  /// Returns nil when no distinct inset object is found.
  nonisolated static func objectBounds(
    in image: CGImage,
    searchRect: CGRect,
    options: Options = Options()
  ) -> CGRect? {
    let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let clamped = searchRect.integral.intersection(imageBounds)
    guard clamped.width >= CGFloat(options.minSide),
          clamped.height >= CGFloat(options.minSide) else { return nil }

    guard let cropped = image.cropping(to: clamped) else { return nil }

    let downscale = min(
      1,
      CGFloat(options.maxAnalysisDimension) / CGFloat(max(cropped.width, cropped.height))
    )
    let analysisWidth = max(2, Int((CGFloat(cropped.width) * downscale).rounded()))
    let analysisHeight = max(2, Int((CGFloat(cropped.height) * downscale).rounded()))
    guard let pixels = rasterize(cropped, width: analysisWidth, height: analysisHeight) else {
      return nil
    }

    guard let local = tightBounds(
      pixels: pixels,
      width: analysisWidth,
      height: analysisHeight,
      options: options
    ) else { return nil }

    let scaleX = clamped.width / CGFloat(analysisWidth)
    let scaleY = clamped.height / CGFloat(analysisHeight)
    let mapped = CGRect(
      x: clamped.minX + local.minX * scaleX,
      y: clamped.minY + local.minY * scaleY,
      width: local.width * scaleX,
      height: local.height * scaleY
    ).integral.intersection(clamped)

    guard mapped.width >= CGFloat(options.minSide),
          mapped.height >= CGFloat(options.minSide) else { return nil }
    return mapped
  }

  // MARK: - Rasterization

  private nonisolated static func rasterize(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    let didDraw = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
      guard let baseAddress = rawBuffer.baseAddress,
            let context = CGContext(
              data: baseAddress,
              width: width,
              height: height,
              bitsPerComponent: 8,
              bytesPerRow: bytesPerRow,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: bitmapInfo
            ) else { return false }
      context.interpolationQuality = .none
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    return didDraw ? pixels : nil
  }

  // MARK: - Flood fill

  private nonisolated static func tightBounds(
    pixels: [UInt8],
    width: Int,
    height: Int,
    options: Options
  ) -> CGRect? {
    let count = width * height
    var isBackground = [UInt8](repeating: 0, count: count)
    let corners = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
    for corner in corners {
      floodFill(
        pixels: pixels,
        isBackground: &isBackground,
        width: width,
        height: height,
        startX: corner.0,
        startY: corner.1,
        tolerance: options.colorTolerance
      )
    }

    var minX = width
    var minY = height
    var maxX = -1
    var maxY = -1
    var contentCount = 0
    for y in 0..<height {
      let row = y * width
      for x in 0..<width {
        if isBackground[row + x] == 0 {
          contentCount += 1
          if x < minX { minX = x }
          if y < minY { minY = y }
          if x > maxX { maxX = x }
          if y > maxY { maxY = y }
        }
      }
    }

    guard contentCount >= options.minArea,
          maxX >= minX, maxY >= minY else { return nil }
    let boxWidth = maxX - minX + 1
    let boxHeight = maxY - minY + 1
    guard boxWidth >= options.minSide, boxHeight >= options.minSide else { return nil }

    let fillRatio = CGFloat(contentCount) / CGFloat(count)
    if fillRatio >= options.fullFillRatio { return nil }

    return CGRect(x: minX, y: minY, width: boxWidth, height: boxHeight)
  }

  private nonisolated static func floodFill(
    pixels: [UInt8],
    isBackground: inout [UInt8],
    width: Int,
    height: Int,
    startX: Int,
    startY: Int,
    tolerance: UInt8
  ) {
    let startIndex = startY * width + startX
    if isBackground[startIndex] != 0 { return }

    let refOffset = startIndex * 4
    let refR = pixels[refOffset]
    let refG = pixels[refOffset + 1]
    let refB = pixels[refOffset + 2]
    let limit = Int(tolerance)

    var stack = [startIndex]
    isBackground[startIndex] = 1

    while !stack.isEmpty {
      let index = stack.removeLast()
      let x = index % width
      let y = index / width
      let neighbors = [
        x > 0 ? index - 1 : -1,
        x + 1 < width ? index + 1 : -1,
        y > 0 ? index - width : -1,
        y + 1 < height ? index + width : -1,
      ]
      for neighbor in neighbors where neighbor >= 0 {
        if isBackground[neighbor] != 0 { continue }
        let offset = neighbor * 4
        if abs(Int(pixels[offset]) - Int(refR)) > limit { continue }
        if abs(Int(pixels[offset + 1]) - Int(refG)) > limit { continue }
        if abs(Int(pixels[offset + 2]) - Int(refB)) > limit { continue }
        isBackground[neighbor] = 1
        stack.append(neighbor)
      }
    }
  }
}
