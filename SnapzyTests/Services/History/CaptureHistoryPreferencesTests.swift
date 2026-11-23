//
//  CaptureHistoryPreferencesTests.swift
//  SnapzyTests
//
//  Verify the shared Capture History enabled reader applies the intended
//  default (`true`) consistently, unlike `bool(forKey:)` which defaults to
//  `false` for a never-written key.
//

import AppKit
@testable import Snapzy
import SwiftUI
import XCTest

final class CaptureHistoryPreferencesTests: XCTestCase {
  private var originalValue: Bool?

  override func setUp() {
    super.setUp()
    originalValue = UserDefaults.standard.object(forKey: PreferencesKeys.historyEnabled) as? Bool
  }

  override func tearDown() {
    if let originalValue {
      UserDefaults.standard.set(originalValue, forKey: PreferencesKeys.historyEnabled)
    } else {
      UserDefaults.standard.removeObject(forKey: PreferencesKeys.historyEnabled)
    }
    super.tearDown()
  }

  func testDefaultsToEnabledWhenKeyNeverWritten() {
    UserDefaults.standard.removeObject(forKey: PreferencesKeys.historyEnabled)

    XCTAssertTrue(UserDefaults.standard.snapzyHistoryEnabled)
    XCTAssertFalse(
      UserDefaults.standard.bool(forKey: PreferencesKeys.historyEnabled),
      "Precondition: raw bool(forKey:) defaults to false — the inconsistency this accessor fixes"
    )
  }

  func testRespectsExplicitDisabled() {
    UserDefaults.standard.set(false, forKey: PreferencesKeys.historyEnabled)

    XCTAssertFalse(UserDefaults.standard.snapzyHistoryEnabled)
  }

  func testRespectsExplicitEnabled() {
    UserDefaults.standard.set(true, forKey: PreferencesKeys.historyEnabled)

    XCTAssertTrue(UserDefaults.standard.snapzyHistoryEnabled)
  }

  /// Regression: in Light Mode with `.solid` backdrop, unselected filter pills, borders, and
  /// count capsules must use dark-tinted contrast fills instead of invisible white-on-white.
  func testHistoryFilterBar_lightModeSolidUsesVisibleDarkTintedPillsAndBadges() throws {
    let fill = try XCTUnwrap(
      NSColor(HistoryFilterBar.unselectedPillFillColor(backgroundStyle: .solid, colorScheme: .light))
        .usingColorSpace(.sRGB)
    )
    let border = try XCTUnwrap(
      NSColor(HistoryFilterBar.pillBorderColor(isSelected: false, colorScheme: .light))
        .usingColorSpace(.sRGB)
    )
    let badge = try XCTUnwrap(
      NSColor(HistoryFilterBar.countBadgeBackgroundColor(isSelected: false, colorScheme: .light))
        .usingColorSpace(.sRGB)
    )

    XCTAssertLessThan(fill.brightnessComponent, 0.2, "Light Mode solid pill fill must not be white-on-white")
    XCTAssertLessThan(border.brightnessComponent, 0.2, "Light Mode pill border must not be white-on-white")
    XCTAssertLessThan(badge.brightnessComponent, 0.2, "Light Mode count capsule must not be white-on-white")

    let selectedBadge = try XCTUnwrap(
      NSColor(HistoryFilterBar.countBadgeBackgroundColor(isSelected: true, colorScheme: .light))
        .usingColorSpace(.sRGB)
    )
    XCTAssertGreaterThan(selectedBadge.brightnessComponent, 0.8, "Selected pill count capsule on accent stays light")
  }
}
