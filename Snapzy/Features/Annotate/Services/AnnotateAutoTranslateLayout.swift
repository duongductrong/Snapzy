//
//  AnnotateAutoTranslateLayout.swift
//  Snapzy
//
//  Finds translatable text blocks on the Annotate image and samples how each one
//  looks (background, text color, weight), so a translation can sit on top of it.
//

import AppKit
import CoreGraphics
import Foundation
import NaturalLanguage

/// sRGB color sampled from the image.
nonisolated struct AnnotateSampledColor: Equatable, Sendable {
  var red: CGFloat
  var green: CGFloat
  var blue: CGFloat

  static let black = AnnotateSampledColor(red: 0, green: 0, blue: 0)
  static let white = AnnotateSampledColor(red: 1, green: 1, blue: 1)

  var nsColor: NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
  }

  /// WCAG relative luminance.
  var luminance: CGFloat {
    func channel(_ value: CGFloat) -> CGFloat {
      value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
  }

  func contrastRatio(with other: AnnotateSampledColor) -> CGFloat {
    let lighter = max(luminance, other.luminance)
    let darker = min(luminance, other.luminance)
    return (lighter + 0.05) / (darker + 0.05)
  }

  func distance(to other: AnnotateSampledColor) -> CGFloat {
    let dr = red - other.red
    let dg = green - other.green
    let db = blue - other.blue
    return sqrt((dr * dr + dg * dg + db * db) / 3)
  }
}

nonisolated struct AnnotateTranslationStyle: Equatable, Sendable {
  var background: AnnotateSampledColor
  var text: AnnotateSampledColor
  var cover: TranslationCoverStyle
  var isBold: Bool

  static let fallback = AnnotateTranslationStyle(background: .white, text: .black, cover: .solid, isBold: false)
}

/// One source block ready to translate, in annotate image space (bottom-left origin).
nonisolated struct AnnotateTranslationCandidate: Identifiable, Equatable, Sendable {
  let id: UUID
  let sourceText: String
  /// Cover rect: the text box with a little padding, clamped to the image.
  let bounds: CGRect
  let rowHeight: CGFloat
  let rowCount: Int
  let alignment: TranslationTextAlignment
  var style: AnnotateTranslationStyle

  var baseFontSize: CGFloat {
    rowHeight * AnnotateTranslationTextLayout.rowHeightToFontSize
  }
}

nonisolated enum AnnotateAutoTranslateError: LocalizedError, Equatable {
  case imageUnavailable
  case noText
  case alreadyInTargetLanguage

  var errorDescription: String? {
    switch self {
    case .imageUnavailable: L10n.AnnotateTranslate.imageUnavailable
    case .noText: L10n.AnnotateTranslate.noText
    case .alreadyInTargetLanguage: L10n.AnnotateTranslate.alreadyInTarget
    }
  }
}

enum AnnotateAutoTranslateLayout {
  /// OCR (Vision, user's OCR language) → positioned blocks → filtered candidates with styles.
  @MainActor
  static func detectCandidates(
    in image: NSImage,
    languageIdentifier: String?,
    targetLanguage: TranslationLanguage
  ) async throws -> [AnnotateTranslationCandidate] {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      throw AnnotateAutoTranslateError.imageUnavailable
    }
    let imageSize = image.size.width > 0 && image.size.height > 0
      ? image.size
      : CGSize(width: cgImage.width, height: cgImage.height)

    let result: OCRResult
    do {
      result = try await OCRService.shared.recognizeLayout(
        OCRRequest(image: cgImage, preferredLanguageIdentifier: languageIdentifier, contentType: .interfaceText)
      )
    } catch OCRError.noTextFound {
      throw AnnotateAutoTranslateError.noText
    }

    let prefersCJK = ["ja", "ko", "zh-Hans", "zh-Hant"]
      .contains(AppLanguageManager.normalizedLanguageIdentifier(from: languageIdentifier) ?? "")
    let formatter = OCRTextLayoutFormatter(
      imageSize: CGSize(width: cgImage.width, height: cgImage.height),
      prefersCJK: prefersCJK
    )
    let blocks = formatter.blocks(result.lines)
    let candidates = makeCandidates(from: blocks, imageSize: imageSize, targetLanguage: targetLanguage)
    guard !candidates.isEmpty else { throw AnnotateAutoTranslateError.noText }

