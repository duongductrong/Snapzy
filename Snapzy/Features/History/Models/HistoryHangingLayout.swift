import AppKit

nonisolated enum HistoryHangingLayout {
  static let maximumWidth: CGFloat = 1120
  static let height: CGFloat = 344
  static let edgeDepth: CGFloat = 3
  static let revealDelay: TimeInterval = 0.18
  static let dismissDelay: TimeInterval = 0.65
  static let toolbarHeight: CGFloat = 44
  static let galleryTop: CGFloat = 56
  static let clipTop: CGFloat = 8

  static func frame(screenFrame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat) -> CGRect {
    let top = min(visibleFrame.maxY, screenFrame.maxY - safeAreaTop)
    let height = max(1, min(Self.height, top - visibleFrame.minY - 16))
    let width = max(1, min(height < 260 ? 680 : maximumWidth, visibleFrame.width - 32))
    return CGRect(
      x: visibleFrame.midX - width / 2,
      y: top - height - 8,
      width: width,
      height: height
    )
  }

  static func thumbnailHeight(galleryHeight: CGFloat, anchorDepth: CGFloat = 0, compact: Bool = false) -> CGFloat {
    if compact {
      return max(16, min(90, galleryHeight - anchorDepth - 54))
    }
    return max(32, min(126, galleryHeight - anchorDepth - 108))
  }

  static func visibleRecords(_ records: [CaptureHistoryRecord], filter: CaptureHistoryType?,
                             maximum: Int, width: CGFloat) -> [CaptureHistoryRecord] {
    let capacity = HistoryHangingRowLayout(width: width).capacity
    return Array(records.lazy.filter { !$0.isDeleted && (filter == nil || $0.captureType == filter) }
      .prefix(min(capacity, max(1, maximum))))
  }

  static func edgeScreenIndex(at point: CGPoint, frames: [CGRect]) -> Int? {
    if let index = frames.firstIndex(where: { $0.contains(point) }) {
      return isAtTopEdge(point, screenFrame: frames[index]) ? index : nil
    }
    return frames.firstIndex(where: { isAtTopEdge(point, screenFrame: $0) })
  }

  static func isAtTopEdge(_ point: CGPoint, screenFrame: CGRect) -> Bool {
    point.x >= screenFrame.minX && point.x < screenFrame.maxX
      && point.y >= screenFrame.maxY - edgeDepth && point.y <= screenFrame.maxY
  }

  static func containsPointer(_ point: CGPoint, panelFrame: CGRect, screenFrame: CGRect) -> Bool {
    let corridor = CGRect(
      x: screenFrame.minX,
      y: panelFrame.maxY,
      width: screenFrame.width,
      height: max(0, screenFrame.maxY - panelFrame.maxY)
    )
    return panelFrame.insetBy(dx: -16, dy: -16).contains(point) || corridor.contains(point)
      || isAtTopEdge(point, screenFrame: screenFrame)
  }
}

nonisolated struct HistoryHangingRowLayout {
  let width: CGFloat
  let cardWidth: CGFloat
  let capacity: Int
  let spacing: CGFloat = 24

  init(width: CGFloat) {
    self.width = width
    cardWidth = min(184, max(1, width - 48))
    capacity = max(1, Int((max(1, width - 48) + spacing) / (cardWidth + spacing)))
  }

  func center(at index: Int, count: Int) -> CGFloat {
    let rowWidth = CGFloat(count) * cardWidth + CGFloat(max(0, count - 1)) * spacing
    return (width - rowWidth) / 2 + cardWidth / 2 + CGFloat(index) * (cardWidth + spacing)
  }
}

nonisolated struct HistoryHangingCableLayout {
  let frame: CGRect
  let panelFrame: CGRect
  let depth: CGFloat

  var maximumAttachmentHeight: CGFloat {
    depth - (frame.maxY - panelFrame.maxY)
  }

  init(panelFrame: CGRect, screenFrame: CGRect) {
    self.panelFrame = panelFrame
    let row = HistoryHangingRowLayout(width: panelFrame.width)
    let first = panelFrame.minX - screenFrame.minX + row.center(at: 0, count: row.capacity)
    let last = panelFrame.minX - screenFrame.minX + row.center(at: row.capacity - 1, count: row.capacity)
    let t = min(first, screenFrame.width - last) / screenFrame.width
    let topGap = screenFrame.maxY - panelFrame.maxY
    let restingDepth = panelFrame.height < 260 ? 12 : HistoryHangingLayout.galleryTop
    depth = ceil(max(topGap + restingDepth, (topGap + 12) / (4 * t * (1 - t))))
    frame = CGRect(x: screenFrame.minX, y: screenFrame.maxY - depth - 8,
                   width: screenFrame.width, height: depth + 8)
  }

  func attachmentHeight(at panelX: CGFloat) -> CGFloat {
    let t = (panelFrame.minX - frame.minX + panelX) / frame.width
    return 4 * depth * t * (1 - t) - (frame.maxY - panelFrame.maxY)
  }
}

nonisolated struct HistoryEdgeHoverState {
  enum Action: Equatable {
    case none, reveal, dismiss
  }

  private var edgeEnteredAt: TimeInterval?
  private var outsideSince: TimeInterval?
  private var requiresEdgeExit = false

  mutating func suspend(atEdge: Bool) {
    edgeEnteredAt = nil
    outsideSince = nil
    if !atEdge {
      requiresEdgeExit = false
    }
  }

  mutating func dismiss() {
    edgeEnteredAt = nil
    outsideSince = nil
    requiresEdgeExit = true
  }

  mutating func update(
    atEdge: Bool,
    insideShelf: Bool,
    visible: Bool,
    keepOpen: Bool,
    suppressed: Bool,
    now: TimeInterval
  ) -> Action {
    if !atEdge {
      requiresEdgeExit = false
    }
    if suppressed {
      edgeEnteredAt = nil
      outsideSince = nil
      requiresEdgeExit = atEdge
      return visible ? .dismiss : .none
    }
    if visible {
      edgeEnteredAt = nil
      if insideShelf || keepOpen {
        outsideSince = nil
      } else if let outsideSince {
        if now - outsideSince >= HistoryHangingLayout.dismissDelay {
          dismiss()
          return .dismiss
        }
      } else {
        outsideSince = now
      }
      return .none
    }
    outsideSince = nil
    guard atEdge, !requiresEdgeExit else {
      edgeEnteredAt = nil
      return .none
    }
    if let edgeEnteredAt {
      if now - edgeEnteredAt >= HistoryHangingLayout.revealDelay {
        self.edgeEnteredAt = nil
        return .reveal
      }
    } else {
      edgeEnteredAt = now
    }
    return .none
  }
}
