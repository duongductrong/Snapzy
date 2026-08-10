//
//  WindowShadowPreferenceTests.swift
//  SnapzyTests
//

import XCTest
@testable import Snapzy

final class WindowShadowPreferenceTests: XCTestCase {
  func testIgnoreShadowsSingleWindow_invertsIncludeShadowFlag() {
    // shadow included  -> SC must NOT ignore shadows
    XCTAssertEqual(WindowShadowPreference.ignoreShadowsSingleWindow(includeShadow: true), false)
    // shadow excluded  -> SC must ignore shadows
    XCTAssertEqual(WindowShadowPreference.ignoreShadowsSingleWindow(includeShadow: false), true)
  }

  func testDefaultIncludeShadow_preservesLegacyShadowOnBehavior() {
    // Default must keep shadow ON so existing users see no behavior change.
    XCTAssertEqual(WindowShadowPreference.defaultIncludeShadow, true)
  }
}
