//
//  PPOCRRecognizer.swift
//  Snapzy
//
//  PP-OCR text recognition: crop, resize h=48, ONNX run, CTC greedy decode.
//

import CoreGraphics
import Foundation
import OnnxRuntimeBindings

/// Greedy CTC decode, mirroring PaddleOCR `CTCLabelDecode`: argmax per
/// timestep, collapse repeated indices, drop the blank token (index 0), map
/// index n → dictionary line n-1. Confidence = mean of max probabilities
/// over kept timesteps (0 when nothing was kept).
enum PPOCRCTCDecoder {
  static func decode(
    logits: [Float],
    timeSteps: Int,
    classCount: Int,
    dictionary: [String]
  ) -> (text: String, confidence: Float) {
    guard timeSteps > 0, classCount > 0, logits.count >= timeSteps * classCount else {
      return ("", 0)
    }
    let probabilities = softmaxIfNeeded(logits, timeSteps: timeSteps, classCount: classCount)
    var text = ""
    var confidenceSum: Float = 0
    var keptCount = 0
    var previousIndex = -1

    for step in 0..<timeSteps {
      let rowStart = step * classCount
      var bestIndex = 0
      var bestValue = -Float.greatestFiniteMagnitude
      for index in 0..<classCount {
        let value = probabilities[rowStart + index]
        if value > bestValue {
          bestValue = value
          bestIndex = index
        }
      }
      let isKept = bestIndex != previousIndex && bestIndex != 0
      previousIndex = bestIndex
      guard isKept else { continue }
      let dictionaryIndex = bestIndex - 1
      guard dictionaryIndex < dictionary.count else { continue }
      text += dictionary[dictionaryIndex]
      confidenceSum += bestValue
      keptCount += 1
    }

    let confidence = keptCount > 0 ? confidenceSum / Float(keptCount) : 0
    return (text, confidence)
  }

  /// PP-OCR rec exports end in softmax; normalize defensively only when raw
  /// values fall outside [0, 1] (i.e. they are logits, not probabilities).
  static func softmaxIfNeeded(_ values: [Float], timeSteps: Int, classCount: Int) -> [Float] {
    let looksLikeProbabilities = values.allSatisfy { $0 >= 0 && $0 <= 1 }
    guard !looksLikeProbabilities else { return values }
    var result = values
    for step in 0..<timeSteps {
      let rowStart = step * classCount
      let row = result[rowStart..<(rowStart + classCount)]
      let rowMax = row.max() ?? 0
      var sum: Float = 0
      for index in rowStart..<(rowStart + classCount) {
        result[index] = exp(result[index] - rowMax)
        sum += result[index]
      }
      guard sum > 0 else { continue }
      for index in rowStart..<(rowStart + classCount) {
        result[index] /= sum
      }
    }
    return result
  }
}

/// Crop → rec preprocess (`RecResizeImg` h=48, dynamic width) → rec
/// inference → CTC decode for one detected box.
enum PPOCRRecognizer {
  static let inputHeight = 48
  private static let maxInputWidth = 3200
  private static let cropPadding: CGFloat = 2

  /// Recognizes the text inside `box` (original-image pixel coordinates).
  static func recognize(
    box: PPOCRTextBox,
    in image: CGImage,
    session: ORTSession,
    dictionary: [String]
  ) throws -> (text: String, confidence: Float) {
    guard let crop = croppedLine(box: box, in: image) else { return ("", 0) }

    let aspect = CGFloat(crop.width) / CGFloat(crop.height)
    let targetWidth = min(maxInputWidth, max(1, Int((CGFloat(inputHeight) * aspect).rounded())))
    guard let tensor = PPOCRImageTensor.makeNCHW(
      from: crop,
      size: CGSize(width: targetWidth, height: inputHeight),
      normalize: .recognition
    ) else {
      throw OCRError.imageConversionFailed
    }

    let output = try PPOCRTensorRunner.run(
      session: session,
      tensor: tensor,
      shape: [1, 3, inputHeight, targetWidth]
    )
    let classCount = dictionary.count + 1  // +1 for the CTC blank at index 0
    guard classCount > 1, output.count % classCount == 0 else { return ("", 0) }
    return PPOCRCTCDecoder.decode(
      logits: output,
      timeSteps: output.count / classCount,
      classCount: classCount,
      dictionary: dictionary
    )
  }

  /// PaddleOCR `get_rotate_crop_image`: lifts the line out along its own axes
  /// so a skewed line still reaches the recognizer as a horizontal strip.
  ///
  /// Upright boxes — every screenshot of ordinary UI text — take the plain
  /// `CGImage.cropping` path instead: same pixels, no resample.
  private static func croppedLine(box: PPOCRTextBox, in image: CGImage) -> CGImage? {
    guard box.rotated.isFinite else { return nil }
    if box.rotated.isAxisAligned {
      let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
      let padded = box.rect.insetBy(dx: -cropPadding, dy: -cropPadding).intersection(imageBounds)
      guard padded.width >= 2, padded.height >= 2 else { return nil }
      return image.cropping(to: padded)
    }
    return rotatedCrop(box.rotated.padded(by: cropPadding), in: image)
  }

  /// Renders the oriented `rect` upright into its own buffer. Anything the box
  /// reaches outside the image stays white rather than black, matching the
  /// white compositing `PPOCRImageTensor` applies to transparent pixels.
  static func rotatedCrop(_ rect: PPOCRRotatedRect, in image: CGImage) -> CGImage? {
    // Guarded here rather than only at the call site: a non-finite centre
    // poisons the CTM instead of failing, yielding a blank crop that would
    // read as an empty line rather than as an error.
    guard rect.isFinite else { return nil }
    let width = Int(rect.size.width.rounded())
    let height = Int(rect.size.height.rounded())
    // A box is derived from the image, so anything far larger is a bad fit
    // rather than a real line; refuse it instead of allocating for it.
    let maxDimension = 2 * (image.width + image.height)
    guard width >= 2, height >= 2, width <= maxDimension, height <= maxDimension else {
      return nil
    }

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .high

    // Flip into the y-down pixel space the box coordinates live in, then map
    // image space onto the crop: subtract the box centre, rotate the box back
    // to horizontal, re-centre. The trailing flip keeps the source image's row
    // 0 at the top once it is drawn into that space.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
    context.rotate(by: -rect.angle)
    context.translateBy(x: -rect.center.x, y: -rect.center.y)
    context.translateBy(x: 0, y: CGFloat(image.height))
    context.scaleBy(x: 1, y: -1)
    context.draw(
      image,
      in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
    )

    return context.makeImage()
  }
}
