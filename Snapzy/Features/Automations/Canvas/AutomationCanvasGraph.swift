//
//  AutomationCanvasGraph.swift
//  Snapzy
//
//  The canvas editor's node graph. Trigger → Source is fixed; every other node
//  is a step with at most one link in and one out. The steps reachable from
//  the source are the automation's run order; the rest are detached chains that
//  are kept on the canvas but never run. Pure value type so it can be tested.
//

import CoreGraphics
import Foundation

enum AutomationCanvasNodeID: Hashable {
  case trigger
  case source
  case step(UUID)

  var layoutKey: String {
    switch self {
    case .trigger: AutomationCanvasLayout.triggerKey
    case .source: AutomationCanvasLayout.sourceKey
    case .step(let id): id.uuidString
    }
  }

  var stepID: UUID? {
    if case .step(let id) = self { return id }
    return nil
  }
}

struct AutomationCanvasLink: Hashable {
  let from: AutomationCanvasNodeID
  let to: AutomationCanvasNodeID
}

struct AutomationCanvasGraph: Equatable {
  /// Node size in canvas units; positions are node centers.
  static let nodeSize = CGSize(width: 232, height: 60)
  static let columnSpacing: CGFloat = 296
  static let rowSpacing: CGFloat = 120

  private(set) var steps: [UUID: AutomationStep] = [:]
  /// Step ids in creation order, so rendering is stable.
  private(set) var stepOrder: [UUID] = []
  /// Outgoing link of a node (trigger → source is implied and never stored).
  private(set) var next: [AutomationCanvasNodeID: UUID] = [:]
  var positions: [AutomationCanvasNodeID: CGPoint] = [:]

  init() {}

  init(automation: Automation) {
    let layout = automation.canvas
    var previous: AutomationCanvasNodeID = .source
    for step in automation.steps {
      addNode(step)
      next[previous] = step.id
      previous = .step(step.id)
    }
    for chain in layout?.detached ?? [] {
      var previousDetached: UUID?
      for step in chain where steps[step.id] == nil {
        addNode(step)
        if let previousDetached { next[.step(previousDetached)] = step.id }
        previousDetached = step.id
      }
    }
    for node in allNodes {
      if let point = layout?.positions[node.layoutKey] {
        positions[node] = point.cgPoint
      }
    }
    if positions.count < allNodes.count {
      placeMissingNodes()
    }
  }

  // MARK: - Reading

  var allNodes: [AutomationCanvasNodeID] {
    [.trigger, .source] + stepOrder.map { .step($0) }
  }

  /// Steps that run, in order.
  var chain: [UUID] {
    var result: [UUID] = []
    var seen = Set<UUID>()
    var cursor = next[.source]
    while let id = cursor, seen.insert(id).inserted {
      result.append(id)
      cursor = next[.step(id)]
    }
    return result
  }

  var chainSteps: [AutomationStep] {
    chain.compactMap { steps[$0] }
  }

  /// Chains not reachable from the source, each from its head.
  var detachedChains: [[UUID]] {
    let attached = Set(chain)
    let targets = Set(next.values)
    var visited = attached
    var chains: [[UUID]] = []
    for id in stepOrder where !visited.contains(id) && !targets.contains(id) {
      var chain: [UUID] = []
      var cursor: UUID? = id
      while let current = cursor, visited.insert(current).inserted {
        chain.append(current)
        cursor = next[.step(current)]
      }
      chains.append(chain)
    }
    // A cycle has no head; break it where it was created first.
    for id in stepOrder where !visited.contains(id) {
      var chain: [UUID] = []
      var cursor: UUID? = id
      while let current = cursor, visited.insert(current).inserted {
        chain.append(current)
        cursor = next[.step(current)]
      }
      chains.append(chain)
    }
    return chains
  }

  var detachedIDs: Set<UUID> {
    Set(stepOrder).subtracting(chain)
  }

  var links: [AutomationCanvasLink] {
    var result = [AutomationCanvasLink(from: .trigger, to: .source)]
    for node in allNodes {
      if let target = next[node] {
        result.append(AutomationCanvasLink(from: node, to: .step(target)))
      }
    }
    return result
  }

  func successor(of node: AutomationCanvasNodeID) -> AutomationCanvasNodeID? {
    if node == .trigger { return .source }
    return next[node].map { .step($0) }
  }

  func predecessor(of node: AutomationCanvasNodeID) -> AutomationCanvasNodeID? {
    switch node {
    case .trigger: return nil
    case .source: return .trigger
    case .step(let id): return next.first { $0.value == id }?.key
    }
  }

