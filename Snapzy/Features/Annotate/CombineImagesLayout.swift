import CoreGraphics
import Foundation

enum CombineImagesMode: String, CaseIterable {
  case autoStitch
  case freeCanvas
}

enum CombineImagesDirection: String, CaseIterable {
  case smart
  case horizontal
  case vertical
}

struct CombineImagesLayoutItem: Equatable {
  let id: UUID
  let size: CGSize
}

struct CombineImagesLayoutResult: Equatable {
  let direction: CombineImagesDirection
  let boundsByID: [UUID: CGRect]
  let contentBounds: CGRect
}

/// Side of a stitched image that another image attaches to (visual orientation:
/// `top` is the edge nearer the top of the screen).
enum CombineStitchEdge: String, CaseIterable, Equatable {
  case top
  case bottom
  case left
  case right

  var isHorizontal: Bool { self == .left || self == .right }
}

/// Stitched layers arranged as justified rows, top to bottom; each row lists ids left
/// to right. A single row is a horizontal strip, one id per row is a vertical strip.
struct CombineStitchGrid: Equatable {
  private(set) var rows: [[UUID]]

  init(rows: [[UUID]]) {
    var seen = Set<UUID>()
    self.rows = rows
      .map { row in row.filter { seen.insert($0).inserted } }
      .filter { !$0.isEmpty }
  }

  static func strip(_ ids: [UUID], direction: CombineImagesDirection) -> CombineStitchGrid {
    switch direction {
    case .vertical:
      return CombineStitchGrid(rows: ids.map { [$0] })
    case .horizontal, .smart:
      return CombineStitchGrid(rows: [ids])
    }
  }

  var orderedIDs: [UUID] { rows.flatMap { $0 } }

  var isEmpty: Bool { rows.isEmpty }

  func contains(_ id: UUID) -> Bool {
    rows.contains { $0.contains(id) }
  }

  func position(of id: UUID) -> (row: Int, column: Int)? {
    for (rowIndex, row) in rows.enumerated() {
      if let column = row.firstIndex(of: id) {
        return (rowIndex, column)
      }
    }
    return nil
  }

  /// The strip this grid is equivalent to, or nil for a true multi-row, multi-column grid.
  var stripDirection: CombineImagesDirection? {
    if rows.count <= 1 { return .horizontal }
    if rows.allSatisfy({ $0.count == 1 }) { return .vertical }
    return nil
  }

  mutating func remove(_ id: UUID) {
    rows = rows.map { $0.filter { $0 != id } }.filter { !$0.isEmpty }
  }

  /// Place `id` against `edge` of `anchor`. Left/right join the anchor's row; top/bottom
  /// open a new row above/below it. Returns false when the anchor is not in the grid.
  @discardableResult
  mutating func insert(_ id: UUID, edge: CombineStitchEdge, of anchor: UUID) -> Bool {
    guard id != anchor, contains(anchor) else { return false }
    remove(id)
    guard let position = position(of: anchor) else { return false }
    switch edge {
    case .left:
      rows[position.row].insert(id, at: position.column)
    case .right:
      rows[position.row].insert(id, at: position.column + 1)
    case .top:
      rows.insert([id], at: position.row)
    case .bottom:
      rows.insert([id], at: position.row + 1)
    }
    return true
  }

  /// Add an id that arrived without a drop position: extend a single row, otherwise
  /// start a new row at the bottom.
  mutating func append(_ id: UUID) {
    guard !contains(id) else { return }
    if rows.count == 1 {
      rows[0].append(id)
    } else {
      rows.append([id])
    }
  }

  /// Keep only `ids`, preserving existing placement, and append ids the grid lacks.
  mutating func reconcile(with ids: [UUID]) {
    let valid = Set(ids)
    rows = rows.map { $0.filter { valid.contains($0) } }.filter { !$0.isEmpty }
    for id in ids where !contains(id) {
      append(id)
    }
  }
}

enum CombineImagesLayout {
  static func resolveDirection(
    requested: CombineImagesDirection,
    items: [CombineImagesLayoutItem],
    gap: CGFloat = 0
  ) -> CombineImagesDirection {
    guard requested == .smart else { return requested }
    guard let first = items.first, first.size.width > 0, first.size.height > 0 else {
      return .horizontal
    }

    let horizontalWidth = items.reduce(CGFloat.zero) { total, item in
      total + scaledSize(item.size, matchingHeight: first.size.height).width
    } + gap * CGFloat(max(items.count - 1, 0))
    let horizontalAspect = horizontalWidth / first.size.height

    let verticalHeight = items.reduce(CGFloat.zero) { total, item in
      total + scaledSize(item.size, matchingWidth: first.size.width).height
    } + gap * CGFloat(max(items.count - 1, 0))
    let verticalAspect = first.size.width / verticalHeight

    // Prefer the arrangement closest to a useful landscape canvas while avoiding
    // extremely long strips in either direction.
    let preferredAspect: CGFloat = 1.35
    let horizontalDistance = abs(log(max(horizontalAspect, 0.0001) / preferredAspect))
    let verticalDistance = abs(log(max(verticalAspect, 0.0001) / preferredAspect))
    return horizontalDistance <= verticalDistance ? .horizontal : .vertical
  }

