//
//  OCRRecognitionTests.swift
//  SnapzyTests
//
//  Regression coverage for language-aware Vision OCR routing.
//

@testable import Snapzy
import Vision
import XCTest

@MainActor
final class OCRRecognitionTests: XCTestCase {
  func testVisionOCRProfile_routesReadmeSupportedLanguages() throws {
    let cases: [(language: String, primaryVisionLanguage: String?, profileID: String)] = [
      ("en", nil, "default-interface"),
      ("vi", "vi-VT", "vietnamese-interface"),
      ("zh-Hans", "zh-Hans", "simplified-chinese-interface"),
      ("zh-Hant", "zh-Hant", "traditional-chinese-interface"),
      ("es", "es-ES", "spanish-interface"),
      ("ja", "ja-JP", "japanese-interface"),
      ("ko", "ko-KR", "korean-interface"),
      ("ru", "ru-RU", "russian-interface"),
      ("fr", "fr-FR", "french-interface"),
      ("de", "de-DE", "german-interface"),
    ]

    for testCase in cases {
      let profile = try VisionOCRProfile.resolve(
        for: OCRRequest(
          image: OCRTestImageRenderer.renderImage(text: "Snapzy OCR"),
          preferredLanguageIdentifier: testCase.language
        )
      )

      XCTAssertEqual(profile.id, testCase.profileID, testCase.language)
      XCTAssertEqual(profile.recognitionLanguages.first, testCase.primaryVisionLanguage, testCase.language)
      XCTAssertEqual(profile.automaticallyDetectsLanguage, testCase.primaryVisionLanguage == nil, testCase.language)
      XCTAssertTrue(profile.usesLanguageCorrection, testCase.language)
    }
  }

  func testVietnameseOCR_preservesDiacriticsForShortIssuePhrase() async throws {
    try XCTSkipIf(!supportedVisionLanguages().contains("vi-VT"), "Vision Vietnamese OCR unavailable")

    let result = try await OCRService.shared.recognizeWithVision(
      OCRRequest(
        image: OCRTestImageRenderer.renderImage(text: "Tài sản"),
        preferredLanguageIdentifier: "vi",
        contentType: .interfaceText
      )
    )

    XCTAssertTrue(result.text.contains("Tài sản"), result.text)
    XCTAssertFalse(result.text.contains("Tai san"), result.text)
    XCTAssertEqual(result.profileID, "vietnamese-interface")
  }

  func testVietnameseOCR_preservesDiverseDiacriticsForCommonPhrases() async throws {
    try XCTSkipIf(!supportedVisionLanguages().contains("vi-VT"), "Vision Vietnamese OCR unavailable")

    let phrases = [
      "Tài sản cố định",
      "Số dư tài khoản",
      "Đường dẫn đã sao chép",
      "Ưu đãi đặc biệt",
      "Chỉnh sửa thủ công",
      "Cộng hòa xã hội",
    ]

    for phrase in phrases {
      let result = try await OCRService.shared.recognizeWithVision(
        OCRRequest(
          image: OCRTestImageRenderer.renderImage(text: phrase),
          preferredLanguageIdentifier: "vi",
          contentType: .interfaceText
        )
      )

      XCTAssertTrue(
        normalizedForDiacriticRegression(result.text).contains(normalizedForDiacriticRegression(phrase)),
        "expected \(phrase), got \(result.text)"
      )
    }
  }

  func testVietnameseOCR_reflowsSameRowWordFragments() async throws {
    try XCTSkipIf(!supportedVisionLanguages().contains("vi-VT"), "Vision Vietnamese OCR unavailable")

    let result = try await OCRService.shared.recognizeWithVision(
      OCRRequest(
        image: OCRTestImageRenderer.renderImage(textChunks: ["Ưu đãi", "đặc", "biệt"], horizontalGap: 100),
        preferredLanguageIdentifier: "vi",
        contentType: .interfaceText
      )
    )

    XCTAssertTrue(
      OCRBenchmarkMetrics.normalized(result.text).contains("Ưu đãi đặc biệt"),
      "expected same-row fragments to reflow, got \(result.text)"
    )
  }

  func testOCR_recognizesReadmeSupportedLanguageSamples() async throws {
    let cases: [(language: String, visionLanguage: String, text: String)] = [
      ("en", "en-US", "Copy text"),
      ("vi", "vi-VT", "Chính xác"),
      ("zh-Hans", "zh-Hans", "复制文本"),
      ("zh-Hant", "zh-Hant", "複製文字"),
      ("es", "es-ES", "Texto rápido"),
      ("ja", "ja-JP", "設定画面"),
      ("ko", "ko-KR", "설정 화면"),
      ("ru", "ru-RU", "Точные заметки"),
      ("fr", "fr-FR", "Texte précis"),
      ("de", "de-DE", "Überschriften"),
    ]
    let supportedLanguages = try supportedVisionLanguages()

    for testCase in cases {
      try XCTSkipIf(
        !supportedLanguages.contains(testCase.visionLanguage),
        "Vision OCR language \(testCase.visionLanguage) unavailable"
      )

      let result = try await OCRService.shared.recognizeWithVision(
        OCRRequest(
          image: OCRTestImageRenderer.renderImage(text: testCase.text),
          preferredLanguageIdentifier: testCase.language,
          contentType: .interfaceText
        )
      )

      XCTAssertTrue(
        OCRBenchmarkMetrics.normalized(result.text).contains(testCase.text),
        "\(testCase.language): expected \(testCase.text), got \(result.text)"
      )
    }
  }

  func testSimplifiedChineseOCR_recognizesVerticalStreetSignText() async throws {
    try XCTSkipIf(!supportedVisionLanguages().contains("zh-Hans"), "Vision Simplified Chinese OCR unavailable")

    let result = try await OCRService.shared.recognizeWithVision(
      OCRRequest(
        image: OCRTestImageRenderer.renderVerticalCJKImage(text: "龙沄路"),
        preferredLanguageIdentifier: "zh-Hans",
        contentType: .interfaceText
      )
    )

    XCTAssertTrue(
      normalizedForCJKRegression(result.text).contains("龙沄路"),
      "expected vertical Chinese text to be recognized in reading order, got \(result.text)"
    )
  }

  private func supportedVisionLanguages() throws -> Set<String> {
    try Set(VNRecognizeTextRequest().supportedRecognitionLanguages())
  }

  private func normalizedForDiacriticRegression(_ text: String) -> String {
    OCRBenchmarkMetrics.normalized(text).filter { !$0.isWhitespace }
  }

  private func normalizedForCJKRegression(_ text: String) -> String {
    OCRBenchmarkMetrics.normalized(text).filter { !$0.isWhitespace }
  }
}
