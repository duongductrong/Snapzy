//
//  PPOCRDetector.swift
//  Snapzy
//
//  PP-OCR text detection: DB preprocess, ONNX run, box post-processing.
//

import CoreGraphics
import Foundation
import OnnxRuntimeBindings

/// Preprocess → det inference → DB post-processing.
///
/// Parameters mirror the model's inference.yml: `DetResizeForTest` defaults
/// (limit_side_len=736, limit_type=min, plus an app-level 2560px cap on the
/// longer side), `NormalizeImage` mean/std, and `DBPostProcess` thresh=0.2 /
/// box_thresh=0.4 / unclip_ratio=1.4.
enum PPOCRDetector {
  private static let limitSideLength: CGFloat = 736
  /// Longer-side cap: keeps 5K Retina captures from producing giant tensors
  /// while staying under the model's 4000px HPI limit.
  private static let maxSideLength: CGFloat = 2560
  private static let binarizeThreshold: Float = 0.2
  private static let boxThreshold: Float = 0.4
  private static let unclipRatio: CGFloat = 1.4
  private static let maxCandidates = 3000
  private static let minComponentPixels = 3
  /// PaddleOCR `DBPostProcess.min_size`: mini-boxes thinner than this in
  /// probability-map pixels are dropped before unclip.
  private static let minBoxSize: CGFloat = 3

  /// Runs detection on `image`, returning boxes in original-image pixel
  /// coordinates (top-left origin), filtered and in reading order.
  static func detectBoxes(in image: CGImage, session: ORTSession) throws -> [PPOCRTextBox] {
    let targetSize = resizedDimensions(width: image.width, height: image.height)
    guard let tensor = PPOCRImageTensor.makeNCHW(
      from: image,
      size: targetSize,
      normalize: .detection
    ) else {
      throw OCRError.imageConversionFailed
    }
    let probabilities = try PPOCRTensorRunner.run(
      session: session,
      tensor: tensor,
      shape: [1, 3, Int(targetSize.height), Int(targetSize.width)]
    )
    return postprocess(
      probabilities: probabilities,
      mapWidth: Int(targetSize.width),
      mapHeight: Int(targetSize.height),
      originalWidth: image.width,
      originalHeight: image.height
    )
  }

  /// limit_type=min: upscale until the smaller side reaches 736 (no downscale
  /// when already larger); the longer side is then capped at 2560, the cap
  /// taking precedence over the upscale; both dims rounded to a multiple of
  /// 32, min 32.
  static func resizedDimensions(width: Int, height: Int) -> CGSize {
    var ratio: CGFloat = 1
    let smaller = min(width, height)
    if smaller < Int(limitSideLength) {
      ratio = limitSideLength / CGFloat(smaller)
    }
    let larger = max(width, height)
    if CGFloat(larger) * ratio > maxSideLength {
      ratio = maxSideLength / CGFloat(larger)
    }
    let resizeWidth = max(32, Int((CGFloat(width) * ratio / 32).rounded() * 32))
    let resizeHeight = max(32, Int((CGFloat(height) * ratio / 32).rounded() * 32))
    return CGSize(width: resizeWidth, height: resizeHeight)
  }

  /// Binarize → connected components → score filter → minimum-area mini-box →
  /// unclip → clip to bounds, reading-order sort.
  static func postprocess(
    probabilities: [Float],
    mapWidth: Int,
    mapHeight: Int,
    originalWidth: Int,
    originalHeight: Int
  ) -> [PPOCRTextBox] {
    let pixelCount = mapWidth * mapHeight
    guard probabilities.count >= pixelCount, pixelCount > 0 else { return [] }
    let binary = (0..<pixelCount).map { probabilities[$0] > binarizeThreshold }
    let components = PPOCRBoxUtils.connectedComponents(
      binary: binary,
      probability: probabilities,
      width: mapWidth,
      height: mapHeight,
      minPixelCount: minComponentPixels
    )
    let scaleX = CGFloat(originalWidth) / CGFloat(mapWidth)
    let scaleY = CGFloat(originalHeight) / CGFloat(mapHeight)
    let imageBounds = CGRect(x: 0, y: 0, width: originalWidth, height: originalHeight)

    // Fitting happens in original-image coordinates rather than map
    // coordinates: `resizedDimensions` rounds each side to its own multiple of
    // 32, so scaling a fitted rectangle afterwards would shear it.
    let minFittedSize = minBoxSize * min(scaleX, scaleY)

    var boxes: [PPOCRTextBox] = []
    for component in components.prefix(maxCandidates) {
      let score = component.meanProbability
      guard score >= boxThreshold else { continue }
      let points = component.boundaryPoints.map {
        CGPoint(x: $0.x * scaleX, y: $0.y * scaleY)
      }
      guard let fitted = PPOCRBoxUtils.minAreaRect(points),
            min(fitted.size.width, fitted.size.height) >= minFittedSize
      else { continue }
      let expanded = PPOCRBoxUtils.unclipped(fitted, ratio: unclipRatio)
      // The oriented box stays unclipped so a skewed crop keeps its full
      // extent; only the axis-aligned bounds handed downstream are clamped.
      let bounds = expanded.boundingRect.intersection(imageBounds)
      guard bounds.width >= 2, bounds.height >= 2 else { continue }
      boxes.append(PPOCRTextBox(rotated: expanded, rect: bounds, score: score))
    }
    return PPOCRBoxUtils.readingOrder(boxes)
  }
}
