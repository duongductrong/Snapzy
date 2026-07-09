//
//  OCRLinkDetectorTests.swift
//  SnapzyTests
//
//  Unit tests for exclusive web link detection in OCR-captured text.
//

import XCTest
@testable import Snapzy

final class OCRLinkDetectorTests: XCTestCase {

  func testDetectsTextThatIsExactlyAWebURL() {
    let link = OCRLinkDetector.exclusiveWebLink(in: "https://example.com/docs")

    XCTAssertEqual(link?.absoluteString, "https://example.com/docs")
  }

  func testTrimsSurroundingWhitespaceAndNewlines() {
    let link = OCRLinkDetector.exclusiveWebLink(in: "  \n https://example.com/docs \n ")

    XCTAssertEqual(link?.absoluteString, "https://example.com/docs")
  }

  func testPromotesBareDomainToHTTP() {
    let link = OCRLinkDetector.exclusiveWebLink(in: "example.com")

    XCTAssertEqual(link?.scheme, "http")
    XCTAssertEqual(link?.host, "example.com")
  }

  func testRejectsURLEmbeddedInLargerText() {
    XCTAssertNil(OCRLinkDetector.exclusiveWebLink(in: "Visit https://example.com for details"))
    XCTAssertNil(OCRLinkDetector.exclusiveWebLink(in: "https://example.com is great"))
    XCTAssertNil(
      OCRLinkDetector.exclusiveWebLink(
        in: """
        Meeting notes
        https://zoom.us/rec/share/abc123
        """
      )
    )
  }

  func testRejectsMultipleURLs() {
    XCTAssertNil(OCRLinkDetector.exclusiveWebLink(in: "https://first.com https://second.com"))
    XCTAssertNil(
      OCRLinkDetector.exclusiveWebLink(
        in: """
        https://first.com
        https://second.com
        """
      )
    )
  }

  func testRejectsEmailAddressesAndCustomSchemes() {
    XCTAssertNil(OCRLinkDetector.exclusiveWebLink(in: "hello@example.com"))
    XCTAssertNil(OCRLinkDetector.exclusiveWebLink(in: "snapzy://capture/area"))
  }

  func testRejectsEmptyAndPlainText() {
    XCTAssertNil(OCRLinkDetector.exclusiveWebLink(in: ""))
    XCTAssertNil(OCRLinkDetector.exclusiveWebLink(in: "   \n  "))
    XCTAssertNil(OCRLinkDetector.exclusiveWebLink(in: "No links in this sentence."))
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
