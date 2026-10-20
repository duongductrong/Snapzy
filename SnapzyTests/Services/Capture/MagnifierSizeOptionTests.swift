//
//  MagnifierSizeOptionTests.swift
//  SnapzyTests
//
//  Unit tests for the magnifier size preference model and the copy-hint row fit rule
//  that keeps narrower magnifier sizes from clipping long translations.
//

import XCTest
@testable import Snapzy

final class MagnifierSizeOptionTests: XCTestCase {

  func testDefaultIsMediumAndKeepsPreviousSize() {
    // Upgrading users must see the same 160pt magnifier they had before the preference existed.
    XCTAssertEqual(MagnifierSizeOption.defaultValue, .medium)
    XCTAssertEqual(MagnifierSizeOption.medium.previewSize, 160)
  }

  func testPreviewSizesAreStrictlyAscending() {
    let sizes = MagnifierSizeOption.allCases.map(\.previewSize)
    XCTAssertEqual(sizes, sizes.sorted())
    XCTAssertEqual(Set(sizes).count, sizes.count)
    XCTAssertLessThan(MagnifierSizeOption.small.previewSize, MagnifierSizeOption.medium.previewSize)
  }

  func testResolve_fallsBackToDefaultForMissingOrUnknownValues() {
    XCTAssertEqual(MagnifierSizeOption.resolve("small"), .small)
    XCTAssertEqual(MagnifierSizeOption.resolve("large"), .large)
    XCTAssertEqual(MagnifierSizeOption.resolve(nil), .medium)
    XCTAssertEqual(MagnifierSizeOption.resolve("huge"), .medium)
  }

  func testCurrent_readsProvidedDefaults() {
    let defaults = UserDefaultsFactory.make()
    XCTAssertEqual(MagnifierSizeOption.current(defaults: defaults), .medium)

    defaults.set(MagnifierSizeOption.small.rawValue, forKey: PreferencesKeys.screenshotMagnifierSize)
    XCTAssertEqual(MagnifierSizeOption.current(defaults: defaults), .small)
  }

  func testHintRowFitsPrefix_keepsPrefixWhenWholeRowFits() {
    // 30 + 6 + 16 + 6 + 40 = 98 <= 108
    XCTAssertTrue(AreaSelectionMagnifier.hintRowFitsPrefix(
      prefixWidth: 30, suffixWidth: 40, availableWidth: 108, keyCapSize: 16, gap: 6
    ))
  }

  func testHintRowFitsPrefix_dropsPrefixWhenRowOverflows() {
    // e.g. French "Appuyez sur [C] pour copier" on the small magnifier.
    XCTAssertFalse(AreaSelectionMagnifier.hintRowFitsPrefix(
      prefixWidth: 66, suffixWidth: 62, availableWidth: 108, keyCapSize: 16, gap: 6
    ))
  }

  func testHintRowFitsPrefix_emptyPrefixNeverShows() {
    // Japanese/Korean have no prefix: the row starts with the key cap.
    XCTAssertFalse(AreaSelectionMagnifier.hintRowFitsPrefix(
      prefixWidth: 0, suffixWidth: 40, availableWidth: 500, keyCapSize: 16, gap: 6
    ))
  }
}
