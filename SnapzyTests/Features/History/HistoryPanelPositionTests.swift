//
//  HistoryPanelPositionTests.swift
//  SnapzyTests
//
//  Unit tests for HistoryPanelPosition layout math and HistoryBackgroundStyle persistence.
//

import AppKit
import XCTest
@testable import Snapzy

final class HistoryPanelPositionTests: XCTestCase {

  private var screen: NSScreen!

  override func setUp() {
    super.setUp()
    screen = NSScreen.main ?? NSScreen.screens.first
  }

  // MARK: - calculateOrigin

  func testTopCenterPositionsAtTopWithPadding() throws {
    guard let screen else {
      throw XCTSkip("No NSScreen available in test environment")
    }
    let size = CGSize(width: 400, height: 200)
    let origin = HistoryPanelPosition.topCenter.calculateOrigin(for: size, on: screen, padding: 20)

    let frame = screen.visibleFrame
    XCTAssertEqual(origin.x, frame.midX - size.width / 2, accuracy: 0.0001)
    XCTAssertEqual(origin.y, frame.maxY - size.height - 20, accuracy: 0.0001)
  }

  func testBottomCenterPositionsAtBottomWithPadding() throws {
    guard let screen else {
      throw XCTSkip("No NSScreen available in test environment")
    }
    let size = CGSize(width: 400, height: 200)
    let origin = HistoryPanelPosition.bottomCenter.calculateOrigin(for: size, on: screen, padding: 20)

    let frame = screen.visibleFrame
    XCTAssertEqual(origin.x, frame.midX - size.width / 2, accuracy: 0.0001)
    XCTAssertEqual(origin.y, frame.minY + 20, accuracy: 0.0001)
  }

  func testCenterPositionsAtVerticalCenter() throws {
    guard let screen else {
      throw XCTSkip("No NSScreen available in test environment")
    }
    let size = CGSize(width: 400, height: 200)
    let origin = HistoryPanelPosition.center.calculateOrigin(for: size, on: screen, padding: 20)

    let frame = screen.visibleFrame
    XCTAssertEqual(origin.x, frame.midX - size.width / 2, accuracy: 0.0001)
    XCTAssertEqual(origin.y, frame.midY - size.height / 2, accuracy: 0.0001)
  }

  func testCalculateOriginIgnoresPaddingForCenterCase() throws {
    guard let screen else {
      throw XCTSkip("No NSScreen available in test environment")
    }
    let size = CGSize(width: 200, height: 100)
    let withPadding = HistoryPanelPosition.center.calculateOrigin(for: size, on: screen, padding: 999)
    let withoutPadding = HistoryPanelPosition.center.calculateOrigin(for: size, on: screen, padding: 0)

    XCTAssertEqual(withPadding, withoutPadding)
  }

  // MARK: - allCases

  func testAllCasesExcludesCenter() {
    XCTAssertEqual(HistoryPanelPosition.allCases, [.topCenter, .bottomCenter])
    XCTAssertFalse(HistoryPanelPosition.allCases.contains(.center))
  }

  // MARK: - HistoryBackgroundStyle

  func testCurrentStoredStyle_readsValidValue() throws {
    let defaults = try makeDefaults()
    defaults.set(HistoryBackgroundStyle.solid.rawValue, forKey: PreferencesKeys.historyBackgroundStyle)

    XCTAssertEqual(HistoryBackgroundStyle.currentStoredStyle(userDefaults: defaults), .solid)
  }

  func testCurrentStoredStyle_fallbackToDefaultForInvalidValue() throws {
    let defaults = try makeDefaults()
    defaults.set("invalid", forKey: PreferencesKeys.historyBackgroundStyle)

    XCTAssertEqual(HistoryBackgroundStyle.currentStoredStyle(userDefaults: defaults), .hud)
  }

  func testCurrentStoredStyle_fallbackToDefaultForMissingKey() throws {
    let defaults = try makeDefaults()
    XCTAssertEqual(HistoryBackgroundStyle.currentStoredStyle(userDefaults: defaults), .hud)
  }

  func testAllBackgroundStylesAreUnique() {
    let all = HistoryBackgroundStyle.allCases
    XCTAssertEqual(Set(all).count, all.count)
  }

  // MARK: - Helpers

  private func makeDefaults(
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws -> UserDefaults {
    let suiteName = "SnapzyTests.HistoryPanelPositionTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName), file: file, line: line)
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }
}
