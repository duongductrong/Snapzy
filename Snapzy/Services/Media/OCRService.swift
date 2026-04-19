//
//  OCRService.swift
//  Snapzy
//
//  Provides OCR text recognition using Vision framework
//

import AppKit
import CoreImage
import Vision

/// Errors that can occur during OCR processing
enum OCRError: LocalizedError {
  case imageConversionFailed
  case noTextFound
  case recognitionFailed(Error)

  var errorDescription: String? {
    switch self {
    case .imageConversionFailed:
      return L10n.OCR.imageConversionFailed
    case .noTextFound:
      return L10n.OCR.noTextFound
    case .recognitionFailed(let error):
      return L10n.OCR.recognitionFailed(error.localizedDescription)
    }
  }
}

/// Service for performing OCR text recognition on images
@MainActor
final class OCRService {

  static let shared = OCRService()

  private typealias OCRCandidate = (result: OCRResult, score: Float)

  private struct OCRPassSummary {
    let acceptedResult: OCRResult?
    let bestCandidate: OCRCandidate?
    let lastError: Error?
  }

  private let ciContext = CIContext(options: [.cacheIntermediates: false])

  private init() {}

  // MARK: - Public API

  func recognize(_ request: OCRRequest) async throws -> OCRResult {
    let profile = VisionOCRProfile.resolve(for: request)
    let languageContext = request.preferredLanguageIdentifier ?? "auto"
    let primaryProfiles = uniqueProfiles([profile] + VisionOCRProfile.recoveryProfiles(for: request, primary: profile))
    let primaryPass = await runRecognitionPass(
      for: request,
      profiles: primaryProfiles,
      languageContext: languageContext
    )

    if let acceptedResult = primaryPass.acceptedResult {
      return acceptedResult
    }

    var bestCandidate = primaryPass.bestCandidate
    var lastError = primaryPass.lastError

    if let enhancedImage = makeContrastEnhancedImage(from: request.image) {
      let enhancedProfiles = uniqueProfiles(VisionOCRProfile.enhancedRecoveryProfiles(for: request, primary: profile))
      if !enhancedProfiles.isEmpty {
        let enhancedRequest = OCRRequest(
          image: enhancedImage,
          preferredLanguageIdentifier: request.preferredLanguageIdentifier,
          contentType: request.contentType
        )

        DiagnosticLogger.shared.log(
          .info,
          .ocr,
          "OCR contrast-enhanced recovery started",
          context: [
            "sourceProfile": profile.id,
            "profiles": enhancedProfiles.map(\.id).joined(separator: ",")
          ]
        )

        let enhancedPass = await runRecognitionPass(
          for: enhancedRequest,
          profiles: enhancedProfiles,
          languageContext: "\(languageContext)+contrast"
        )

        bestCandidate = betterCandidate(bestCandidate, than: enhancedPass.bestCandidate)
        if let acceptedResult = enhancedPass.acceptedResult {
          return acceptedResult
        }
        lastError = enhancedPass.lastError ?? lastError
      }
    }

    if let bestCandidate {
      DiagnosticLogger.shared.log(
        .warning,
        .ocr,
        "OCR returning best available candidate after exhausting profiles",
        context: [
          "profile": bestCandidate.result.profileID,
          "confidence": String(format: "%.3f", bestCandidate.result.averageConfidence),
          "score": String(format: "%.3f", bestCandidate.score)
        ]
      )
      return bestCandidate.result
    }

    throw lastError ?? OCRError.noTextFound
  }

  /// Recognize text from a CGImage
  /// - Parameter image: The image to extract text from
  /// - Returns: Recognized text joined by newlines
  func recognizeText(
    from image: CGImage,
    preferredLanguageIdentifier: String? = nil,
    contentType: OCRContentType = .interfaceText
  ) async throws -> String {
    let result = try await recognize(
      OCRRequest(
        image: image,
        preferredLanguageIdentifier: preferredLanguageIdentifier,
        contentType: contentType
      )
    )
    return result.text
  }

