import XCTest
@testable import Snapzy

final class HistoryKeyboardNavigationTests: XCTestCase {
  func testDirectionMapsArrowKeyCodes() {
    XCTAssertEqual(HistoryFloatingNavigationDirection(keyCode: 123), .left)
    XCTAssertEqual(HistoryFloatingNavigationDirection(keyCode: 124), .right)
    XCTAssertEqual(HistoryFloatingNavigationDirection(keyCode: 126), .up)
    XCTAssertEqual(HistoryFloatingNavigationDirection(keyCode: 125), .down)
    XCTAssertNil(HistoryFloatingNavigationDirection(keyCode: 0))
  }

  func testCompactNavigationMovesHorizontallyWithoutWrapping() {
    XCTAssertEqual(HistoryFloatingNavigation.compactTargetIndex(from: 0, direction: .left, count: 3), 0)
    XCTAssertEqual(HistoryFloatingNavigation.compactTargetIndex(from: 0, direction: .right, count: 3), 1)
    XCTAssertEqual(HistoryFloatingNavigation.compactTargetIndex(from: 2, direction: .right, count: 3), 2)
    XCTAssertNil(HistoryFloatingNavigation.compactTargetIndex(from: 1, direction: .up, count: 3))
    XCTAssertNil(HistoryFloatingNavigation.compactTargetIndex(from: 1, direction: .down, count: 3))
  }

  func testGridNavigationStaysWithinRowsAndColumns() {
    XCTAssertEqual(HistoryFloatingNavigation.expandedTargetIndex(from: 4, direction: .left, count: 8), 4)
    XCTAssertEqual(HistoryFloatingNavigation.expandedTargetIndex(from: 6, direction: .right, count: 8), 7)
    XCTAssertEqual(HistoryFloatingNavigation.expandedTargetIndex(from: 7, direction: .right, count: 8), 7)
    XCTAssertEqual(HistoryFloatingNavigation.expandedTargetIndex(from: 2, direction: .up, count: 8), 2)
    XCTAssertEqual(HistoryFloatingNavigation.expandedTargetIndex(from: 6, direction: .up, count: 8), 2)
    XCTAssertEqual(HistoryFloatingNavigation.expandedTargetIndex(from: 2, direction: .down, count: 8), 6)
    XCTAssertEqual(HistoryFloatingNavigation.expandedTargetIndex(from: 6, direction: .down, count: 8), 6)
    XCTAssertEqual(HistoryFloatingNavigation.expandedTargetIndex(from: 0, direction: .down, count: 3), 0)
  }

  func testGridDownClampsToLastCardInIncompleteFinalRow() {
    XCTAssertEqual(HistoryFloatingNavigation.expandedTargetIndex(from: 4, direction: .down, count: 10), 8)
    XCTAssertEqual(HistoryFloatingNavigation.expandedTargetIndex(from: 5, direction: .down, count: 10), 9)
    XCTAssertEqual(HistoryFloatingNavigation.expandedTargetIndex(from: 6, direction: .down, count: 10), 9)
    XCTAssertEqual(HistoryFloatingNavigation.expandedTargetIndex(from: 9, direction: .down, count: 10), 9)
  }

  func testNavigationHandlesEmptyAndInvalidInputs() {
    XCTAssertNil(HistoryFloatingNavigation.compactTargetIndex(from: 0, direction: .right, count: 0))
    XCTAssertNil(HistoryFloatingNavigation.expandedTargetIndex(from: 0, direction: .down, count: 0))
    XCTAssertNil(HistoryFloatingNavigation.expandedTargetIndex(from: 5, direction: .left, count: 5))
  }

  func testShiftRangeUnionsExistingIDsInFilteredOrder() {
    let filteredOrder = (0..<5).map { _ in UUID() }
    let existing = Set([filteredOrder[0], UUID()])

    let result = HistoryFloatingNavigation.inclusiveRangeIDs(
      orderedIDs: filteredOrder,
      anchorID: filteredOrder[3],
      previousFocusedID: nil,
      focusedID: filteredOrder[1],
      existingIDs: existing
    )

    XCTAssertEqual(result.selection, existing.union(filteredOrder[1...3]))
    XCTAssertEqual(result.anchor, filteredOrder[3])
  }

  func testShiftRangeUsesPreviousFocusAsMissingAnchorAndPreservesExistingIDs() {
    let ordered = (0..<3).map { _ in UUID() }
    let existing = Set([UUID()])

    let result = HistoryFloatingNavigation.inclusiveRangeIDs(
      orderedIDs: ordered,
      anchorID: nil,
      previousFocusedID: ordered[0],
      focusedID: ordered[2],
      existingIDs: existing
    )

    XCTAssertEqual(result.selection, existing.union(ordered[0...2]))
    XCTAssertEqual(result.anchor, ordered[0])
  }
}
