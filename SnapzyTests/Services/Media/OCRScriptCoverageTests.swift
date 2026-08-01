//
//  OCRScriptCoverageTests.swift
//  SnapzyTests
//
//  Dictionary charset analysis: what a PP-OCR model can and cannot spell.
//

import XCTest
@testable import Snapzy

final class OCRScriptCoverageTests: XCTestCase {

  /// One dictionary line per character, as `dict.txt` is laid out.
  private func dictionary(_ characters: String...) -> [String] {
    characters.flatMap { $0.map(String.init) }
  }

  func testFullyCoveredScriptReportsFull() {
    let latin = OCRScript.probes[.latin] ?? []
    let report = OCRScriptCoverageReport.analyze(dictionary: latin.map(String.init))
    XCTAssertEqual(report.support(for: .latin), .full)
    XCTAssertTrue(report.fullySupported.contains(.latin))
    XCTAssertFalse(report.partiallySupported.contains(.latin))
  }

  func testAbsentScriptReportsUnsupported() {
    let report = OCRScriptCoverageReport.analyze(dictionary: dictionary("abcXYZ123"))
    XCTAssertEqual(report.support(for: .thai), .unsupported)
    XCTAssertEqual(report.support(for: .korean), .unsupported)
    XCTAssertEqual(report.coverage[.thai], 0)
  }

  /// The PP-OCRv6 failure this analysis exists to surface: the base vowels are
  /// present, the precomposed tone block is not, so recognition silently
  /// substitutes rather than failing.
  func testVietnameseWithoutToneMarksReportsPartial() {
    var characters = "abcdefghijklmnopqrstuvwxyz"
    characters += "àáâãèéêìíòóôõùúýăđĩũơư"  // in PP-OCRv6, no U+1EA0–U+1EF9
    let report = OCRScriptCoverageReport.analyze(dictionary: dictionary(characters))

    XCTAssertEqual(report.support(for: .vietnamese), .partial)
    XCTAssertTrue(report.partiallySupported.contains(.vietnamese))
    XCTAssertFalse(report.fullySupported.contains(.vietnamese))
    let coverage = report.coverage[.vietnamese] ?? 0
    XCTAssertGreaterThan(coverage, OCRScriptCoverageReport.unsupportedThreshold)
    XCTAssertLessThan(coverage, OCRScriptCoverageReport.fullThreshold)
  }

  func testFullVietnameseToneBlockReportsFull() {
    let vietnamese = OCRScript.probes[.vietnamese] ?? []
    let report = OCRScriptCoverageReport.analyze(dictionary: vietnamese.map(String.init))
    XCTAssertEqual(report.support(for: .vietnamese), .full)
  }

  func testCharacterCountTracksDictionaryLines() {
    let lines = dictionary("abc") + [" "]
    XCTAssertEqual(OCRScriptCoverageReport.analyze(dictionary: lines).characterCount, 4)
  }

  func testEmptyDictionarySupportsNothing() {
    let report = OCRScriptCoverageReport.analyze(dictionary: [])
    XCTAssertTrue(report.fullySupported.isEmpty)
    XCTAssertTrue(report.partiallySupported.isEmpty)
    XCTAssertEqual(report.characterCount, 0)
  }
}
