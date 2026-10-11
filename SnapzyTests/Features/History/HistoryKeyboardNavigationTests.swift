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

  func testInitialFocusUsesFirstVisibleRecordAndPreservesValidFocus() {
    let ordered = (0..<4).map { _ in UUID() }

    XCTAssertEqual(
      HistoryFloatingNavigation.initialFocusedID(in: ordered, currentID: nil),
      ordered[0]
    )
    XCTAssertEqual(
      HistoryFloatingNavigation.initialFocusedID(in: ordered, currentID: UUID()),
      ordered[0]
    )
    XCTAssertEqual(
      HistoryFloatingNavigation.initialFocusedID(in: ordered, currentID: ordered[2]),
      ordered[2]
    )
    XCTAssertNil(HistoryFloatingNavigation.initialFocusedID(in: [], currentID: ordered[0]))
  }

  func testPlainGridFocusMovesInAllDirectionsWithoutChangingSelection() {
    let ordered = (0..<12).map { _ in UUID() }
    let selectedIDs: Set<UUID> = [ordered[0], ordered[5]]

    let expected: [(HistoryFloatingNavigationDirection, UUID)] = [
      (.left, ordered[4]),
      (.right, ordered[6]),
      (.up, ordered[1]),
      (.down, ordered[9])
    ]

    for (direction, expectedID) in expected {
      let transition = HistoryFloatingNavigation.expandedFocusTransition(
        from: ordered[5],
        direction: direction,
        orderedIDs: ordered,
        selectedIDs: selectedIDs,
        extendingSelection: false,
        anchorID: nil,
        baselineIDs: selectedIDs
      )
      XCTAssertEqual(transition.focusedID, expectedID)
      XCTAssertEqual(transition.selectedIDs, selectedIDs)
      XCTAssertEqual(transition.anchorID, nil)
      XCTAssertEqual(transition.baselineIDs, selectedIDs)
    }
  }

  func testPlainGridFocusMovesWithoutSelectionWhenSelectionIsEmpty() {
    let ordered = (0..<8).map { _ in UUID() }

    let transition = HistoryFloatingNavigation.expandedFocusTransition(
      from: ordered[1],
      direction: .right,
      orderedIDs: ordered,
      selectedIDs: [],
      extendingSelection: false,
      anchorID: nil,
      baselineIDs: []
    )

    XCTAssertEqual(transition.focusedID, ordered[2])
    XCTAssertTrue(transition.selectedIDs.isEmpty)
    XCTAssertNil(transition.anchorID)
    XCTAssertTrue(transition.baselineIDs.isEmpty)
  }

  func testPlainGridArrowMovesSingletonSelectionAndResetsRangeBaseline() {
    let ordered = (0..<8).map { _ in UUID() }

    let transition = HistoryFloatingNavigation.expandedFocusTransition(
      from: ordered[1],
      direction: .right,
      orderedIDs: ordered,
      selectedIDs: [ordered[1]],
      extendingSelection: false,
      anchorID: ordered[1],
      baselineIDs: [ordered[1]]
    )

    XCTAssertEqual(transition.focusedID, ordered[2])
    XCTAssertEqual(transition.selectedIDs, [ordered[2]])
    XCTAssertEqual(transition.anchorID, ordered[2])
    XCTAssertEqual(transition.baselineIDs, [ordered[2]])
  }

  func testPlainGridBoundaryPreservesSingletonSelectionState() {
    let ordered = (0..<4).map { _ in UUID() }

    let transition = HistoryFloatingNavigation.expandedFocusTransition(
      from: ordered[3],
      direction: .right,
      orderedIDs: ordered,
      selectedIDs: [ordered[3]],
      extendingSelection: false,
      anchorID: ordered[3],
      baselineIDs: [ordered[3]]
    )

    XCTAssertEqual(transition.focusedID, ordered[3])
    XCTAssertEqual(transition.selectedIDs, [ordered[3]])
    XCTAssertEqual(transition.anchorID, ordered[3])
    XCTAssertEqual(transition.baselineIDs, [ordered[3]])
  }

  func testPlainGridFocusPreservesSingletonSelectionWhenFocusDiffers() {
    let ordered = (0..<8).map { _ in UUID() }
    let selectedID = ordered[1]

    let transition = HistoryFloatingNavigation.expandedFocusTransition(
      from: ordered[2],
      direction: .right,
      orderedIDs: ordered,
      selectedIDs: [selectedID],
      extendingSelection: false,
      anchorID: selectedID,
      baselineIDs: [selectedID]
    )

    XCTAssertEqual(transition.focusedID, ordered[3])
    XCTAssertEqual(transition.selectedIDs, [selectedID])
    XCTAssertEqual(transition.anchorID, selectedID)
    XCTAssertEqual(transition.baselineIDs, [selectedID])
  }

  func testSingletonArrowThenShiftRangeExpandsAndContractsFromNewAnchor() {
    let ordered = (0..<8).map { _ in UUID() }
    let singleton = HistoryFloatingNavigation.expandedFocusTransition(
      from: ordered[1],
      direction: .right,
      orderedIDs: ordered,
      selectedIDs: [ordered[1]],
      extendingSelection: false,
      anchorID: ordered[1],
      baselineIDs: [ordered[1]]
    )

    XCTAssertEqual(singleton.focusedID, ordered[2])
    XCTAssertEqual(singleton.selectedIDs, [ordered[2]])
    XCTAssertEqual(singleton.anchorID, ordered[2])
    XCTAssertEqual(singleton.baselineIDs, [ordered[2]])

    let expanded = HistoryFloatingNavigation.expandedFocusTransition(
      from: singleton.focusedID,
      direction: .down,
      orderedIDs: ordered,
      selectedIDs: singleton.selectedIDs,
      extendingSelection: true,
      anchorID: singleton.anchorID,
      baselineIDs: singleton.baselineIDs
    )
    XCTAssertEqual(expanded.focusedID, ordered[6])
    XCTAssertEqual(expanded.selectedIDs, Set(ordered[2...6]))
    XCTAssertEqual(expanded.anchorID, ordered[2])
    XCTAssertEqual(expanded.baselineIDs, [ordered[2]])

    let contracted = HistoryFloatingNavigation.expandedFocusTransition(
      from: expanded.focusedID,
      direction: .up,
      orderedIDs: ordered,
      selectedIDs: expanded.selectedIDs,
      extendingSelection: true,
      anchorID: expanded.anchorID,
      baselineIDs: expanded.baselineIDs
    )
    XCTAssertEqual(contracted.focusedID, ordered[2])
    XCTAssertEqual(contracted.selectedIDs, [ordered[2]])
    XCTAssertEqual(contracted.baselineIDs, [ordered[2]])
  }

  func testShiftGridFocusTransitionExpandsAndContractsRange() {
    let ordered = (0..<8).map { _ in UUID() }
    let baseline: Set<UUID> = [ordered[2], ordered[6]]

    let expanded = HistoryFloatingNavigation.expandedFocusTransition(
      from: ordered[2],
      direction: .down,
      orderedIDs: ordered,
      selectedIDs: baseline,
      extendingSelection: true,
      anchorID: ordered[2],
      baselineIDs: baseline
    )
    XCTAssertEqual(expanded.focusedID, ordered[6])
    XCTAssertEqual(expanded.selectedIDs, baseline.union(ordered[2...6]))
    XCTAssertEqual(expanded.baselineIDs, baseline)

    let contracted = HistoryFloatingNavigation.expandedFocusTransition(
      from: expanded.focusedID,
      direction: .up,
      orderedIDs: ordered,
      selectedIDs: expanded.selectedIDs,
      extendingSelection: true,
      anchorID: expanded.anchorID,
      baselineIDs: expanded.baselineIDs
    )
    XCTAssertEqual(contracted.focusedID, ordered[2])
    XCTAssertEqual(contracted.selectedIDs, baseline)
    XCTAssertEqual(contracted.baselineIDs, baseline)
  }

  func testShiftRangeUsesCurrentFilteredOrder() {
    let filteredOrder = (0..<5).map { _ in UUID() }
    let baseline = Set([filteredOrder[0], UUID()])

    let result = HistoryFloatingNavigation.inclusiveRangeIDs(
      orderedIDs: filteredOrder,
      anchorID: filteredOrder[3],
      previousFocusedID: nil,
      focusedID: filteredOrder[1],
      baselineIDs: baseline
    )

    XCTAssertEqual(result.selection, baseline.union(filteredOrder[1...3]))
    XCTAssertEqual(result.anchor, filteredOrder[3])
  }

  func testShiftRangeContractsWhenFocusMovesBack() {
    let ordered = (0..<5).map { _ in UUID() }
    let baseline = Set([ordered[0], UUID()])

    let expanded = HistoryFloatingNavigation.inclusiveRangeIDs(
      orderedIDs: ordered,
      anchorID: ordered[1],
      previousFocusedID: nil,
      focusedID: ordered[4],
      baselineIDs: baseline
    )
    let contracted = HistoryFloatingNavigation.inclusiveRangeIDs(
      orderedIDs: ordered,
      anchorID: expanded.anchor,
      previousFocusedID: ordered[4],
      focusedID: ordered[2],
      baselineIDs: baseline
    )

    XCTAssertEqual(expanded.selection, baseline.union(ordered[1...4]))
    XCTAssertEqual(contracted.selection, baseline.union(ordered[1...2]))
    XCTAssertEqual(contracted.anchor, ordered[1])
  }

  func testShiftRangeRetainsCommandClickBaseline() {
    let ordered = (0..<5).map { _ in UUID() }
    let commandSelection = Set([ordered[0], ordered[4]])

    let expanded = HistoryFloatingNavigation.inclusiveRangeIDs(
      orderedIDs: ordered,
      anchorID: ordered[0],
      previousFocusedID: nil,
      focusedID: ordered[3],
      baselineIDs: commandSelection
    )
    let contracted = HistoryFloatingNavigation.inclusiveRangeIDs(
      orderedIDs: ordered,
      anchorID: expanded.anchor,
      previousFocusedID: ordered[3],
      focusedID: ordered[2],
      baselineIDs: commandSelection
    )

    XCTAssertEqual(expanded.selection, commandSelection.union(ordered[0...3]))
    XCTAssertEqual(contracted.selection, commandSelection.union(ordered[0...2]))
    XCTAssertTrue(contracted.selection.contains(ordered[4]))
    XCTAssertFalse(contracted.selection.contains(ordered[3]))
    XCTAssertEqual(contracted.anchor, ordered[0])
  }

  func testShiftRangeUsesPreviousFocusAsMissingAnchorAndPreservesBaseline() {
    let ordered = (0..<3).map { _ in UUID() }
    let baseline = Set([UUID()])

    let result = HistoryFloatingNavigation.inclusiveRangeIDs(
      orderedIDs: ordered,
      anchorID: nil,
      previousFocusedID: ordered[0],
      focusedID: ordered[2],
      baselineIDs: baseline
    )

    XCTAssertEqual(result.selection, baseline.union(ordered[0...2]))
    XCTAssertEqual(result.anchor, ordered[0])
  }

  func testShiftRangeFallsBackToValidPreviousFocusWhenAnchorIsMissing() {
    let ordered = (0..<3).map { _ in UUID() }
    let baseline = Set([UUID()])

    let result = HistoryFloatingNavigation.inclusiveRangeIDs(
      orderedIDs: ordered,
      anchorID: UUID(),
      previousFocusedID: ordered[0],
      focusedID: ordered[2],
      baselineIDs: baseline
    )

    XCTAssertEqual(result.selection, baseline.union(ordered[0...2]))
    XCTAssertEqual(result.anchor, ordered[0])
  }

  func testShiftRangeHandlesEmptyAndMissingInputs() {
    let ordered = (0..<2).map { _ in UUID() }
    let baseline = Set([UUID()])

    let empty = HistoryFloatingNavigation.inclusiveRangeIDs(
      orderedIDs: [],
      anchorID: ordered[0],
      previousFocusedID: nil,
      focusedID: ordered[1],
      baselineIDs: baseline
    )
    let missingFocus = HistoryFloatingNavigation.inclusiveRangeIDs(
      orderedIDs: ordered,
      anchorID: ordered[0],
      previousFocusedID: nil,
      focusedID: UUID(),
      baselineIDs: baseline
    )
    let missingAnchor = HistoryFloatingNavigation.inclusiveRangeIDs(
      orderedIDs: ordered,
      anchorID: UUID(),
      previousFocusedID: nil,
      focusedID: ordered[1],
      baselineIDs: baseline
    )

    XCTAssertEqual(empty.selection, baseline)
    XCTAssertEqual(empty.anchor, ordered[0])
    XCTAssertEqual(missingFocus.selection, baseline)
    XCTAssertEqual(missingFocus.anchor, ordered[0])
    XCTAssertEqual(missingAnchor.selection, baseline.union([ordered[1]]))
    XCTAssertEqual(missingAnchor.anchor, ordered[1])
  }

  func testPrunedSelectionPreservesVisibleIDsAndResetsRangeToDisplayOrderAnchor() {
    let hiddenAnchor = UUID()
    let ordered = (0..<4).map { _ in UUID() }
    let selectedIDs = Set([hiddenAnchor, ordered[2], ordered[0]])
    let baselineIDs = Set([hiddenAnchor, ordered[1], ordered[0]])

    let result = HistoryFloatingNavigation.prunedExpandedSelection(
      orderedIDs: [ordered[2], ordered[0], ordered[3]],
      selectedIDs: selectedIDs,
      baselineIDs: baselineIDs,
      anchorID: hiddenAnchor,
      focusedID: ordered[3]
    )

    XCTAssertEqual(result.selection, [ordered[2], ordered[0]])
    XCTAssertEqual(result.baseline, result.selection)
    XCTAssertEqual(result.anchor, ordered[2])
  }

  func testPrunedSelectionFallsBackToVisibleFocusWhenNoSelectionRemains() {
    let hiddenAnchor = UUID()
    let hiddenSelection = UUID()
    let focusedID = UUID()

    let result = HistoryFloatingNavigation.prunedExpandedSelection(
      orderedIDs: [focusedID],
      selectedIDs: [hiddenSelection],
      baselineIDs: [hiddenSelection],
      anchorID: hiddenAnchor,
      focusedID: focusedID
    )

    XCTAssertTrue(result.selection.isEmpty)
    XCTAssertTrue(result.baseline.isEmpty)
    XCTAssertEqual(result.anchor, focusedID)
  }

  func testFirstSelectedIDUsesCurrentFilteredOrder() {
    let selectedIDs = (0..<4).map { _ in UUID() }
    let filteredOrder = [selectedIDs[3], selectedIDs[2], selectedIDs[1]]

    XCTAssertEqual(
      HistoryFloatingNavigation.firstSelectedID(
        in: filteredOrder,
        selectedIDs: [selectedIDs[1], selectedIDs[3]]
      ),
      selectedIDs[3]
    )
    XCTAssertNil(HistoryFloatingNavigation.firstSelectedID(in: filteredOrder, selectedIDs: []))
  }
}