    let styled = await Task.detached(priority: .userInitiated) {
      candidates.map { candidate -> AnnotateTranslationCandidate in
        var candidate = candidate
        candidate.style = AnnotateTranslationStyleSampler.sample(
          cgImage: cgImage,
          imageSize: imageSize,
          textBounds: candidate.bounds,
          rowHeight: candidate.rowHeight
        )
        return candidate
      }
    }.value
    return styled
  }

  // MARK: - Candidates

  nonisolated static func makeCandidates(
    from blocks: [OCRTextBlock],
    imageSize: CGSize,
    targetLanguage: TranslationLanguage
  ) -> [AnnotateTranslationCandidate] {
    let imageBounds = CGRect(origin: .zero, size: imageSize)
    return blocks.compactMap { block -> AnnotateTranslationCandidate? in
      let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard shouldTranslate(text, targetLanguage: targetLanguage) else { return nil }

      let textBounds = VisionImageGeometry.annotateRect(fromVisionBoundingBox: block.box, imageSize: imageSize)
      let rowHeight = block.rowHeight * imageSize.height
      guard rowHeight >= 6, textBounds.width >= 4 else { return nil }

      // Vision boxes hug the glyphs; pad so the cover hides antialiasing and accents.
      let padded = textBounds
        .insetBy(dx: -max(rowHeight * 0.14, 1.5), dy: -max(rowHeight * 0.1, 1))
        .intersection(imageBounds)
      guard !padded.isNull, padded.width > 0, padded.height > 0 else { return nil }

      let rowRects = block.rowBoxes.map {
        VisionImageGeometry.annotateRect(fromVisionBoundingBox: $0, imageSize: imageSize)
      }
      return AnnotateTranslationCandidate(
        id: UUID(),
        sourceText: text,
        bounds: padded,
        rowHeight: rowHeight,
        rowCount: max(rowRects.count, 1),
        alignment: alignment(of: rowRects, rowHeight: rowHeight),
        style: .fallback
      )
    }
  }

  /// Skips blocks with nothing to translate: symbols and numbers, URLs and e-mail
  /// addresses, and longer text already in the target language.
  nonisolated static func shouldTranslate(_ text: String, targetLanguage: TranslationLanguage) -> Bool {
    let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
    let meaningful = text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
    guard letters >= 1, meaningful > 0 else { return false }
    guard Double(letters) / Double(meaningful) >= 0.3 else { return false }
    if letters < 2, !text.unicodeScalars.contains(where: isCJKScalar) { return false }
    if isEntirelyLink(text) { return false }

    if letters >= 12 {
      let recognizer = NLLanguageRecognizer()
      recognizer.processString(text)
      if let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
         confidence >= 0.8,
         languageCode(language.rawValue) == languageCode(targetLanguage.identifier) {
        return false
      }
    }
    return true
  }

  nonisolated static func languageCode(_ identifier: String) -> String {
    let lowered = identifier.lowercased()
    if lowered.hasPrefix("zh-hant") || lowered.hasPrefix("zh-tw") || lowered.hasPrefix("zh-hk") { return "zh-hant" }
    if lowered.hasPrefix("zh") { return "zh-hans" }
    return String(lowered.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? Substring(lowered))
  }

  private nonisolated static func isEntirelyLink(_ text: String) -> Bool {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
      return false
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let range = NSRange(trimmed.startIndex..., in: trimmed)
    let covered = detector.matches(in: trimmed, range: range).reduce(0) { $0 + $1.range.length }
    return covered >= range.length - 1
  }

  private nonisolated static func isCJKScalar(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x3040...0x30FF, 0xAC00...0xD7AF:
      return true
    default:
      return false
    }
  }

  /// Multi-row blocks: whichever edge the rows share. Single rows read as leading.
  nonisolated static func alignment(of rows: [CGRect], rowHeight: CGFloat) -> TranslationTextAlignment {
    guard rows.count > 1 else { return .leading }
    func spread(_ values: [CGFloat]) -> CGFloat {
      (values.max() ?? 0) - (values.min() ?? 0)
    }
    let tolerance = max(rowHeight * 0.5, 2)
    let left = spread(rows.map(\.minX))
    let center = spread(rows.map(\.midX))
    let right = spread(rows.map(\.maxX))
    if left <= tolerance { return .leading }
    if center <= tolerance, center < right { return .center }
    if right <= tolerance { return .trailing }
    return .leading
  }
}

// MARK: - Style sampling

