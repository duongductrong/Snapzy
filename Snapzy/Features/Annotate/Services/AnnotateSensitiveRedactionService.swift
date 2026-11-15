//
//  AnnotateSensitiveRedactionService.swift
//  Snapzy
//
//  Local OCR + deterministic sensitive-data detection for annotate redaction.
//

import AppKit
import CoreGraphics
import Foundation
import Vision

enum AnnotateSensitiveDataKind: String, CaseIterable, Sendable {
  case email
  case phoneNumber
  case url
  case creditCard
  case paymentCardExpiration
  case paymentCardholderName
  case credential
  case accessToken
}

struct AnnotateSensitiveTextMatch: Equatable, Sendable {
  let kind: AnnotateSensitiveDataKind
  let range: NSRange
  let confidence: Float
}

struct AnnotateSensitiveRedactionRegion: Equatable, Sendable {
  let kind: AnnotateSensitiveDataKind
  let bounds: CGRect
  let confidence: Float
}

struct AnnotateSensitiveRedactionResult: Equatable, Sendable {
  let regions: [AnnotateSensitiveRedactionRegion]

  var count: Int {
    regions.count
  }
}

struct AnnotateSensitiveOCRLine: Equatable, Sendable {
  let text: String
  let bounds: CGRect
  let confidence: Float
}

enum AnnotateSensitiveRedactionError: LocalizedError {
  case imageUnavailable
  case textRecognitionFailed

  var errorDescription: String? {
    switch self {
    case .imageUnavailable:
      return "Unable to load image data for sensitive-data detection."
    case .textRecognitionFailed:
      return "Unable to recognize text for sensitive-data detection."
    }
  }
}

struct AnnotateSensitiveDataDetector {
  private static let linkAndPhoneDetector = try? NSDataDetector(
    types: NSTextCheckingResult.CheckingType.link.rawValue
      | NSTextCheckingResult.CheckingType.phoneNumber.rawValue
  )

