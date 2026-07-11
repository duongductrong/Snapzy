//
//  OCRLinkDetectorTests.swift
//  SnapzyTests
//
//  Unit tests for web link detection in OCR-captured text.
//

import XCTest
@testable import Snapzy

final class OCRLinkDetectorTests: XCTestCase {

  func testDetectsExplicitWebURL() {
    let links = OCRLinkDetector.detectWebLinks(in: "Visit https://example.com/docs for details")

    XCTAssertEqual(links.map(\.absoluteString), ["https://example.com/docs"])
  }

  func testPromotesBareDomainToHTTP() {
    let links = OCRLinkDetector.detectWebLinks(in: "Docs live at example.com today")

    XCTAssertEqual(links.count, 1)
    XCTAssertEqual(links.first?.scheme, "http")
    XCTAssertEqual(links.first?.host, "example.com")
  }

  func testIgnoresEmailAddressesAndCustomSchemes() {
    let text = "Contact hello@example.com or launch snapzy://capture/area"
    let links = OCRLinkDetector.detectWebLinks(in: text)

    XCTAssertTrue(links.isEmpty)
  }

  func testDeduplicatesRepeatedLinks() {
    let text = """
    https://example.com/page
    HTTPS://EXAMPLE.COM/page
    https://example.com/page/
    """
    let links = OCRLinkDetector.detectWebLinks(in: text)

    XCTAssertEqual(links.count, 1)
  }

  func testKeepsLinksThatDifferOnlyByPathCase() {
    let text = "https://example.com/Foo and https://example.com/foo"
    let links = OCRLinkDetector.detectWebLinks(in: text)

    XCTAssertEqual(links.count, 2)
  }

  func testPreservesOrderAndRespectsLimit() {
    let text = "https://first.com then https://second.com then https://third.com then https://fourth.com"
    let links = OCRLinkDetector.detectWebLinks(in: text)

    XCTAssertEqual(links.count, OCRLinkDetector.maxDetectedLinks)
    XCTAssertEqual(links.first?.host, "first.com")

    let limited = OCRLinkDetector.detectWebLinks(in: text, limit: 1)
    XCTAssertEqual(limited.map(\.host), ["first.com"])
  }

  func testEmptyAndPlainTextYieldNoLinks() {
    XCTAssertTrue(OCRLinkDetector.detectWebLinks(in: "").isEmpty)
    XCTAssertTrue(OCRLinkDetector.detectWebLinks(in: "No links in this sentence.").isEmpty)
  }

  func testDetectsLinkInsideMultilineOCROutput() {
    let text = """
    Meeting notes
    Agenda: review roadmap
    Recording: https://zoom.us/rec/share/abc123
    Attendees: 5
    """
    let links = OCRLinkDetector.detectWebLinks(in: text)

    XCTAssertEqual(links.map(\.absoluteString), ["https://zoom.us/rec/share/abc123"])
  }

  func testDisplayStringStripsSchemeAndTrailingSlash() {
    let url = URL(string: "https://example.com/path/")!

    XCTAssertEqual(OCRLinkDetector.displayString(for: url), "example.com/path")
    XCTAssertEqual(
      OCRLinkDetector.displayString(for: URL(string: "http://example.com")!),
      "example.com"
    )
  }
}