  func position(of node: AutomationCanvasNodeID) -> CGPoint {
    positions[node] ?? .zero
  }

  func frame(of node: AutomationCanvasNodeID) -> CGRect {
    let center = position(of: node)
    return CGRect(
      x: center.x - Self.nodeSize.width / 2,
      y: center.y - Self.nodeSize.height / 2,
      width: Self.nodeSize.width,
      height: Self.nodeSize.height
    )
  }

  /// Bounding box of every node, in canvas coordinates.
  var bounds: CGRect {
    allNodes.map(frame(of:)).reduce(CGRect.null) { $0.union($1) }
  }

  /// Linking `from → to` is allowed: no link into the fixed nodes, out of the
  /// trigger, onto itself, or one that closes a loop.
  func canConnect(from: AutomationCanvasNodeID, to: AutomationCanvasNodeID) -> Bool {
    guard from != .trigger, let target = to.stepID, steps[target] != nil, from != to else { return false }
    if next[from] == target { return false }
    guard case .step(let origin) = from else { return true }
    // The new link must not lead back to `from`.
    var cursor: UUID? = target
    var seen = Set<UUID>()
    while let current = cursor, seen.insert(current).inserted {
      if current == origin { return false }
      cursor = next[.step(current)]
    }
    return true
  }

  // MARK: - Editing

  /// Links `from → to`. The node `from` linked to before, and the node that
  /// linked to `to` before, are cut off (as in node editors).
  @discardableResult
  mutating func connect(from: AutomationCanvasNodeID, to: AutomationCanvasNodeID) -> Bool {
    guard canConnect(from: from, to: to), let target = to.stepID else { return false }
    reconcilingSkips { graph in
      if let previous = graph.predecessor(of: to) { graph.next[previous] = nil }
      graph.next[from] = target
    }
    return true
  }

  mutating func disconnect(from: AutomationCanvasNodeID) {
    guard next[from] != nil else { return }
    reconcilingSkips { $0.next[from] = nil }
  }

  /// Adds a step after `node` (between it and its successor), or unlinked
  /// when `node` is nil. `at` places it; otherwise it goes to the right of `node`.
  mutating func insert(_ step: AutomationStep, after node: AutomationCanvasNodeID?, at point: CGPoint? = nil) {
    let previousBounds = bounds
    let anchor = node == .trigger ? AutomationCanvasNodeID.source : node
    let following = anchor.flatMap { next[$0] }
    reconcilingSkips { graph in
      graph.addNode(step)
      if let anchor {
        graph.next[anchor] = step.id
        if let following { graph.next[.step(step.id)] = following }
      }
    }
    let placed: CGPoint
    if let point {
      placed = point
    } else if let following {
      // On a link: take the next node's place and push the rest of the chain right.
      placed = position(of: .step(following))
      shiftChain(from: .step(following), by: Self.columnSpacing)
    } else if let anchor {
      placed = freeSpot(rightOf: anchor)
    } else {
      placed = freeSpot(near: CGPoint(x: previousBounds.midX, y: previousBounds.maxY + Self.rowSpacing))
    }
    positions[.step(step.id)] = placed
  }

  /// Deletes a step and joins its neighbours.
  mutating func remove(_ id: UUID) {
    guard steps[id] != nil else { return }
    reconcilingSkips { graph in
      let previous = graph.predecessor(of: .step(id))
      let following = graph.next[.step(id)]
      graph.next[.step(id)] = nil
      if let previous { graph.next[previous] = following }
      graph.steps[id] = nil
      graph.stepOrder.removeAll { $0 == id }
    }
    positions[.step(id)] = nil
  }

  mutating func update(_ step: AutomationStep) {
    guard steps[step.id] != nil else { return }
    steps[step.id] = step
  }

  /// Lays every node out left to right: the run chain on the first row, each
  /// detached chain on a row below.
  mutating func autoLayout() {
    let origin = CGPoint.zero
    positions[.trigger] = origin
    positions[.source] = CGPoint(x: origin.x + Self.columnSpacing, y: origin.y)
    for (index, id) in chain.enumerated() {
      positions[.step(id)] = CGPoint(x: origin.x + Self.columnSpacing * CGFloat(index + 2), y: origin.y)
    }
    for (row, detached) in detachedChains.enumerated() {
      for (index, id) in detached.enumerated() {
        positions[.step(id)] = CGPoint(
          x: origin.x + Self.columnSpacing * CGFloat(index + 2),
          y: origin.y + Self.rowSpacing * CGFloat(row + 1)
        )
      }
    }
  }