nonisolated enum AnnotateTranslationStyleSampler {
  private static let maxSampleDimension: CGFloat = 160
  /// Luminance spread above which the background is treated as a photo/gradient.
  private static let noisyBackgroundDeviation: CGFloat = 0.085
  private static let minimumContrast: CGFloat = 3

  static func sample(
    cgImage: CGImage,
    imageSize: CGSize,
    textBounds: CGRect,
    rowHeight: CGFloat
  ) -> AnnotateTranslationStyle {
    guard imageSize.width > 0, imageSize.height > 0 else { return .fallback }
    let scaleX = CGFloat(cgImage.width) / imageSize.width
    let scaleY = CGFloat(cgImage.height) / imageSize.height

    // Annotate (bottom-left) → pixel rect (top-left).
    let pixelText = CGRect(
      x: textBounds.minX * scaleX,
      y: (imageSize.height - textBounds.maxY) * scaleY,
      width: textBounds.width * scaleX,
      height: textBounds.height * scaleY
    )
    let pad = max(2, rowHeight * scaleY * 0.3)
    let pixelBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
    let outer = pixelText.insetBy(dx: -pad, dy: -pad).intersection(pixelBounds).integral
    guard !outer.isNull, outer.width >= 2, outer.height >= 2,
          let crop = cgImage.cropping(to: outer) else { return .fallback }

    let factor = min(1, maxSampleDimension / max(outer.width, outer.height))
    let width = max(Int((outer.width * factor).rounded()), 2)
    let height = max(Int((outer.height * factor).rounded()), 2)
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
      guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
              data: buffer.baseAddress,
              width: width,
              height: height,
              bitsPerComponent: 8,
              bytesPerRow: width * 4,
              space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
      context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      context.interpolationQuality = .medium
      context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return .fallback }

    // Inner (text) rect in sample coordinates; buffer row 0 is the top.
    let innerMinX = Int(((pixelText.minX - outer.minX) * factor).rounded(.down))
    let innerMaxX = Int(((pixelText.maxX - outer.minX) * factor).rounded(.up))
    let innerMinY = Int(((pixelText.minY - outer.minY) * factor).rounded(.down))
    let innerMaxY = Int(((pixelText.maxY - outer.minY) * factor).rounded(.up))

    var ring: [AnnotateSampledColor] = []
    var inner: [AnnotateSampledColor] = []
    ring.reserveCapacity(width * height / 2)
    inner.reserveCapacity(width * height / 2)
    for y in 0..<height {
      for x in 0..<width {
        let offset = (y * width + x) * 4
        let color = AnnotateSampledColor(
          red: CGFloat(pixels[offset]) / 255,
          green: CGFloat(pixels[offset + 1]) / 255,
          blue: CGFloat(pixels[offset + 2]) / 255
        )
        let isInner = x >= innerMinX && x < innerMaxX && y >= innerMinY && y < innerMaxY
        if isInner {
          inner.append(color)
        } else {
          ring.append(color)
        }
      }
    }
    return style(ring: ring.isEmpty ? edgeSamples(of: inner, width: width) : ring, inner: inner)
  }

  /// Background = per-channel median of the ring; text = mean of the inner pixels
  /// farthest from it. Low contrast falls back to black or white.
  static func style(ring: [AnnotateSampledColor], inner: [AnnotateSampledColor]) -> AnnotateTranslationStyle {
    guard !ring.isEmpty else { return .fallback }
    let background = AnnotateSampledColor(
      red: median(ring.map(\.red)),
      green: median(ring.map(\.green)),
      blue: median(ring.map(\.blue))
    )

    let luminances = ring.map(\.luminance)
    let mean = luminances.reduce(0, +) / CGFloat(luminances.count)
    let deviation = sqrt(luminances.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / CGFloat(luminances.count))
    let cover: TranslationCoverStyle = deviation > noisyBackgroundDeviation ? .frosted : .solid

    let distances = inner.map { $0.distance(to: background) }
    let ink = zip(inner, distances).filter { $0.1 > 0.18 }.sorted { $0.1 > $1.1 }
    var text: AnnotateSampledColor
    if ink.isEmpty {
      text = background.luminance > 0.4 ? .black : .white
    } else {
      let top = ink.prefix(max(ink.count * 3 / 10, 1))
      let count = CGFloat(top.count)
      text = AnnotateSampledColor(
        red: top.map(\.0.red).reduce(0, +) / count,
        green: top.map(\.0.green).reduce(0, +) / count,
        blue: top.map(\.0.blue).reduce(0, +) / count
      )
    }
    if text.contrastRatio(with: background) < minimumContrast {
      text = AnnotateSampledColor.black.contrastRatio(with: background)
        >= AnnotateSampledColor.white.contrastRatio(with: background) ? .black : .white
    }

    let inkRatio = inner.isEmpty ? 0 : CGFloat(distances.filter { $0 > 0.25 }.count) / CGFloat(inner.count)
    return AnnotateTranslationStyle(background: background, text: text, cover: cover, isBold: inkRatio > 0.34)
  }

  private static func edgeSamples(of inner: [AnnotateSampledColor], width: Int) -> [AnnotateSampledColor] {
    guard width > 0, inner.count >= width else { return inner }
    return Array(inner.prefix(width)) + Array(inner.suffix(width))
  }

  private static func median(_ values: [CGFloat]) -> CGFloat {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
  }
}
