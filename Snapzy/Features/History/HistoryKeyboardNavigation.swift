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

  static func inclusiveRangeIDs(
    orderedIDs: [UUID],
    anchorID: UUID?,
    previousFocusedID: UUID?,
    focusedID: UUID?,
    existingIDs: Set<UUID>
  ) -> (selection: Set<UUID>, anchor: UUID?) {
    guard let focusedID,
          let focusedIndex = orderedIDs.firstIndex(of: focusedID) else {
      return (existingIDs, anchorID)
    }

    let resolvedAnchor = anchorID ?? previousFocusedID ?? focusedID
    guard let anchorIndex = orderedIDs.firstIndex(of: resolvedAnchor) else {
      return (existingIDs.union([focusedID]), focusedID)
    }

    let lower = min(anchorIndex, focusedIndex)
    let upper = max(anchorIndex, focusedIndex)
    return (existingIDs.union(orderedIDs[lower...upper]), resolvedAnchor)
  }

  static func firstSelectedID(in orderedIDs: [UUID], selectedIDs: Set<UUID>) -> UUID? {
    orderedIDs.first(where: selectedIDs.contains)
  }
}
