import AppKit

enum HistoryFloatingNavigationDirection: CaseIterable, Equatable {
  case left
  case right
  case up
  case down

  init?(keyCode: UInt16) {
    switch keyCode {
    case 123: self = .left
    case 124: self = .right
    case 126: self = .up
    case 125: self = .down
    default: return nil
    }
  }
}

enum HistoryFloatingNavigation {
  static let expandedColumnCount = 4

  static func initialFocusedID(in orderedIDs: [UUID], currentID: UUID?) -> UUID? {
    guard !orderedIDs.isEmpty else { return nil }
    guard let currentID, orderedIDs.contains(currentID) else {
      return orderedIDs.first
    }
    return currentID
  }

  static func compactTargetIndex(
    from index: Int,
    direction: HistoryFloatingNavigationDirection,
    count: Int
  ) -> Int? {
    guard count > 0, (0..<count).contains(index) else { return nil }
    switch direction {
    case .left: return max(0, index - 1)
    case .right: return min(count - 1, index + 1)
    case .up, .down: return nil
    }
  }

  static func expandedTargetIndex(
    from index: Int,
    direction: HistoryFloatingNavigationDirection,
    count: Int
  ) -> Int? {
    guard count > 0, (0..<count).contains(index) else { return nil }

    let column = index % expandedColumnCount
    switch direction {
    case .left:
      return column == 0 ? index : index - 1
    case .right:
      return column == expandedColumnCount - 1 || index + 1 >= count ? index : index + 1
    case .up:
      return index < expandedColumnCount ? index : index - expandedColumnCount
    case .down:
      let destination = index + expandedColumnCount
      guard destination < count else {
        let finalRowStart = (count - 1) / expandedColumnCount * expandedColumnCount
        return index < finalRowStart ? count - 1 : index
      }
      return destination
    }
  }

  static func expandedFocusID(
    from focusedID: UUID?,
    direction: HistoryFloatingNavigationDirection,
    orderedIDs: [UUID]
  ) -> UUID? {
    guard let focusedID,
          let currentIndex = orderedIDs.firstIndex(of: focusedID),
          let targetIndex = expandedTargetIndex(
            from: currentIndex,
            direction: direction,
            count: orderedIDs.count
          ) else {
      return focusedID
    }
    return orderedIDs[targetIndex]
  }

  static func expandedFocusTransition(
    from focusedID: UUID?,
    direction: HistoryFloatingNavigationDirection,
    orderedIDs: [UUID],
    selectedIDs: Set<UUID>,
    extendingSelection: Bool,
    anchorID: UUID?,
    baselineIDs: Set<UUID>
  ) -> (focusedID: UUID?, selectedIDs: Set<UUID>, anchorID: UUID?, baselineIDs: Set<UUID>) {
    let nextFocusedID = expandedFocusID(
      from: focusedID,
      direction: direction,
      orderedIDs: orderedIDs
    )

    guard extendingSelection,
          let nextFocusedID,
          nextFocusedID != focusedID else {
      guard let nextFocusedID,
            nextFocusedID != focusedID,
            selectedIDs.count == 1,
            let focusedID,
            selectedIDs.contains(focusedID) else {
        return (nextFocusedID, selectedIDs, anchorID, baselineIDs)
      }

      return (nextFocusedID, [nextFocusedID], nextFocusedID, [nextFocusedID])
    }

    let rangeSelection = inclusiveRangeIDs(
      orderedIDs: orderedIDs,
      anchorID: anchorID,
      previousFocusedID: focusedID,
      focusedID: nextFocusedID,
      baselineIDs: baselineIDs
    )
    return (nextFocusedID, rangeSelection.selection, rangeSelection.anchor, baselineIDs)
  }

  static func inclusiveRangeIDs(
    orderedIDs: [UUID],
    anchorID: UUID?,
    previousFocusedID: UUID?,
    focusedID: UUID?,
    baselineIDs: Set<UUID>
  ) -> (selection: Set<UUID>, anchor: UUID?) {
    guard let focusedID,
          let focusedIndex = orderedIDs.firstIndex(of: focusedID) else {
      return (baselineIDs, anchorID)
    }

    let resolvedAnchor: UUID
    if let anchorID, orderedIDs.contains(anchorID) {
      resolvedAnchor = anchorID
    } else if let previousFocusedID, orderedIDs.contains(previousFocusedID) {
      resolvedAnchor = previousFocusedID
    } else {
      resolvedAnchor = focusedID
    }
    guard let anchorIndex = orderedIDs.firstIndex(of: resolvedAnchor) else {
      return (baselineIDs.union([focusedID]), focusedID)
    }

    let lower = min(anchorIndex, focusedIndex)
    let upper = max(anchorIndex, focusedIndex)
    return (baselineIDs.union(orderedIDs[lower...upper]), resolvedAnchor)
  }

  static func firstSelectedID(in orderedIDs: [UUID], selectedIDs: Set<UUID>) -> UUID? {
    orderedIDs.first(where: selectedIDs.contains)
  }

  static func prunedExpandedSelection(
    orderedIDs: [UUID],
    selectedIDs: Set<UUID>,
    baselineIDs: Set<UUID>,
    anchorID: UUID?,
    focusedID: UUID?
  ) -> (selection: Set<UUID>, baseline: Set<UUID>, anchor: UUID?) {
    let visibleIDs = Set(orderedIDs)
    let visibleSelection = selectedIDs.intersection(visibleIDs)
    let visibleBaseline = baselineIDs.intersection(visibleIDs)

    guard let anchorID, !visibleIDs.contains(anchorID) else {
      return (visibleSelection, visibleBaseline, anchorID)
    }

    let fallbackAnchor = firstSelectedID(in: orderedIDs, selectedIDs: visibleSelection)
      ?? (focusedID.flatMap { visibleIDs.contains($0) ? $0 : nil })
    return (visibleSelection, visibleSelection, fallbackAnchor)
  }
}
