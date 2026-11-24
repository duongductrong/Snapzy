//
//  HistoryFilterBarTests.swift
//  SnapzyTests
//
//  Light/Dark Mode contrast regression tests for HistoryFilterBar and HistoryToolbar.
//

import AppKit
@testable import Snapzy
import SwiftUI
import XCTest

@MainActor
final class HistoryFilterBarTests: XCTestCase {
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

    let selectedBadgeLight = try XCTUnwrap(
      NSColor(HistoryFilterBar.countBadgeBackgroundColor(isSelected: true, colorScheme: .light))
        .usingColorSpace(.sRGB)
    )
    let selectedBadgeDark = try XCTUnwrap(
      NSColor(HistoryFilterBar.countBadgeBackgroundColor(isSelected: true, colorScheme: .dark))
        .usingColorSpace(.sRGB)
    )
    XCTAssertGreaterThan(
      selectedBadgeLight.brightnessComponent,
      0.8,
      "Selected pill count capsule on accent stays light"
    )
    XCTAssertGreaterThan(
      selectedBadgeDark.brightnessComponent,
      0.8,
      "Selected pill count capsule in Dark Mode stays visible"
    )
  }

  /// Regression: HistoryToolbar search bar sits next to HistoryFilterBar in the same window and
  /// must also use dark-tinted fills and borders in Light Mode instead of white-on-white.
  func testHistoryToolbar_lightModeSolidUsesVisibleDarkTintedChrome() throws {
    let fillLight = try XCTUnwrap(
      NSColor(HistoryToolbar.chromeSurfaceFillColor(backgroundStyle: .solid, colorScheme: .light))
        .usingColorSpace(.sRGB)
    )
    let borderLight = try XCTUnwrap(
      NSColor(HistoryToolbar.chromeSurfaceBorderColor(colorScheme: .light))
        .usingColorSpace(.sRGB)
    )

    XCTAssertLessThan(fillLight.brightnessComponent, 0.2, "Light Mode solid toolbar fill must not be white-on-white")
    XCTAssertGreaterThan(fillLight.alphaComponent, 0.04, "Light Mode solid toolbar fill must have visible alpha")
    XCTAssertLessThan(borderLight.brightnessComponent, 0.2, "Light Mode toolbar border must not be white-on-white")
    XCTAssertGreaterThan(borderLight.alphaComponent, 0.05, "Light Mode toolbar border must have visible alpha")

    let fillDark = try XCTUnwrap(
      NSColor(HistoryToolbar.chromeSurfaceFillColor(backgroundStyle: .solid, colorScheme: .dark))
        .usingColorSpace(.sRGB)
    )
    let borderDark = try XCTUnwrap(
      NSColor(HistoryToolbar.chromeSurfaceBorderColor(colorScheme: .dark))
        .usingColorSpace(.sRGB)
    )
    XCTAssertGreaterThan(fillDark.brightnessComponent, 0.8, "Dark Mode toolbar fill stays light-tinted")
    XCTAssertGreaterThan(borderDark.brightnessComponent, 0.8, "Dark Mode toolbar border stays light-tinted")
  }
}
