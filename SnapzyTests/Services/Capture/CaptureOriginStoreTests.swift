//
//  CaptureOriginStoreTests.swift
//  SnapzyTests
//
//  Unit tests for the short-lived capture-region memory behind pin entrances.
//

import CoreGraphics
import Foundation
import XCTest
@testable import Snapzy

@MainActor
final class CaptureOriginStoreTests: XCTestCase {
  private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
  private let firstURL = URL(fileURLWithPath: "/tmp/snapzy-tests/first.png")
  private let secondURL = URL(fileURLWithPath: "/tmp/snapzy-tests/second.png")

  override func setUp() {
    super.setUp()
    CaptureOriginStore.shared.removeAll()
  }

  override func tearDown() {
    CaptureOriginStore.shared.removeAll()
    super.tearDown()
  }

  func testRecordThenLookupReturnsScreenRect() {
    let rect = CGRect(x: 120, y: 340, width: 800, height: 600)
    CaptureOriginStore.shared.record(url: firstURL, screenRect: rect, at: referenceDate)

    XCTAssertEqual(CaptureOriginStore.shared.origin(for: firstURL, at: referenceDate), rect)
  }

  func testUnknownURLHasNoOrigin() {
    let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
    CaptureOriginStore.shared.record(url: firstURL, screenRect: rect, at: referenceDate)

    XCTAssertNil(CaptureOriginStore.shared.origin(for: secondURL, at: referenceDate))
  }

  func testOriginExpiresAfterLifetime() {
    let rect = CGRect(x: 5, y: 5, width: 100, height: 100)
    CaptureOriginStore.shared.record(url: firstURL, screenRect: rect, at: referenceDate)

    let justInside = referenceDate.addingTimeInterval(CaptureOriginStore.lifetime)
    let justPast = referenceDate.addingTimeInterval(CaptureOriginStore.lifetime + 1)

    XCTAssertNotNil(CaptureOriginStore.shared.origin(for: firstURL, at: justInside))
    XCTAssertNil(CaptureOriginStore.shared.origin(for: firstURL, at: justPast))
  }

  func testExpiredOriginIsForgottenRatherThanRevived() {
    let rect = CGRect(x: 5, y: 5, width: 100, height: 100)
    CaptureOriginStore.shared.record(url: firstURL, screenRect: rect, at: referenceDate)
    let late = referenceDate.addingTimeInterval(CaptureOriginStore.lifetime * 2)
    XCTAssertNil(CaptureOriginStore.shared.origin(for: firstURL, at: late))

    // A fresh capture of the same path must win, not the aged-out entry.
    let replacement = CGRect(x: 900, y: 900, width: 50, height: 50)
    CaptureOriginStore.shared.record(url: firstURL, screenRect: replacement, at: late)
    XCTAssertEqual(CaptureOriginStore.shared.origin(for: firstURL, at: late), replacement)
  }

  func testRectsWithoutAreaAreNotRemembered() {
    CaptureOriginStore.shared.record(url: firstURL, screenRect: .zero, at: referenceDate)
    let hairline = CGRect(x: 10, y: 10, width: 120, height: 0)
    CaptureOriginStore.shared.record(url: secondURL, screenRect: hairline, at: referenceDate)

    XCTAssertNil(CaptureOriginStore.shared.origin(for: firstURL, at: referenceDate))
    XCTAssertNil(CaptureOriginStore.shared.origin(for: secondURL, at: referenceDate))
  }

  func testReRecordingSameURLReplacesItsOrigin() {
    let first = CGRect(x: 0, y: 0, width: 100, height: 100)
    let second = CGRect(x: 40, y: 40, width: 120, height: 80)
    CaptureOriginStore.shared.record(url: firstURL, screenRect: first, at: referenceDate)
    let later = referenceDate.addingTimeInterval(1)
    CaptureOriginStore.shared.record(url: firstURL, screenRect: second, at: later)

    XCTAssertEqual(CaptureOriginStore.shared.origin(for: firstURL, at: later), second)
  }

  func testCapacityEvictsTheOldestOrigin() {
    func url(for index: Int) -> URL {
      URL(fileURLWithPath: "/tmp/snapzy-tests/capture-\(index).png")
    }

    func rect(for index: Int) -> CGRect {
      CGRect(x: index, y: index, width: 10, height: 10)
    }

    let count = CaptureOriginStore.capacity + 1
    for index in 0 ..< count {
      CaptureOriginStore.shared.record(url: url(for: index), screenRect: rect(for: index), at: referenceDate)
    }

    XCTAssertNil(CaptureOriginStore.shared.origin(for: url(for: 0), at: referenceDate))
    XCTAssertEqual(
      CaptureOriginStore.shared.origin(for: url(for: count - 1), at: referenceDate),
      rect(for: count - 1)
    )
  }
}