  /// Recognize text from an NSImage
  /// - Parameter image: The NSImage to extract text from
  /// - Returns: Recognized text joined by newlines
  func recognizeText(
    from image: NSImage,
    preferredLanguageIdentifier: String? = nil,
    contentType: OCRContentType = .interfaceText
  ) async throws -> String {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      DiagnosticLogger.shared.log(.error, .ocr, "NSImage to CGImage conversion failed")
      throw OCRError.imageConversionFailed
    }
    return try await recognizeText(
      from: cgImage,
      preferredLanguageIdentifier: preferredLanguageIdentifier,
      contentType: contentType
    )
  }

  // MARK: - Vision Runtime

  private func runRecognitionPass(
    for request: OCRRequest,
    profiles: [VisionOCRProfile],
    languageContext: String
  ) async -> OCRPassSummary {
    var lastError: Error?
    var bestCandidate: OCRCandidate?

    for (index, profile) in profiles.enumerated() {
      let isFallback = index > 0

      do {
        let result = try await recognize(request, using: profile, languageContext: languageContext, isFallback: isFallback)
        let qualityScore = score(result, from: profile, request: request)
        let candidate = (result: result, score: qualityScore)
        bestCandidate = betterCandidate(bestCandidate, than: candidate)

        if shouldAccept(result, from: profile, request: request, qualityScore: qualityScore) {
          return OCRPassSummary(acceptedResult: result, bestCandidate: bestCandidate, lastError: lastError)
        }

        guard index < profiles.count - 1 else { continue }

        DiagnosticLogger.shared.log(
          .warning,
          .ocr,
          "OCR retrying with fallback profile after low-confidence result",
          context: [
            "profile": profile.id,
            "confidence": String(format: "%.3f", result.averageConfidence),
            "score": String(format: "%.3f", qualityScore)
          ]
        )
      } catch {
        lastError = error
        guard index < profiles.count - 1 else { break }

        DiagnosticLogger.shared.log(
          .warning,
          .ocr,
          "OCR retrying with fallback profile after failure",
          context: [
            "failedProfile": profile.id,
            "nextProfile": profiles[index + 1].id,
            "reason": error.localizedDescription
          ]
        )
      }
    }

    return OCRPassSummary(acceptedResult: nil, bestCandidate: bestCandidate, lastError: lastError)
  }

  private func recognize(
    _ request: OCRRequest,
    using profile: VisionOCRProfile,
    languageContext: String,
    isFallback: Bool
  ) async throws -> OCRResult {
    DiagnosticLogger.shared.log(
      .info,
      .ocr,
      isFallback ? "OCR fallback started" : "OCR started",
      context: [
        "width": "\(request.image.width)",
        "height": "\(request.image.height)",
        "profile": profile.id,
        "language": languageContext,
        "contentType": request.contentType.rawValue
      ]
    )

    return try await withCheckedThrowingContinuation { continuation in
      var hasResumed = false
      func resumeOnce(with result: Result<OCRResult, Error>) {
        guard !hasResumed else { return }
        hasResumed = true
        continuation.resume(with: result)
      }

      let visionRequest = VNRecognizeTextRequest { visionRequest, error in
        if let error {
          DiagnosticLogger.shared.logError(.ocr, error, "OCR recognition failed", context: ["profile": profile.id])
          resumeOnce(with: .failure(OCRError.recognitionFailed(error)))
          return
        }

        guard let observations = visionRequest.results as? [VNRecognizedTextObservation] else {
          resumeOnce(with: .failure(OCRError.noTextFound))
          return
        }

        let lines = observations.compactMap { observation -> OCRTextLine? in
          guard let candidate = observation.topCandidates(1).first else { return nil }
          return OCRTextLine(
            text: candidate.string,
            confidence: candidate.confidence,
            boundingBox: observation.boundingBox
          )
        }

        guard !lines.isEmpty else {
          DiagnosticLogger.shared.log(.warning, .ocr, "OCR completed: no text found", context: ["profile": profile.id])
          resumeOnce(with: .failure(OCRError.noTextFound))
          return
        }

        let orderedLines = self.sortLinesForReadingOrder(lines)
        let resultText = self.formatText(from: orderedLines, request: request)
        let averageConfidence = orderedLines.map(\.confidence).reduce(0, +) / Float(orderedLines.count)
        let result = OCRResult(
          engine: .vision,
          profileID: profile.id,
          text: resultText,
          lines: orderedLines,
          averageConfidence: averageConfidence
        )

        DiagnosticLogger.shared.log(
          .info,
          .ocr,
          "OCR completed",
          context: [
            "profile": profile.id,
            "lines": "\(lines.count)",
            "chars": "\(resultText.count)",
            "confidence": String(format: "%.3f", averageConfidence)
          ]
        )
        resumeOnce(with: .success(result))
      }

      profile.configure(visionRequest)

      let handler = VNImageRequestHandler(cgImage: request.image, options: [:])

      do {
        try handler.perform([visionRequest])
      } catch {
        DiagnosticLogger.shared.logError(.ocr, error, "OCR handler failed", context: ["profile": profile.id])
        resumeOnce(with: .failure(OCRError.recognitionFailed(error)))
      }
    }
  }

  private func shouldAccept(
    _ result: OCRResult,
    from profile: VisionOCRProfile,
    request: OCRRequest,
    qualityScore: Float
  ) -> Bool {
    let trimmedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedText.isEmpty {
      return false
    }

    if meaningfulCharacterCount(in: trimmedText) == 0 {
      return false
    }

    if request.contentType == .code {
      return result.averageConfidence >= profile.minimumAcceptableConfidence
    }

    return qualityScore >= profile.minimumAcceptableConfidence
  }

  private func score(_ result: OCRResult, from profile: VisionOCRProfile, request: OCRRequest) -> Float {
    let trimmedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else { return 0 }

    let meaningfulCharacters = meaningfulCharacterCount(in: trimmedText)
    let cjkCharacters = cjkCharacterCount(in: trimmedText)
    let lineCount = max(result.lines.count, 1)
    let averageLineLength = Float(meaningfulCharacters) / Float(lineCount)
    let preferredLanguage = AppLanguageManager.normalizedLanguageIdentifier(from: request.preferredLanguageIdentifier)

    var qualityScore = result.averageConfidence

    switch meaningfulCharacters {
    case 24...:
      qualityScore += 0.18
    case 12...:
      qualityScore += 0.10
    case 4...:
      qualityScore += 0.04
    default:
      qualityScore -= 0.06
    }

    if averageLineLength >= 10 {
      qualityScore += 0.06
    } else if averageLineLength < 1.5 {
      qualityScore -= 0.08
    }

    if cjkCharacters > 0 {
      qualityScore += 0.05
    }

    if profile.prefersCJKContent {
      qualityScore += cjkCharacters > 0 ? 0.08 : -0.12
    }

    if let preferredLanguage, isCJKLanguage(preferredLanguage) {
      if containsExpectedScript(for: preferredLanguage, in: trimmedText) {
        qualityScore += 0.12
      } else if cjkCharacters == 0 {
        qualityScore -= 0.10
      }
    }

    return qualityScore
  }

  private func uniqueProfiles(_ profiles: [VisionOCRProfile]) -> [VisionOCRProfile] {
    var seenIDs = Set<String>()
    return profiles.filter { profile in
      seenIDs.insert(profile.id).inserted
    }
  }

  private func betterCandidate(_ lhs: OCRCandidate?, than rhs: OCRCandidate?) -> OCRCandidate? {
    switch (lhs, rhs) {
    case (nil, nil):
      return nil
    case let (candidate?, nil), let (nil, candidate?):
      return candidate
    case let (lhs?, rhs?):
      return lhs.score >= rhs.score ? lhs : rhs
    }
  }

  private func sortLinesForReadingOrder(_ lines: [OCRTextLine]) -> [OCRTextLine] {
    lines.sorted { lhs, rhs in
      let verticalDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
      let rowTolerance = max(lhs.boundingBox.height, rhs.boundingBox.height) * 0.6
      if verticalDelta > rowTolerance {
        return lhs.boundingBox.maxY > rhs.boundingBox.maxY
      }
      return lhs.boundingBox.minX < rhs.boundingBox.minX
    }
  }

  private func formatText(from lines: [OCRTextLine], request: OCRRequest) -> String {
    let paragraphs = groupParagraphs(from: lines)
    let formattedParagraphs = paragraphs.map { paragraph -> String in
      if shouldReflowParagraph(paragraph, request: request) {
        return reflowedParagraphText(from: paragraph, request: request)
      }
      return paragraph
        .map(\.text)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .joined(separator: "\n")
    }

    return formattedParagraphs
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n\n")
  }

  private func groupParagraphs(from lines: [OCRTextLine]) -> [[OCRTextLine]] {
    guard !lines.isEmpty else { return [] }

    let averageHeight = lines.map(\.boundingBox.height).reduce(0, +) / CGFloat(lines.count)
    var paragraphs: [[OCRTextLine]] = []
    var currentParagraph = [lines[0]]

    for line in lines.dropFirst() {
      guard let previousLine = currentParagraph.last else { continue }
      let verticalGap = previousLine.boundingBox.minY - line.boundingBox.maxY
      let paragraphThreshold = max(
        averageHeight * 0.75,
        max(previousLine.boundingBox.height, line.boundingBox.height) * 0.68
      )

      if verticalGap > paragraphThreshold {
        paragraphs.append(currentParagraph)
        currentParagraph = [line]
      } else {
        currentParagraph.append(line)
      }
    }

    paragraphs.append(currentParagraph)
    return paragraphs
  }

  private func shouldReflowParagraph(_ paragraph: [OCRTextLine], request: OCRRequest) -> Bool {
    guard paragraph.count > 1 else { return false }

    let averageWidth = paragraph.map(\.boundingBox.width).reduce(0, +) / CGFloat(paragraph.count)
    let longestLineLength = paragraph.map { meaningfulCharacterCount(in: $0.text) }.max() ?? 0
    let preferredLanguage = AppLanguageManager.normalizedLanguageIdentifier(from: request.preferredLanguageIdentifier)
    let paragraphText = paragraph.map(\.text).joined()
    let cjkWeight = cjkCharacterCount(in: paragraphText)
    let isLikelyCJK = (preferredLanguage.map(isCJKLanguage) ?? false) || cjkWeight >= max(6, meaningfulCharacterCount(in: paragraphText) / 3)

    if isLikelyCJK {
      return averageWidth >= 0.24 || paragraph.count >= 3
    }

    return averageWidth >= 0.36 || longestLineLength >= 28 || paragraph.count >= 4
  }

  private func reflowedParagraphText(from paragraph: [OCRTextLine], request: OCRRequest) -> String {
    let paragraphText = paragraph.map(\.text).joined()
    let preferredLanguage = AppLanguageManager.normalizedLanguageIdentifier(from: request.preferredLanguageIdentifier)
    let isLikelyCJK = (preferredLanguage.map(isCJKLanguage) ?? false) || cjkCharacterCount(in: paragraphText) >= max(6, meaningfulCharacterCount(in: paragraphText) / 3)
    let separator = isLikelyCJK ? "" : " "

    return paragraph.reduce(into: "") { text, line in
      let nextFragment = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !nextFragment.isEmpty else { return }
      guard !text.isEmpty else {
        text = nextFragment
        return
      }

      if separator.isEmpty {
        text += nextFragment
      } else if text.hasSuffix("-") {
        text.removeLast()
        text += nextFragment
      } else if let firstScalar = nextFragment.unicodeScalars.first, leadingInlinePunctuation.contains(firstScalar) {
        text += nextFragment
      } else {
        text += separator + nextFragment
      }
    }
  }

  private var leadingInlinePunctuation: CharacterSet {
    CharacterSet(charactersIn: ",.;:!?)]}%")
  }

  private func makeContrastEnhancedImage(from image: CGImage) -> CGImage? {
    let ciImage = CIImage(cgImage: image)

    guard
      let colorControls = CIFilter(name: "CIColorControls"),
      let sharpen = CIFilter(name: "CISharpenLuminance")
    else {
      return nil
    }

    colorControls.setValue(ciImage, forKey: kCIInputImageKey)
    colorControls.setValue(0, forKey: kCIInputSaturationKey)
    colorControls.setValue(1.32, forKey: kCIInputContrastKey)
    colorControls.setValue(0.02, forKey: kCIInputBrightnessKey)

    guard let normalizedImage = colorControls.outputImage?.cropped(to: ciImage.extent) else {
      return nil
    }

    sharpen.setValue(normalizedImage, forKey: kCIInputImageKey)
    sharpen.setValue(0.45, forKey: kCIInputSharpnessKey)

    guard let outputImage = sharpen.outputImage?.cropped(to: ciImage.extent) else {
      return nil
    }

    return ciContext.createCGImage(outputImage, from: ciImage.extent)
  }

  private func meaningfulCharacterCount(in text: String) -> Int {
    text.unicodeScalars.reduce(into: 0) { count, scalar in
      guard !CharacterSet.whitespacesAndNewlines.contains(scalar) else { return }
      if CharacterSet.alphanumerics.contains(scalar) || isCJKScalar(scalar) || isKanaScalar(scalar) || isHangulScalar(scalar) {
        count += 1
      }
    }
  }

  private func cjkCharacterCount(in text: String) -> Int {
    text.unicodeScalars.reduce(into: 0) { count, scalar in
      if isCJKScalar(scalar) || isKanaScalar(scalar) || isHangulScalar(scalar) {
        count += 1
      }
    }
  }

  private func containsExpectedScript(for languageIdentifier: String, in text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
      switch languageIdentifier {
      case "ja":
        return isCJKScalar(scalar) || isKanaScalar(scalar)
      case "ko":
        return isHangulScalar(scalar)
      case "zh-Hans", "zh-Hant":
        return isCJKScalar(scalar)
      default:
        return true
      }
    }
  }

  private func isCJKLanguage(_ languageIdentifier: String) -> Bool {
    switch languageIdentifier {
    case "ja", "ko", "zh-Hans", "zh-Hant":
      return true
    default:
      return false
    }
  }

  private func isCJKScalar(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
      return true
    default:
      return false
    }
  }

  private func isKanaScalar(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x3040...0x309F, 0x30A0...0x30FF:
      return true
    default:
      return false
    }
  }

  private func isHangulScalar(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF:
      return true
    default:
      return false
    }
  }
}
