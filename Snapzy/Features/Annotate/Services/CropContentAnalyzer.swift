//
//  CropContentAnalyzer.swift
//  Snapzy
//
//  Deterministic image edge analysis for crop border-snapping and auto-crop.
//  Pure functions over CGImage pixels; safe to call off-main (Task.detached).
//

import CoreGraphics
import Foundation

enum CropContentAnalyzer {

  // MARK: - Edge profile

  /// Detect content borders of `image` and return their positions in image
  /// points (bottom-left origin, the `cropRect` coordinate space).
  ///
  /// The image is rasterized once at a capped analysis resolution, adjacent
  /// pixel-pair gradients are accumulated per column/row (stride-sampled),
  /// and peaks are extracted with a relative threshold plus non-maximum
  /// suppression. The image-bounds edges (0 / width / height) are always
  /// included with strength 0.
  ///
  /// - Parameters:
  ///   - image: source pixels.
  ///   - imagePointSize: point size the crop rect is expressed in
  ///     (`NSImage.size`); differs from pixel size on retina captures.
  ///   - maxAnalysisDimension: cap for the analysis raster; never upscales.
  nonisolated static func edgeProfile(
    for image: CGImage,
    imagePointSize: CGSize,
    maxAnalysisDimension: Int = 1024
  ) -> CropEdgeProfile? {
    let pixelWidth = image.width
    let pixelHeight = image.height
    guard pixelWidth > 1, pixelHeight > 1,
          imagePointSize.width > 0, imagePointSize.height > 0 else { return nil }

    let downscale = min(1, CGFloat(maxAnalysisDimension) / CGFloat(max(pixelWidth, pixelHeight)))
    let analysisWidth = max(2, Int((CGFloat(pixelWidth) * downscale).rounded()))
    let analysisHeight = max(2, Int((CGFloat(pixelHeight) * downscale).rounded()))
    guard let pixels = rasterize(image, width: analysisWidth, height: analysisHeight) else { return nil }

    let columnStrengths = lineStrengths(pixels: pixels, width: analysisWidth, height: analysisHeight, axis: .vertical)
    let rowStrengths = lineStrengths(pixels: pixels, width: analysisWidth, height: analysisHeight, axis: .horizontal)

    // Analysis px -> image points. Vertical edges map linearly; horizontal
    // edges flip Y because the raster is top-down but points are bottom-up.
    let xScale = imagePointSize.width / CGFloat(analysisWidth)
    let yScale = imagePointSize.height / CGFloat(analysisHeight)
    let vertical = extractPeaks(strengths: columnStrengths, dimension: analysisWidth)
      .map { (position: CGFloat($0.index + 1) * xScale, strength: $0.strength) }
    let horizontal = extractPeaks(strengths: rowStrengths, dimension: analysisHeight)
      .map { (position: imagePointSize.height - CGFloat($0.index + 1) * yScale, strength: $0.strength) }

    let verticalMerged = mergedEdges(vertical, bounds: [0, imagePointSize.width])
    let horizontalMerged = mergedEdges(horizontal, bounds: [0, imagePointSize.height])
    return CropEdgeProfile(
      verticalEdges: verticalMerged.map(\.position),
      horizontalEdges: horizontalMerged.map(\.position),
      verticalStrengths: verticalMerged.map(\.strength),
      horizontalStrengths: horizontalMerged.map(\.strength)
    )
  }

  // MARK: - Rasterization

  private enum Axis { case vertical, horizontal }

  /// Draw the image into an RGBA buffer at the analysis size. Buffer row 0 is
  /// the image top row (CGBitmapContext draw preserves top-down order).
  /// Premultiplied RGB keeps transparent pixels from adding phantom RGB edges.
  private nonisolated static func rasterize(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    let didDraw = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
      guard let baseAddress = rawBuffer.baseAddress,
            let context = CGContext(
              data: baseAddress, width: width, height: height,
              bitsPerComponent: 8, bytesPerRow: bytesPerRow,
              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo
            ) else { return false }
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    return didDraw ? pixels : nil
  }

  // MARK: - Gradient strengths

  /// Mean per-pixel gradient magnitude between adjacent lines (columns for
  /// `.vertical`, rows for `.horizontal`), stride-sampled along each line.
  /// Entry `i` is the border between line `i` and `i + 1`; alpha counts
  /// double so transparency transitions register as strong borders.
  private nonisolated static func lineStrengths(
    pixels: [UInt8], width: Int, height: Int, axis: Axis
  ) -> [CGFloat] {
    let borderCount = (axis == .vertical ? width : height) - 1
    let lineLength = axis == .vertical ? height : width
    let sampleStride = max(1, lineLength / 512)
    var strengths = [CGFloat](repeating: 0, count: borderCount)
    var sampled = 0
    for t in Swift.stride(from: 0, to: lineLength, by: sampleStride) {
      sampled += 1
      for i in 0..<borderCount {
        let a = (axis == .vertical ? (t * width + i) : (i * width + t)) * 4
        let b = a + (axis == .vertical ? 4 : width * 4)
        let delta = abs(Int(pixels[a]) - Int(pixels[b]))
          + abs(Int(pixels[a + 1]) - Int(pixels[b + 1]))
          + abs(Int(pixels[a + 2]) - Int(pixels[b + 2]))
          + 2 * abs(Int(pixels[a + 3]) - Int(pixels[b + 3]))
        strengths[i] += CGFloat(delta)
      }
    }
    guard sampled > 0 else { return strengths }
    return strengths.map { $0 / CGFloat(sampled) }
  }

  // MARK: - Peak extraction

  /// Mean per-pixel gradient below which a border is treated as noise.
  private static let noiseFloor: CGFloat = 255 * 3 * 0.05

  /// Peak indices with strength >= max(20% of max strength, noise floor),
  /// non-maximum suppressed: descending strength, keep only peaks farther
  /// than `minSeparation` analysis px from every already-kept peak.
  private nonisolated static func extractPeaks(
    strengths: [CGFloat], dimension: Int
  ) -> [(index: Int, strength: CGFloat)] {
    guard let maxStrength = strengths.max() else { return [] }
    let threshold = max(0.2 * maxStrength, noiseFloor)
    let minSeparation = max(2, dimension / 256)
    var kept: [(index: Int, strength: CGFloat)] = []
    for (index, strength) in strengths.enumerated().sorted(by: { $0.element > $1.element })
    where strength >= threshold {
      if kept.allSatisfy({ abs($0.index - index) > minSeparation }) {
        kept.append((index, strength))
      }
    }
    return kept
  }

  // MARK: - Edge assembly

  /// Union detected peaks with the image-bounds edges (strength 0), sorted
  /// ascending and deduplicated within 0.5 pt (stronger edge wins).
  private nonisolated static func mergedEdges(
    _ peaks: [(position: CGFloat, strength: CGFloat)], bounds: [CGFloat]
  ) -> [(position: CGFloat, strength: CGFloat)] {
    let all = (peaks + bounds.map { ($0, CGFloat(0)) }).sorted { $0.position < $1.position }
    var merged: [(position: CGFloat, strength: CGFloat)] = []
    for edge in all {
      if let last = merged.last, edge.position - last.position <= 0.5 {
        if edge.strength > last.strength { merged[merged.count - 1] = edge }
      } else {
        merged.append(edge)
      }
    }
    return merged
  }
}