  /// Strip layout. The first item keeps its native rect at the origin; later items run
  /// to the right (horizontal) or downward on screen (vertical).
  static func layout(
    items: [CombineImagesLayoutItem],
    direction requestedDirection: CombineImagesDirection,
    gap: CGFloat
  ) -> CombineImagesLayoutResult {
    guard let first = items.first, first.size.width > 0, first.size.height > 0 else {
      return CombineImagesLayoutResult(
        direction: requestedDirection == .vertical ? .vertical : .horizontal,
        boundsByID: [:],
        contentBounds: .zero
      )
    }

    let direction = resolveDirection(requested: requestedDirection, items: items, gap: gap)
    let grid = CombineStitchGrid.strip(items.map(\.id), direction: direction)
    let sizes = Dictionary(items.map { ($0.id, $0.size) }, uniquingKeysWith: { lhs, _ in lhs })
    let result = layout(grid: grid, sizes: sizes, anchorID: first.id, gap: gap)
    return CombineImagesLayoutResult(
      direction: direction,
      boundsByID: result.boundsByID,
      contentBounds: result.contentBounds
    )
  }

  /// Justified-rows layout in canvas coordinates (y up). Every row spans the same width
  /// and the images inside a row share one height. The whole arrangement is placed so
  /// `anchorID` keeps its native size at the origin, which keeps the base image fixed.
  static func layout(
    grid: CombineStitchGrid,
    sizes: [UUID: CGSize],
    anchorID: UUID,
    gap: CGFloat
  ) -> CombineImagesLayoutResult {
    func isUsable(_ id: UUID) -> Bool {
      guard let size = sizes[id] else { return false }
      return size.width > 0 && size.height > 0
    }
    func aspect(_ id: UUID) -> CGFloat {
      guard let size = sizes[id], size.height > 0 else { return 0 }
      return size.width / size.height
    }

    let rows = grid.rows.map { $0.filter(isUsable) }.filter { !$0.isEmpty }
    let fallbackDirection = grid.stripDirection ?? .horizontal
    guard !rows.isEmpty else {
      return CombineImagesLayoutResult(direction: fallbackDirection, boundsByID: [:], contentBounds: .zero)
    }

    let safeGap = max(0, gap)
    let referenceID = isUsable(anchorID) && rows.contains(where: { $0.contains(anchorID) })
      ? anchorID
      : rows[0][0]
    let referenceRow = rows.first { $0.contains(referenceID) } ?? rows[0]
    let referenceHeight = sizes[referenceID]?.height ?? 1
    let referenceRowAspect = referenceRow.reduce(CGFloat.zero) { $0 + aspect($1) }
    let contentWidth = referenceHeight * referenceRowAspect
      + safeGap * CGFloat(max(referenceRow.count - 1, 0))

    // Lay rows out top-down first (visual order), then flip into y-up canvas space.
    var visualRects: [UUID: CGRect] = [:]
    var cursorY: CGFloat = 0
    for row in rows {
      let rowAspect = row.reduce(CGFloat.zero) { $0 + aspect($1) }
      let available = max(contentWidth - safeGap * CGFloat(max(row.count - 1, 0)), 1)
      let rowHeight = row == referenceRow ? referenceHeight : available / max(rowAspect, 0.0001)
      var cursorX: CGFloat = 0
      for id in row {
        let width = rowHeight * aspect(id)
        visualRects[id] = CGRect(x: cursorX, y: cursorY, width: width, height: rowHeight)
        cursorX += width + safeGap
      }
      cursorY += rowHeight + safeGap
    }
    let totalHeight = max(cursorY - safeGap, 0)

    let referenceVisual = visualRects[referenceID] ?? .zero
    let offsetX = -referenceVisual.minX
    let offsetY = -(totalHeight - referenceVisual.maxY)
    var boundsByID: [UUID: CGRect] = [:]
    for (id, rect) in visualRects {
      boundsByID[id] = CGRect(
        x: rect.minX + offsetX,
        y: totalHeight - rect.maxY + offsetY,
        width: rect.width,
        height: rect.height
      )
    }
    // Pin the reference exactly so the base layer never drifts by rounding error.
    if let size = sizes[referenceID] {
      boundsByID[referenceID] = CGRect(origin: .zero, size: size)
    }

    let allBounds = Array(boundsByID.values)
    let contentBounds = allBounds.dropFirst().reduce(allBounds.first ?? .zero) { $0.union($1) }
    return CombineImagesLayoutResult(
      direction: fallbackDirection,
      boundsByID: boundsByID,
      contentBounds: contentBounds
    )
  }

