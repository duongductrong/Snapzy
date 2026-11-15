//
//  OCRTextLayoutFormatterTests.swift
//  SnapzyTests
//
//  Layout reconstruction for OCR text: list items, hard breaks, clipped glyphs.
//

import XCTest
@testable import Snapzy

final class OCRTextLayoutFormatterTests: XCTestCase {
  private let imageSize = CGSize(width: 2000, height: 610)

  /// Builds a line from pixel coordinates (top-left origin), like a screenshot.
  private func line(_ text: String, x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat = 30) -> OCRTextLine {
    OCRTextLine(
      text: text,
      confidence: 0.9,
      boundingBox: CGRect(
        x: x / imageSize.width,
        y: (imageSize.height - top - height) / imageSize.height,
        width: width / imageSize.width,
        height: height / imageSize.height
      )
    )
  }

  private func format(_ lines: [OCRTextLine], cjk: Bool = false) -> String {
    OCRTextLayoutFormatter(imageSize: imageSize, prefersCJK: cjk).format(lines)
  }

  func testBulletList_keepsOneItemPerLineAndJoinsWrappedRows() {
    let lines = [
      line("Phase 1 of #720: select an area, OCR it, and show a window.", x: 46, top: 58, width: 1690),
      line("• Reuses the Capture Text flow; only the last step differs.", x: 78, top: 131, width: 1120),
      line("• Engines: Apple Translation (default) or a custom endpoint. No automatic fallback to an", x: 78, top: 180, width: 1910),
      line("endpoint: text leaves the device only after an explicit click.", x: 101, top: 221, width: 750),
      line("• Settings: target language and engine under Capture > OCR.", x: 78, top: 270, width: 1210),
      line("P", x: 1975, top: 270, width: 22),
      line("Pinned live-translate frame (part 2 of #720) is out of scope.", x: 46, top: 524, width: 760)
    ]

    XCTAssertEqual(
      format(lines),
      """
      Phase 1 of #720: select an area, OCR it, and show a window.

      - Reuses the Capture Text flow; only the last step differs.
      - Engines: Apple Translation (default) or a custom endpoint. No automatic fallback to an endpoint: text leaves the device only after an explicit click.
      - Settings: target language and engine under Capture > OCR.

      Pinned live-translate frame (part 2 of #720) is out of scope.
      """
    )
  }

  func testNumberedAndDashedListsAreDetected() {
    XCTAssertTrue(OCRTextLayoutFormatter.startsWithListMarker("1. First"))
    XCTAssertTrue(OCRTextLayoutFormatter.startsWithListMarker("2) Second"))
    XCTAssertTrue(OCRTextLayoutFormatter.startsWithListMarker("- dash item"))
    XCTAssertTrue(OCRTextLayoutFormatter.startsWithListMarker("•No space"))
    XCTAssertFalse(OCRTextLayoutFormatter.startsWithListMarker("2026 was a year"))
    XCTAssertFalse(OCRTextLayoutFormatter.startsWithListMarker("-1 degrees"))
  }

  func testSymbolBullets_areNormalizedToDash() {
    for marker in ["•", "●", "○", "◦", "▪", "■", "□", "‣", "➤", "✓", "–", "—", "*", "+", "-"] {
      XCTAssertEqual(OCRTextLayoutFormatter.normalizingBulletMarker("\(marker) Item"), "- Item", marker)
    }
    XCTAssertEqual(OCRTextLayoutFormatter.normalizingBulletMarker("•Item"), "- Item")
    XCTAssertEqual(OCRTextLayoutFormatter.normalizingBulletMarker("1. Item"), "1. Item")
    XCTAssertEqual(OCRTextLayoutFormatter.normalizingBulletMarker("a) Item"), "a) Item")
  }

  func testNumberedList_keepsNumbers() {
    let lines = [
      line("1. First step", x: 40, top: 20, width: 300),
      line("2. Second step", x: 40, top: 60, width: 300)
    ]

    XCTAssertEqual(format(lines), "1. First step\n2. Second step")
  }

  func testListEndsWhenRowReturnsToMarkerColumn() {
    let lines = [
      line("- first item", x: 40, top: 20, width: 300),
      line("- second item", x: 40, top: 60, width: 300),
      line("Plain text after the list", x: 40, top: 100, width: 400)
    ]

    XCTAssertEqual(format(lines), "- first item\n- second item\nPlain text after the list")
  }

  func testProse_reflowsWrappedRowsButKeepsShortSentenceBreak() {
    let lines = [
      line("This paragraph wraps across several rows of the screenshot and", x: 40, top: 20, width: 1800),
      line("should be joined back together into one line.", x: 40, top: 60, width: 1200),
      line("A new sentence starts on its own line here and it keeps going across", x: 40, top: 100, width: 1810),
      line("the width.", x: 40, top: 140, width: 300)
    ]

    XCTAssertEqual(
      format(lines),
      """
      This paragraph wraps across several rows of the screenshot and should be joined back together into one line.
      A new sentence starts on its own line here and it keeps going across the width.
      """
    )
  }

  func testShortLabels_stayOnSeparateLines() {
    let lines = [
      line("General", x: 40, top: 20, width: 160),
      line("Capture", x: 40, top: 60, width: 160),
      line("Shortcuts", x: 40, top: 100, width: 180)
    ]

    XCTAssertEqual(format(lines), "General\nCapture\nShortcuts")
  }

  func testSameRowFragments_areMergedWithSpace() {
    let lines = [
      line("Copy", x: 40, top: 20, width: 100),
      line("Translation", x: 160, top: 22, width: 200)
    ]

    XCTAssertEqual(format(lines), "Copy Translation")
  }
}
