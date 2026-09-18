//
//  ScrollingCaptureEdgeDimmingDetector.swift
//  Snapzy
//
//  Measures how deep a page fades or dims content near the bottom edge of a
//  scrolling viewport, so stitched strips can be cut from above that band.
//

import CoreGraphics
import Foundation

/// 8-bit luma copy of a frame for cheap row comparisons.
/// Row 0 is the top row of the image.
nonisolated struct ScrollingCaptureLumaPlane {
  let width: Int
  let height: Int
  private let pixels: [UInt8]

  init(width: Int, height: Int, pixels: [UInt8]) {
    self.width = width
    self.height = height
    self.pixels = pixels
  }

  /// Builds the plane from a premultiplied RGBA buffer whose first row is the
  /// top row of the image.
  init(rgbaPixels: [UInt8], width: Int, height: Int, bytesPerRow: Int) {
    var luma = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
      let sourceRow = y * bytesPerRow
      let destinationRow = y * width
      for x in 0..<width {
        let index = sourceRow + x * 4
        let value =
          Int(rgbaPixels[index]) * 299 +
          Int(rgbaPixels[index + 1]) * 587 +
          Int(rgbaPixels[index + 2]) * 114
        luma[destinationRow + x] = UInt8(value / 1000)
      }
    }
    self.init(width: width, height: height, pixels: luma)
  }

  init?(cgImage: CGImage) {
    let width = cgImage.width
    let height = cgImage.height
    guard width > 0, height > 0 else { return nil }

    var buffer = [UInt8](repeating: 0, count: width * height)
    let drew = buffer.withUnsafeMutableBytes { rawBuffer -> Bool in
      guard
        let context = CGContext(
          data: rawBuffer.baseAddress,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width,
          space: CGColorSpaceCreateDeviceGray(),
          bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
      else {
        return false
      }
      // The bitmap buffer starts at the image's top-left pixel even though the
      // context draws with a bottom-left origin, so no flip is needed.
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drew else { return nil }
    self.init(width: width, height: height, pixels: buffer)
  }

  func value(x: Int, y: Int) -> Int {
    guard x >= 0, y >= 0, x < width, y < height else { return 0 }
    return Int(pixels[y * width + x])
  }
}

nonisolated enum ScrollingCaptureEdgeDimmingDetector {
  /// Mean luma difference above which a row counts as drawn differently.
  static let differenceThreshold = 5.0
  /// Contrast a sample needs along its row before it says anything; flat
  /// background reads the same whether it is dimmed or not.
  static let contrastFloor = 12
  /// Contrasty samples a row needs before it is judged at all.
  static let minimumContrastySamples = 6
  /// Undimmed rows tolerated inside the band before it is called finished, so
  /// a paragraph gap inside a faded region does not end the measurement.
  static let maximumGapRows = 60

  /// Content near the bottom of `previous` sits `offset` rows higher in
  /// `current`. Where the two copies disagree, the page drew that content
  /// differently while it was near the edge.
  ///
  /// - Returns: rows above the bottom of the content area that the page draws
  ///   differently, or nil when the frames cannot answer.
  static func dimmedDepth(
    previous: ScrollingCaptureLumaPlane,
    current: ScrollingCaptureLumaPlane,
    offset: Int,
    headerHeight: Int = 0,
    footerHeight: Int = 0,
    xStart: Int = 0,
    xEnd: Int? = nil,
    maximumFraction: Double = 0.4
  ) -> Int? {
    guard offset > 0, previous.width == current.width, previous.height == current.height else {
      return nil
    }

    let columnStart = max(0, xStart)
    let columnEnd = min(previous.width, xEnd ?? previous.width)
    let columnSpan = columnEnd - columnStart
    guard columnSpan > 1 else { return nil }

    let bottom = previous.height - footerHeight
    let limit = min(
      Int(Double(previous.height) * maximumFraction),
      bottom - headerHeight - offset
    )
    guard limit > 0 else { return nil }
    let columnStep = max(1, columnSpan / 80)

    /// nil when the row carries too little contrast to judge.
    func wasDrawnDifferently(rowInPrevious row: Int) -> Bool? {
      let matchingRow = row - offset
      guard matchingRow >= headerHeight else { return nil }

      var contrasty = 0
      var total = 0
      for column in stride(from: columnStart, to: columnEnd, by: columnStep) {
        let value = previous.value(x: column, y: row)
        let neighbour = previous.value(x: min(columnEnd - 1, column + columnStep), y: row)
        guard abs(value - neighbour) >= contrastFloor else { continue }
        contrasty += 1
        total += abs(value - current.value(x: column, y: matchingRow))
      }
      guard contrasty >= minimumContrastySamples else { return nil }
      return Double(total) / Double(contrasty) > differenceThreshold
    }

    var depth = 0
    var gap = 0
    for rowsUp in 0..<limit {
      switch wasDrawnDifferently(rowInPrevious: bottom - 1 - rowsUp) {
      case .some(true):
        depth = rowsUp + 1
        gap = 0
      case .some(false):
        gap += 1
        if gap > maximumGapRows { return depth }
      case .none:
        continue
      }
    }
    return depth
  }
}