  private static func scaledSize(_ size: CGSize, matchingHeight height: CGFloat) -> CGSize {
    guard size.height > 0 else { return .zero }
    let scale = height / size.height
    return CGSize(width: size.width * scale, height: height)
  }

  private static func scaledSize(_ size: CGSize, matchingWidth width: CGFloat) -> CGSize {
    guard size.width > 0 else { return .zero }
    let scale = width / size.width
    return CGSize(width: width, height: size.height * scale)
  }
}

/// Where an image dropped (or dragged) onto a stitched canvas should go.
enum CombineDropTarget: Equatable {
  /// Attach against `edge` of the stitched layer `anchor`.
  case stitch(anchor: UUID, edge: CombineStitchEdge)
  /// Float above the stitched images, centred on `point`.
  case overlay(at: CGPoint)
}

enum CombineDropResolver {
  /// Share of an image's width/height, measured from each edge, that counts as "near
  /// the edge" — a drop there stitches; deeper inside it overlaps.
  static let edgeBandFraction: CGFloat = 0.22

  /// Resolve a drop in canvas coordinates (y up) against the stitched layers.
  /// - Inside a layer near an edge → stitch on that edge.
  /// - Inside a layer, past the edge band → overlay (or the nearest edge when
  ///   `allowsOverlay` is false).
  /// - Outside every layer → stitch to the nearest layer on the side the point lies.
  static func resolve(
    point: CGPoint,
    layers: [(id: UUID, rect: CGRect)],
    allowsOverlay: Bool = true,
    edgeBandFraction: CGFloat = CombineDropResolver.edgeBandFraction
  ) -> CombineDropTarget? {
    let usable = layers.filter { $0.rect.width > 0 && $0.rect.height > 0 }
    guard !usable.isEmpty else { return nil }

    if let hit = usable.last(where: { $0.rect.contains(point) }) {
      let rect = hit.rect
      let bandX = max(rect.width * edgeBandFraction, 0.0001)
      let bandY = max(rect.height * edgeBandFraction, 0.0001)
      let candidates: [(CombineStitchEdge, CGFloat)] = [
        (.left, (point.x - rect.minX) / bandX),
        (.right, (rect.maxX - point.x) / bandX),
        (.top, (rect.maxY - point.y) / bandY),
        (.bottom, (point.y - rect.minY) / bandY)
      ]
      let nearest = candidates.min { $0.1 < $1.1 }!
      if nearest.1 <= 1 || !allowsOverlay {
        return .stitch(anchor: hit.id, edge: nearest.0)
      }
      return .overlay(at: point)
    }

    let nearest = usable.min { distance(from: point, to: $0.rect) < distance(from: point, to: $1.rect) }!
    return .stitch(anchor: nearest.id, edge: outsideEdge(of: point, relativeTo: nearest.rect))
  }

  private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
    let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
    let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
    return hypot(dx, dy)
  }

  /// Side of `rect` that `point` (outside it) lies on, weighting overshoot by the
  /// rect's size so a diagonal drop picks the side it is relatively further past.
  private static func outsideEdge(of point: CGPoint, relativeTo rect: CGRect) -> CombineStitchEdge {
    let width = max(rect.width, 0.0001)
    let height = max(rect.height, 0.0001)
    let candidates: [(CombineStitchEdge, CGFloat)] = [
      (.left, (rect.minX - point.x) / width),
      (.right, (point.x - rect.maxX) / width),
      (.top, (point.y - rect.maxY) / height),
      (.bottom, (rect.minY - point.y) / height)
    ]
    return candidates.max { $0.1 < $1.1 }!.0
  }
}

/// Insertion edge drawn while a stitch drop is hovering, canvas space.
struct CombineInsertionLine: Equatable {
  let start: CGPoint
  let end: CGPoint
}

/// What the canvas draws while an image is dropped or dragged in Auto Stitch.
struct CombineDropPreview: Equatable {
  let target: CombineDropTarget
  /// The image (or, for a new row, the whole row) that receives the drop, canvas space.
  let highlightRect: CGRect
  /// Edge the image attaches to; nil for an overlay.
  let insertionLine: CombineInsertionLine?
}
