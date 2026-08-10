//
//  ScreenshotLastAreaStoreTests.swift
//  SnapzyTests
//
//  Unit tests for repeat-area screenshot rect persistence.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class ScreenshotLastAreaStoreTests: XCTestCase {

  override func setUp() {
    super.setUp()
    UserDefaults.standard.removeObject(forKey: PreferencesKeys.screenshotLastAreaRect)
  }

  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: PreferencesKeys.screenshotLastAreaRect)
    super.tearDown()
  }

  func testLoadReturnsNilWhenNothingStored() {
    XCTAssertNil(ScreenshotLastAreaStore.load())
  }

  func testSaveThenLoadRoundTripsRect() {
    let screenFrame = NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    let rect = screenFrame.insetBy(dx: 100, dy: 100)

    ScreenshotLastAreaStore.save(rect)

    XCTAssertEqual(ScreenshotLastAreaStore.load(), rect)
  }

  func testLoadReturnsNilForCorruptedPayload() {
    UserDefaults.standard.set(["x": "not-a-number"], forKey: PreferencesKeys.screenshotLastAreaRect)

    XCTAssertNil(ScreenshotLastAreaStore.load())
  }

  func testLoadReturnsNilWhenRectIsOffAllScreens() {
    let offscreen = CGRect(x: -1_000_000, y: -1_000_000, width: 200, height: 200)
    ScreenshotLastAreaStore.save(offscreen)

    XCTAssertNil(ScreenshotLastAreaStore.load())
  }
}
