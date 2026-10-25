//
//  PreferencesSearchEngineTests.swift
//  SnapzyTests
//
//  Unit tests for Preferences search matching, ranking, and the settings catalog.
//

@testable import Snapzy
import XCTest

@MainActor
final class PreferencesSearchEngineTests: XCTestCase {
  private let engine = PreferencesSearchEngine(entries: [
    PreferencesSearchEntry(page: .quickAccess),
    PreferencesSearchEntry(.capture, section: "Screenshot", title: "Screenshot format",
                           detail: "File type used when saving screenshots", keywords: ["png", "jpg"]),
    PreferencesSearchEntry(.general, section: "Storage", title: "Save location"),
    PreferencesSearchEntry(.general, section: "Startup", title: "Play sounds",
                           detail: "Play a sound after capturing"),
    PreferencesSearchEntry(.shortcuts, section: nil, title: "Phím tắt chụp màn hình"),
    PreferencesSearchEntry(.history, section: "Đường dẫn", title: "Thư mục lưu"),
    PreferencesSearchEntry(.capture, section: nil, title: "スクリーンショットの形式"),
  ])

  private func titles(_ query: String) -> [String] {
    engine.search(query).map(\.entry.title)
  }

  func testBlankQuery_returnsNothing() {
    XCTAssertTrue(engine.search("   ").isEmpty)
  }

  func testExactAndPrefix_matchCaseInsensitively() {
    XCTAssertEqual(titles("SAVE").first, "Save location")
    XCTAssertEqual(titles("screens").first, "Screenshot format")
  }

  func testMultipleTokens_mustAllMatch() {
    XCTAssertEqual(titles("screenshot format"), ["Screenshot format"])
    XCTAssertTrue(titles("screenshot zebra").isEmpty)
  }

  func testTypo_isTolerated() {
    XCTAssertEqual(titles("screnshot").first, "Screenshot format")
    XCTAssertEqual(titles("lcoation").first, "Save location")
  }

  func testInitialsAndAbbreviation() {
    XCTAssertEqual(titles("qa").first, PreferencesTab.quickAccess.title)
    XCTAssertEqual(titles("fmt").first, "Screenshot format")
  }

  func testKeywordsSectionAndDetail_matchBelowTitle() {
    XCTAssertEqual(titles("png"), ["Screenshot format"])
    XCTAssertEqual(titles("storage"), ["Save location"])
    XCTAssertEqual(titles("capturing"), ["Play sounds"])
  }

  func testTitleMatch_outranksDetailMatch() {
    // "sound" is in Play sounds' title; "screenshots" only in Screenshot format's detail.
    let results = engine.search("sound")
    XCTAssertEqual(results.first?.entry.title, "Play sounds")
  }

  func testVietnamese_matchesWithoutDiacritics() {
    XCTAssertEqual(titles("phim tat").first, "Phím tắt chụp màn hình")
    XCTAssertEqual(titles("duong dan").first, "Thư mục lưu")
  }

  func testCJK_matchesSubstring() {
    XCTAssertEqual(titles("形式").first, "スクリーンショットの形式")
  }

  func testShortLatinFragments_doNotMatchMidWord() {
    XCTAssertFalse(titles("cr").contains("Screenshot format"))
  }

  func testTitleHighlights_mapToOriginalCharacters() throws {
    let result = try XCTUnwrap(engine.search("tắt").first)
    let highlighted = result.titleHighlights.map { String(result.entry.title[$0]) }
    XCTAssertEqual(highlighted, ["tắt"])
  }

  func testGroupedSearch_ordersPagesByBestHit() {
    let groups = engine.groupedSearch("screenshot")
    XCTAssertEqual(groups.first?.tab, .capture)
    XCTAssertNil(groups.first?.pageResult)
  }

  func testEditDistance_handlesTranspositionAndLimit() {
    XCTAssertEqual(PreferencesSearchEngine.editDistance(Array("ab"), Array("ba"), limit: 2), 1)
    XCTAssertEqual(PreferencesSearchEngine.editDistance(Array("kitten"), Array("sitting"), limit: 5), 3)
    XCTAssertEqual(PreferencesSearchEngine.editDistance(Array("abcdef"), Array("uvwxyz"), limit: 1), 2)
  }

  // MARK: - Catalog

  func testCatalog_hasUniqueNonEmptyEntries() {
    let catalog = PreferencesSearchEntry.catalog()
    XCTAssertGreaterThan(catalog.count, 50)
    for entry in catalog {
      XCTAssertFalse(entry.title.trimmingCharacters(in: .whitespaces).isEmpty, "Empty title in \(entry.tab)")
    }
    // Rows are anchored by title, so titles must be unique within whatever is on screen at once.
    let anchored = catalog.filter(\.anchored).map { "\($0.tab.rawValue)/\($0.pane ?? "")/\($0.title)" }
    let duplicates = Dictionary(grouping: anchored, by: { $0 }).filter { $1.count > 1 }.keys
    XCTAssertTrue(duplicates.isEmpty, "Duplicate anchors: \(duplicates.sorted())")
  }

  func testStandardEngine_ranksPageAboveItsSettings() {
    let first = PreferencesSearchEngine.standard().search(PreferencesTab.cloud.title).first
    XCTAssertEqual(first?.entry.id, PreferencesSearchEntry(page: .cloud).id)
  }
}
