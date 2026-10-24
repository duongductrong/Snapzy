//
//  WindowListDisplaySnapshotTests.swift
//  SnapzyTests
//
//  Unit tests for choosing which on-screen windows a chrome-free snapshot composites.
//

import XCTest
@testable import Snapzy

final class WindowListDisplaySnapshotTests: XCTestCase {

  func testCompositedWindowIDs_dropsExcludedAndKeepsOrder() {
    let result = WindowListDisplaySnapshot.compositedWindowIDs(
      onScreenWindowIDs: [40, 12, 7, 99],
      excluding: [12, 99]
    )

    XCTAssertEqual(result, [40, 7])
  }

  func testCompositedWindowIDs_returnsNilWhenNoExcludedWindowIsOnScreen() {
    XCTAssertNil(
      WindowListDisplaySnapshot.compositedWindowIDs(onScreenWindowIDs: [1, 2, 3], excluding: [42])
    )
  }

  func testCompositedWindowIDs_returnsNilForEmptyExclusion() {
    XCTAssertNil(
      WindowListDisplaySnapshot.compositedWindowIDs(onScreenWindowIDs: [1, 2, 3], excluding: [])
    )
  }
}