  // MARK: - Writing back

  /// `automation` with this graph's steps and layout.
  func applied(to automation: Automation) -> Automation {
    var copy = automation
    copy.steps = chainSteps
    var points: [String: AutomationCanvasPoint] = [:]
    for (node, point) in positions {
      points[node.layoutKey] = AutomationCanvasPoint(point)
    }
    copy.canvas = AutomationCanvasLayout(
      positions: points,
      detached: detachedChains.map { $0.compactMap { steps[$0] } }
    )
    return copy
  }

  // MARK: - Private

  private mutating func addNode(_ step: AutomationStep) {
    steps[step.id] = step
    if !stepOrder.contains(step.id) { stepOrder.append(step.id) }
  }

  /// Keeps each condition's "Otherwise skip" covering the same steps after the
  /// chain changes: a step added inside the range joins it, a removed one leaves.
  private mutating func reconcilingSkips(_ body: (inout AutomationCanvasGraph) -> Void) {
    let before = chain
    var ranges: [UUID: [UUID]] = [:]
    for (index, id) in before.enumerated() {
      guard case .condition(let config)? = steps[id]?.action,
            case .skip(let count) = config.otherwise, count > 0 else { continue }
      ranges[id] = Array(before[(index + 1)..<min(before.count, index + 1 + count)])
    }
    body(&self)
    guard !ranges.isEmpty else { return }
    let after = chain
    for (index, id) in after.enumerated() {
      guard let range = ranges[id], var step = steps[id],
            case .condition(var config)? = step.action,
            case .skip(let count) = config.otherwise else { continue }
      let members = Set(range)
      let following = after[(index + 1)...]
      // The branch ends at the last of its old steps still following the condition.
      var lastOffset = 0
      for (offset, candidate) in following.enumerated() where members.contains(candidate) {
        lastOffset = offset + 1
      }
      let remaining = following.count
      // A skip that reached past the old chain end meant "to the end"; keep that.
      // (Same as `Automation.insertStep`: only a count longer than the steps after it.)
      let stepsAfterBefore = before.firstIndex(of: id).map { before.count - 1 - $0 }
      let updated: Int
      if let stepsAfterBefore, count > stepsAfterBefore {
        updated = max(count, remaining)
      } else {
        updated = lastOffset > 0 ? lastOffset : max(1, min(count, remaining))
      }
      guard updated != count else { continue }
      config.otherwise = .skip(min(updated, AutomationConditionConfig.Otherwise.maxSkip))
      step.content = .action(.condition(config))
      steps[id] = step
    }
  }

  private mutating func placeMissingNodes() {
    if positions[.trigger] == nil || positions[.source] == nil {
      // No usable layout: lay everything out.
      autoLayout()
      return
    }
    for id in chain + detachedChains.joined() where positions[.step(id)] == nil {
      let anchor = predecessor(of: .step(id)) ?? .source
      positions[.step(id)] = freeSpot(rightOf: anchor)
    }
  }

  private func freeSpot(rightOf node: AutomationCanvasNodeID) -> CGPoint {
    let anchor = position(of: node)
    return freeSpot(near: CGPoint(x: anchor.x + Self.columnSpacing, y: anchor.y))
  }

  /// `point`, moved down a row at a time until no node is under it.
  private func freeSpot(near point: CGPoint) -> CGPoint {
    var candidate = point
    for _ in 0..<20 {
      let rect = CGRect(
        x: candidate.x - Self.nodeSize.width / 2,
        y: candidate.y - Self.nodeSize.height / 2,
        width: Self.nodeSize.width,
        height: Self.nodeSize.height
      ).insetBy(dx: -12, dy: -12)
      let taken = positions.values.contains { other in
        rect.intersects(CGRect(
          x: other.x - Self.nodeSize.width / 2,
          y: other.y - Self.nodeSize.height / 2,
          width: Self.nodeSize.width,
          height: Self.nodeSize.height
        ))
      }
      if !taken { return candidate }
      candidate.y += Self.rowSpacing
    }
    return candidate
  }

  /// Moves `node` and every node after it horizontally.
  private mutating func shiftChain(from node: AutomationCanvasNodeID, by dx: CGFloat) {
    var cursor: AutomationCanvasNodeID? = node
    var seen = Set<AutomationCanvasNodeID>()
    while let current = cursor, seen.insert(current).inserted {
      positions[current]?.x += dx
      cursor = successor(of: current)
    }
  }
}