  private static let emailRegex = makeRegex(
    #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
    options: [.caseInsensitive]
  )
  private static let creditCardRegex = makeRegex(#"\b(?:\d[ -]?){13,19}\b"#)
  private static let groupedCardRegex = makeRegex(#"^\d{4}(?:[ -]\d{4}){2,4}$"#)
  private static let credentialValueRegex = makeRegex(
    #"\b(?:api[_-]?key|api[_-]?secret|access[_-]?token|auth[_-]?token|password|passwd|secret|client[_-]?secret|private[_-]?key)\b\s*[:=]\s*["']?([A-Za-z0-9_./+=:-]{6,})"#,
    options: [.caseInsensitive]
  )
  private static let bearerTokenRegex = makeRegex(
    #"\bAuthorization\s*:\s*Bearer\s+([A-Za-z0-9._~+/=-]{10,})"#,
    options: [.caseInsensitive]
  )
  private static let accessTokenRegexes: [NSRegularExpression] = [
    makeRegex(#"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#),
    makeRegex(#"\bgh[pousr]_[A-Za-z0-9_]{20,}\b"#),
    makeRegex(#"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"#),
    makeRegex(#"\b(?:sk|pk)_(?:live|test)_[A-Za-z0-9]{16,}\b"#),
    makeRegex(#"\bsk-[A-Za-z0-9]{20,}\b"#),
    makeRegex(#"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#)
  ]

  func detect(in text: String) -> [AnnotateSensitiveTextMatch] {
    guard !text.isEmpty else { return [] }
    let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
    var matches: [AnnotateSensitiveTextMatch] = []

    appendNSDataDetectorMatches(in: text, fullRange: fullRange, to: &matches)
    appendRegexMatches(Self.emailRegex, kind: .email, confidence: 0.94, in: text, fullRange: fullRange, to: &matches)
    appendCreditCardMatches(in: text, fullRange: fullRange, to: &matches)
    appendCapturedRegexMatches(
      Self.credentialValueRegex,
      kind: .credential,
      confidence: 0.96,
      in: text,
      fullRange: fullRange,
      to: &matches
    )
    appendCapturedRegexMatches(
      Self.bearerTokenRegex,
      kind: .accessToken,
      confidence: 0.97,
      in: text,
      fullRange: fullRange,
      to: &matches
    )

    for regex in Self.accessTokenRegexes {
      appendRegexMatches(regex, kind: .accessToken, confidence: 0.98, in: text, fullRange: fullRange, to: &matches)
    }

    return matches.sorted {
      if $0.range.location == $1.range.location {
        return $0.range.length < $1.range.length
      }
      return $0.range.location < $1.range.location
    }
  }

  private func appendNSDataDetectorMatches(
    in text: String,
    fullRange: NSRange,
    to matches: inout [AnnotateSensitiveTextMatch]
  ) {
    guard let detector = Self.linkAndPhoneDetector else { return }

    detector.enumerateMatches(in: text, options: [], range: fullRange) { result, _, _ in
      guard let result else { return }
      switch result.resultType {
      case .link:
        if result.url?.scheme?.lowercased() == "mailto" || text.nsSubstring(with: result.range).contains("@") {
          appendUnique(.init(kind: .email, range: result.range, confidence: 0.93), to: &matches)
        } else {
          appendUnique(.init(kind: .url, range: result.range, confidence: 0.88), to: &matches)
        }
      case .phoneNumber:
        appendUnique(.init(kind: .phoneNumber, range: result.range, confidence: 0.82), to: &matches)
      default:
        break
      }
    }
  }

  private func appendRegexMatches(
    _ regex: NSRegularExpression,
    kind: AnnotateSensitiveDataKind,
    confidence: Float,
    in text: String,
    fullRange: NSRange,
    to matches: inout [AnnotateSensitiveTextMatch]
  ) {
    regex.enumerateMatches(in: text, options: [], range: fullRange) { result, _, _ in
      guard let result else { return }
      appendUnique(.init(kind: kind, range: result.range, confidence: confidence), to: &matches)
    }
  }

  private func appendCapturedRegexMatches(
    _ regex: NSRegularExpression,
    kind: AnnotateSensitiveDataKind,
    confidence: Float,
    in text: String,
    fullRange: NSRange,
    to matches: inout [AnnotateSensitiveTextMatch]
  ) {
    regex.enumerateMatches(in: text, options: [], range: fullRange) { result, _, _ in
      guard let result, result.numberOfRanges > 1 else { return }
      let valueRange = result.range(at: 1)
      guard valueRange.location != NSNotFound, valueRange.length > 0 else { return }
      appendUnique(.init(kind: kind, range: valueRange, confidence: confidence), to: &matches)
    }
  }

  private func appendCreditCardMatches(
    in text: String,
    fullRange: NSRange,
    to matches: inout [AnnotateSensitiveTextMatch]
  ) {
    Self.creditCardRegex.enumerateMatches(in: text, options: [], range: fullRange) { result, _, _ in
      guard let result else { return }
      let candidate = text.nsSubstring(with: result.range)
      let digits = candidate.filter(\.isNumber)
      guard (13...19).contains(digits.count),
            Self.hasPlausiblePaymentCardPrefix(digits),
            Self.passesLuhn(digits) || Self.isGroupedPaymentCardNumber(candidate) else { return }
      appendUnique(.init(kind: .creditCard, range: result.range, confidence: 0.98), to: &matches)
    }
  }

  private func appendUnique(
    _ candidate: AnnotateSensitiveTextMatch,
    to matches: inout [AnnotateSensitiveTextMatch]
  ) {
    if let overlappingIndex = matches.firstIndex(where: { $0.range.intersects(candidate.range) }) {
      let existing = matches[overlappingIndex]
      if candidate.confidence > existing.confidence || candidate.range.length > existing.range.length {
        matches[overlappingIndex] = candidate
      }
      return
    }
    matches.append(candidate)
  }

  private static func makeRegex(
    _ pattern: String,
    options: NSRegularExpression.Options = []
  ) -> NSRegularExpression {
    do {
      return try NSRegularExpression(pattern: pattern, options: options)
    } catch {
      preconditionFailure("Invalid sensitive-data regex: \(pattern)")
    }
  }

  fileprivate static func isGroupedPaymentCardNumber(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let fullRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
    let digits = trimmed.filter(\.isNumber)
    return groupedCardRegex.firstMatch(in: trimmed, options: [], range: fullRange) != nil
      && hasPlausiblePaymentCardPrefix(digits)
  }

  fileprivate static func hasPlausiblePaymentCardPrefix(_ digits: String) -> Bool {
    guard digits.count >= 2 else { return false }
    let prefix2 = Int(digits.prefix(2)) ?? -1
    let prefix3 = Int(digits.prefix(3)) ?? -1
    let prefix4 = Int(digits.prefix(4)) ?? -1

    return digits.hasPrefix("4")
      || (51...55).contains(prefix2)
      || prefix2 == 34
      || prefix2 == 37
      || (2221...2720).contains(prefix4)
      || digits.hasPrefix("6011")
      || digits.hasPrefix("65")
      || (644...649).contains(prefix3)
      || digits.hasPrefix("35")
      || prefix2 == 30
      || prefix2 == 36
      || prefix2 == 38
      || prefix2 == 39
      || digits.hasPrefix("62")
  }

  fileprivate static func passesLuhn(_ digits: String) -> Bool {
    var sum = 0
    var shouldDouble = false

    for character in digits.reversed() {
      guard let digit = character.wholeNumberValue else { return false }
      var value = digit
      if shouldDouble {
        value *= 2
        if value > 9 { value -= 9 }
      }
      sum += value
      shouldDouble.toggle()
    }

    return sum > 0 && sum.isMultiple(of: 10)
  }
}

final class AnnotateSensitiveRedactionService {
  static let shared = AnnotateSensitiveRedactionService()

  private static let fullLineMatchCoverageThreshold: CGFloat = 0.6

  private let detector: AnnotateSensitiveDataDetector

  init(detector: AnnotateSensitiveDataDetector = AnnotateSensitiveDataDetector()) {
    self.detector = detector
  }

  /// Returns regions in annotate image space (bottom-left origin), ready to be
  /// inserted as `AnnotationItem.bounds`.
  /// - Parameter preferredLanguageIdentifier: the user's OCR language, so Vision
  ///   reads e.g. Vietnamese diacritics or CJK the same way Capture Text does.
  func detectRegions(
    in image: NSImage,
    preferredLanguageIdentifier: String? = nil
  ) async throws -> AnnotateSensitiveRedactionResult {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      throw AnnotateSensitiveRedactionError.imageUnavailable
    }

    let imageSize = image.size.width > 0 && image.size.height > 0
      ? image.size
      : CGSize(width: cgImage.width, height: cgImage.height)
    let detector = detector
    let languageProfile = VisionOCRProfile.resolve(
      for: OCRRequest(image: cgImage, preferredLanguageIdentifier: preferredLanguageIdentifier)
    )
    let recognitionLanguages = languageProfile.recognitionLanguages
    let automaticallyDetectsLanguage = languageProfile.automaticallyDetectsLanguage

    return try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        let request = VNRecognizeTextRequest { request, error in
          if let error {
            continuation.resume(throwing: error)
            return
          }

          guard let observations = request.results as? [VNRecognizedTextObservation] else {
            continuation.resume(throwing: AnnotateSensitiveRedactionError.textRecognitionFailed)
            return
          }

          // Analysis runs in top-left space (its "below"/row heuristics read
          // downward); the canvas is bottom-left, so flip once at the boundary.
          let regions = Self.annotateRegions(
            fromTopLeftRegions: Self.extractRegions(
              from: observations,
              imageSize: imageSize,
              detector: detector
            ),
            imageSize: imageSize
          )
          continuation.resume(returning: AnnotateSensitiveRedactionResult(regions: regions))
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.01
        if !recognitionLanguages.isEmpty {
          request.recognitionLanguages = recognitionLanguages
        }
        if #available(macOS 13.0, *) {
          request.automaticallyDetectsLanguage = automaticallyDetectsLanguage
        }

        do {
          try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Top-left image rect (y grows downward), used for the internal analysis only.
  /// Convert with `annotateRegions(fromTopLeftRegions:imageSize:)` before inserting.
  static func imageRect(fromVisionBoundingBox boundingBox: CGRect, imageSize: CGSize) -> CGRect {
    VisionImageGeometry.topLeftRect(fromVisionBoundingBox: boundingBox, imageSize: imageSize)
  }

  /// Top-left analysis regions → annotate canvas regions (bottom-left origin).
  static func annotateRegions(
    fromTopLeftRegions regions: [AnnotateSensitiveRedactionRegion],
    imageSize: CGSize
  ) -> [AnnotateSensitiveRedactionRegion] {
    regions.map { region in
      AnnotateSensitiveRedactionRegion(
        kind: region.kind,
        bounds: VisionImageGeometry.flippedVertically(region.bounds, imageHeight: imageSize.height),
        confidence: region.confidence
      )
    }
  }

  static func contextualRegions(
    from lines: [AnnotateSensitiveOCRLine],
    imageSize: CGSize
  ) -> [AnnotateSensitiveRedactionRegion] {
    let rows = groupedRows(from: lines)
    let cardRegions = rows.flatMap { paymentCardNumberRegions(in: $0, imageSize: imageSize) }
    guard !cardRegions.isEmpty else { return [] }

    return cardRegions
      + paymentCardExpirationRegions(in: lines, imageSize: imageSize)
      + paymentCardholderRegions(in: lines, cardRegions: cardRegions, imageSize: imageSize)
  }

  private static func extractRegions(
    from observations: [VNRecognizedTextObservation],
    imageSize: CGSize,
    detector: AnnotateSensitiveDataDetector
  ) -> [AnnotateSensitiveRedactionRegion] {
    let lines = observations.compactMap { observation -> AnnotateSensitiveOCRLine? in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      return AnnotateSensitiveOCRLine(
        text: candidate.string,
        bounds: imageRect(fromVisionBoundingBox: observation.boundingBox, imageSize: imageSize),
        confidence: observation.confidence
      )
    }

    var regions = contextualRegions(from: lines, imageSize: imageSize)

    for observation in observations {
      guard let candidate = observation.topCandidates(1).first else { continue }
      let text = candidate.string
      let matches = detector.detect(in: text)
      guard !matches.isEmpty else { continue }

      let lineRect = imageRect(fromVisionBoundingBox: observation.boundingBox, imageSize: imageSize)
      for match in matches {
        let matchRect: CGRect
        if let range = Range(match.range, in: text),
           let box = try? candidate.boundingBox(for: range) {
          matchRect = imageRect(fromVisionBoundingBox: box.boundingBox, imageSize: imageSize)
        } else {
          guard matchCoversMostLine(match.range, in: text) else { continue }
          matchRect = lineRect
        }

        let paddedRect = redactionRect(
          forMatchRect: matchRect,
          lineRect: lineRect,
          matchRange: match.range,
          text: text,
          kind: match.kind,
          imageSize: imageSize
        )
        guard paddedRect.width > 0, paddedRect.height > 0 else { continue }

        regions.append(
          AnnotateSensitiveRedactionRegion(
            kind: match.kind,
            bounds: paddedRect,
            confidence: min(observation.confidence, match.confidence)
          )
        )
      }
    }

    return mergeOverlappingRegions(regions)
  }

  private static func groupedRows(from lines: [AnnotateSensitiveOCRLine]) -> [[AnnotateSensitiveOCRLine]] {
    let sortedLines = lines.sorted {
      if abs($0.bounds.midY - $1.bounds.midY) < 0.5 {
        return $0.bounds.minX < $1.bounds.minX
      }
      return $0.bounds.midY < $1.bounds.midY
    }

    return sortedLines.reduce(into: [[AnnotateSensitiveOCRLine]]()) { rows, line in
      if let index = rows.firstIndex(where: { row in
        let rowBounds = rowBounds(row)
        let tolerance = max(line.bounds.height, rowBounds.height) * 0.85
        return abs(line.bounds.midY - rowBounds.midY) <= tolerance
      }) {
        rows[index].append(line)
      } else {
        rows.append([line])
      }
    }
    .map { $0.sorted { $0.bounds.minX < $1.bounds.minX } }
  }

  private static func paymentCardNumberRegions(
    in row: [AnnotateSensitiveOCRLine],
    imageSize: CGSize
  ) -> [AnnotateSensitiveRedactionRegion] {
    var regions: [AnnotateSensitiveRedactionRegion] = []
    var sequence: [AnnotateSensitiveOCRLine] = []

    func flushSequence() {
      guard !sequence.isEmpty else { return }
      defer { sequence.removeAll() }

      let combinedText = sequence.map(\.text).joined(separator: " ")
      let digits = combinedText.filter(\.isNumber)
      guard (13...19).contains(digits.count),
            AnnotateSensitiveDataDetector.passesLuhn(digits)
              || AnnotateSensitiveDataDetector.isGroupedPaymentCardNumber(combinedText) else { return }

      let bounds = clampedRect(rowBounds(sequence), imageSize: imageSize)
      guard !bounds.isEmpty else { return }
      regions.append(
        AnnotateSensitiveRedactionRegion(
          kind: .creditCard,
          bounds: paddedClampedRect(bounds, kind: .creditCard, imageSize: imageSize),
          confidence: min(sequence.map(\.confidence).min() ?? 0.95, 0.97)
        )
      )
    }

    for line in row {
      if isPaymentCardNumberFragment(line.text) {
        sequence.append(line)
      } else {
        flushSequence()
      }
    }
    flushSequence()

    return regions
  }

  private static func paymentCardExpirationRegions(
    in lines: [AnnotateSensitiveOCRLine],
    imageSize: CGSize
  ) -> [AnnotateSensitiveRedactionRegion] {
    let labels = lines.filter { isExpirationLabel($0.text) }
    guard !labels.isEmpty else { return [] }

    return lines.compactMap { line in
      guard isPaymentCardExpirationValue(line.text),
            labels.contains(where: { isNearbyExpirationLabel($0, value: line) }) else { return nil }

      return AnnotateSensitiveRedactionRegion(
        kind: .paymentCardExpiration,
        bounds: paddedClampedRect(line.bounds, imageSize: imageSize),
        confidence: min(line.confidence, 0.94)
      )
    }
  }

  private static func paymentCardholderRegions(
    in lines: [AnnotateSensitiveOCRLine],
    cardRegions: [AnnotateSensitiveRedactionRegion],
    imageSize: CGSize
  ) -> [AnnotateSensitiveRedactionRegion] {
    guard let lowestCardNumberY = cardRegions.map(\.bounds.maxY).max() else { return [] }
    let cardNumberMinX = cardRegions.map(\.bounds.minX).min() ?? 0
    let leftAlignmentTolerance = max(imageSize.width * 0.12, 48)

    return lines.compactMap { line in
      let normalized = normalizedWords(line.text)
      guard line.bounds.midY > lowestCardNumberY,
            abs(line.bounds.minX - cardNumberMinX) <= leftAlignmentTolerance,
            containsCardholderKeyword(normalized) || looksLikeCardholderName(normalized) else { return nil }

      return AnnotateSensitiveRedactionRegion(
        kind: .paymentCardholderName,
        bounds: paddedClampedRect(line.bounds, imageSize: imageSize),
        confidence: min(line.confidence, 0.92)
      )
    }
  }

  private static func isPaymentCardNumberFragment(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let digits = trimmed.filter(\.isNumber)
    guard digits.count >= 4 else { return false }
    return trimmed.allSatisfy { $0.isNumber || $0 == " " || $0 == "-" }
  }

  private static func isPaymentCardExpirationValue(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let pattern = #"^(?:0[0-9]|1[0-2]|[0-9]{2})[/-](?:[0-9]{2}|[0-9]{4})$"#
    return trimmed.range(of: pattern, options: .regularExpression) != nil
  }

  private static func isExpirationLabel(_ text: String) -> Bool {
    let normalized = normalizedWords(text)
    return normalized.contains("VALID")
      || normalized.contains("THRU")
      || normalized.contains("EXP")
      || normalized.contains("EXPIRES")
      || normalized.contains("EXPIRY")
  }

  private static func isNearbyExpirationLabel(
    _ label: AnnotateSensitiveOCRLine,
    value: AnnotateSensitiveOCRLine
  ) -> Bool {
    let verticalTolerance = max(label.bounds.height, value.bounds.height) * 2.4
    let sameBand = abs(label.bounds.midY - value.bounds.midY) <= verticalTolerance
    let horizontallyNear = value.bounds.minX >= label.bounds.minX
      && value.bounds.minX - label.bounds.maxX <= max(value.bounds.width * 1.4, 64)
    return sameBand && horizontallyNear
  }

  private static func containsCardholderKeyword(_ text: String) -> Bool {
    text.contains("CARDHOLDER") || text.contains("CARD HOLDER")
  }

  private static func looksLikeCardholderName(_ text: String) -> Bool {
    let excluded: Set<String> = ["BANK", "VALID", "THRU", "MEMBER", "SINCE", "CARD", "NAME"]
    let tokens = text
      .split(separator: " ")
      .map(String.init)
      .filter { !$0.isEmpty }

    guard (2...4).contains(tokens.count),
          tokens.allSatisfy({ token in
            token.count >= 2
              && token.allSatisfy(\.isLetter)
              && !excluded.contains(token)
          }) else { return false }

    return true
  }

  private static func normalizedWords(_ text: String) -> String {
    text
      .uppercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  private static func rowBounds(_ lines: [AnnotateSensitiveOCRLine]) -> CGRect {
    lines.reduce(CGRect.null) { $0.union($1.bounds) }.standardized
  }

  private static func clampedRect(_ rect: CGRect, imageSize: CGSize) -> CGRect {
    rect.standardized.intersection(CGRect(origin: .zero, size: imageSize)).standardized
  }

  static func redactionRect(
    forMatchRect matchRect: CGRect,
    lineRect: CGRect,
    matchRange: NSRange,
    text: String,
    kind: AnnotateSensitiveDataKind,
    imageSize: CGSize
  ) -> CGRect {
    let normalizedMatchRect = clampedRect(matchRect, imageSize: imageSize)
    let normalizedLineRect = clampedRect(lineRect, imageSize: imageSize)
    let baseRect = matchCoversMostLine(matchRange, in: text)
      ? normalizedMatchRect.union(normalizedLineRect).standardized
      : normalizedMatchRect

    return paddedClampedRect(baseRect, kind: kind, imageSize: imageSize)
  }

  private static func matchCoversMostLine(_ range: NSRange, in text: String) -> Bool {
    let fullLength = max((text as NSString).length, 1)
    let start = min(max(range.location, 0), fullLength)
    let end = min(start + max(range.length, 0), fullLength)
    let coveredLength = max(end - start, 0)
    return CGFloat(coveredLength) / CGFloat(fullLength) >= fullLineMatchCoverageThreshold
  }

  private static func paddedClampedRect(_ rect: CGRect, imageSize: CGSize) -> CGRect {
    let padding = max(4, min(12, max(rect.width, rect.height) * 0.18))
    let padded = rect.insetBy(dx: -padding, dy: -padding).standardized
    let imageBounds = CGRect(origin: .zero, size: imageSize)
    return padded.intersection(imageBounds).standardized
  }

  private static func paddedClampedRect(
    _ rect: CGRect,
    kind: AnnotateSensitiveDataKind,
    imageSize: CGSize
  ) -> CGRect {
    guard kind == .creditCard else {
      return paddedClampedRect(rect, imageSize: imageSize)
    }

    let horizontalPadding = max(8, min(18, rect.width * 0.06))
    let verticalPadding = max(8, min(18, rect.height * 0.85))
    let padded = rect.insetBy(dx: -horizontalPadding, dy: -verticalPadding).standardized
    return clampedRect(padded, imageSize: imageSize)
  }

  private static func mergeOverlappingRegions(
    _ regions: [AnnotateSensitiveRedactionRegion]
  ) -> [AnnotateSensitiveRedactionRegion] {
    regions.reduce(into: []) { merged, region in
      if let index = merged.firstIndex(where: { $0.bounds.insetBy(dx: -2, dy: -4).intersects(region.bounds) }) {
        let existing = merged[index]
        merged[index] = AnnotateSensitiveRedactionRegion(
          kind: existing.kind,
          bounds: existing.bounds.union(region.bounds).standardized,
          confidence: max(existing.confidence, region.confidence)
        )
      } else {
        merged.append(region)
      }
    }
  }
}

private extension NSRange {
  func intersects(_ other: NSRange) -> Bool {
    NSIntersectionRange(self, other).length > 0
  }
}

private extension String {
  func nsSubstring(with range: NSRange) -> String {
    guard let swiftRange = Range(range, in: self) else { return "" }
    return String(self[swiftRange])
  }
}
