//
//  CaptureHistoryPreferencesTests.swift
//  SnapzyTests
//
//  Verify the shared Capture History enabled reader applies the intended
//  default (`true`) consistently, unlike `bool(forKey:)` which defaults to
//  `false` for a never-written key.
//

@testable import Snapzy
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
}
