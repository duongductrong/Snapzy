//
//  OCRNotificationContentTests.swift
//  SnapzyTests
//
//  Unit tests for OCR result notification titles, bodies, and text previews.
//

import XCTest
@testable import Snapzy

final class OCRNotificationContentTests: XCTestCase {

  // MARK: - Preview formatting

  func testPreviewKeepsShortTextUnchanged() {
    XCTAssertEqual(OCRNotificationContent.preview("Subnet 策略组 RouterOS-LAN"), "Subnet 策略组 RouterOS-LAN")
  }

  func testPreviewCollapsesNewlinesAndRepeatedWhitespaceIntoSingleSpaces() {
    let text = "  first line \n\n\tsecond   line \r\n third\t\tline  "

    XCTAssertEqual(OCRNotificationContent.preview(text), "first line second line third line")
  }

  func testPreviewTruncatesLongTextWithEllipsis() {
    let text = String(repeating: "a", count: 500)

    let preview = OCRNotificationContent.preview(text, limit: 200)

    XCTAssertEqual(preview.count, 201, "200 characters plus the ellipsis")
    XCTAssertTrue(preview.hasSuffix("…"))
    XCTAssertEqual(String(preview.dropLast()), String(repeating: "a", count: 200))
  }

  func testPreviewDoesNotTruncateTextExactlyAtTheLimit() {
    let text = String(repeating: "b", count: 12)

    XCTAssertEqual(OCRNotificationContent.preview(text, limit: 12), text)
  }

  func testPreviewTrimsTrailingWhitespaceBeforeTheEllipsis() {
    let text = "one two three four"

    XCTAssertEqual(OCRNotificationContent.preview(text, limit: 8), "one two…")
  }

  func testPreviewTruncatesOnGraphemeClustersForEmojiAndCombiningMarks() {
    // Family emoji and a combining-diacritic sequence are single grapheme clusters that
    // must never be cut in half.
    let familyEmoji = "👨‍👩‍👧‍👦"
    let text = String(repeating: familyEmoji, count: 6) + "e\u{0301}"

    XCTAssertEqual(text.count, 7, "6 emoji clusters plus one combining sequence")
    XCTAssertEqual(OCRNotificationContent.preview(text, limit: 3), String(repeating: familyEmoji, count: 3) + "…")
    XCTAssertEqual(OCRNotificationContent.preview(text, limit: 6), String(repeating: familyEmoji, count: 6) + "…")
    XCTAssertEqual(OCRNotificationContent.preview(text, limit: 7), text, "no truncation at exactly the limit")
  }

  func testPreviewSupportsNonLatinScripts() {
    XCTAssertEqual(OCRNotificationContent.preview("Xin chào thế giới"), "Xin chào thế giới")
    XCTAssertEqual(OCRNotificationContent.preview("안녕하세요\n반갑습니다"), "안녕하세요 반갑습니다")
    XCTAssertEqual(OCRNotificationContent.preview("Привет мир", limit: 6), "Привет…")
  }

  func testPreviewReturnsEmptyStringForBlankOrZeroLimitInput() {
    XCTAssertEqual(OCRNotificationContent.preview("   \n\t  "), "")
    XCTAssertEqual(OCRNotificationContent.preview("anything", limit: 0), "")
  }

  // MARK: - Titles and bodies

  func testCopiedOutcomeUsesCopiedTitleAndTextPreview() {
    let outcome = OCRCaptureOutcome.copied("Subnet 策略组\nRouterOS-LAN")

    XCTAssertEqual(OCRNotificationContent.title(for: outcome), L10n.OCR.notificationCopiedTitle)
    XCTAssertEqual(OCRNotificationContent.body(for: outcome), "Subnet 策略组 RouterOS-LAN")
  }

  func testNoTextOutcomeUsesDedicatedTitleAndBody() {
    let outcome = OCRCaptureOutcome.noText

    XCTAssertEqual(OCRNotificationContent.title(for: outcome), L10n.OCR.notificationNoTextTitle)
    XCTAssertEqual(OCRNotificationContent.body(for: outcome), L10n.OCR.notificationNoTextBody)
  }

  func testUnsupportedQROutcomeReusesNoTextTitleWithSpecificBody() {
    let outcome = OCRCaptureOutcome.qrTextOnlyUnsupported

    XCTAssertEqual(OCRNotificationContent.title(for: outcome), L10n.OCR.notificationNoTextTitle)
    XCTAssertEqual(OCRNotificationContent.body(for: outcome), L10n.OCR.qrTextOnlyUnsupported)
  }

  func testFailedOutcomeKeepsGenericBodyInsteadOfTheUnderlyingError() {
    let outcome = OCRCaptureOutcome.failed(errorDescription: "CRImageReaderError 3")

    XCTAssertEqual(OCRNotificationContent.title(for: outcome), L10n.OCR.notificationFailedTitle)
    XCTAssertEqual(OCRNotificationContent.body(for: outcome), L10n.OCR.notificationFailedBody)
  }

  // MARK: - Authorization state

  func testOnlyAuthorizedCountsAsAuthorized() {
    XCTAssertTrue(SystemNotificationAuthorization.authorized.isAuthorized)
    XCTAssertFalse(SystemNotificationAuthorization.notDetermined.isAuthorized)
    XCTAssertFalse(SystemNotificationAuthorization.denied.isAuthorized)
    XCTAssertFalse(SystemNotificationAuthorization.unavailable.isAuthorized)
  }

  // MARK: - Preference gating

  @MainActor
  func testNotificationsAreEnabledByDefaultAndFollowThePreference() throws {
    // An isolated suite keeps this out of the shared standard domain, which the
    // parallel test processes all write to.
    let suiteName = "OCRNotificationContentTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let key = PreferencesKeys.ocrSuccessNotificationEnabled

    XCTAssertTrue(OCRResultNotifier.isEnabled(defaults: defaults), "unset preference defaults to on")

    defaults.set(false, forKey: key)
    XCTAssertFalse(OCRResultNotifier.isEnabled(defaults: defaults))

    defaults.set(true, forKey: key)
    XCTAssertTrue(OCRResultNotifier.isEnabled(defaults: defaults))
  }
}
