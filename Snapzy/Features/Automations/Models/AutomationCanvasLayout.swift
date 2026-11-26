//
//  AutomationCanvasLayout.swift
//  Snapzy
//
//  What the canvas editor keeps beside the run model: where each node sits and
//  the steps that are on the canvas but not connected to the source. Detached
//  steps never run. The runner, launcher and validator only look at `steps`.
//

import Foundation

struct AutomationCanvasPoint: Codable, Equatable, Sendable {
  var x: Double
  var y: Double

  init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }

  init(_ point: CGPoint) {
    x = Double(point.x)
    y = Double(point.y)
  }

  var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

struct AutomationCanvasLayout: Codable, Equatable {
  /// Position keys for the two fixed nodes; step nodes use their UUID string.
  static let triggerKey = "trigger"
  static let sourceKey = "source"

  /// Node centers in canvas coordinates.
  var positions: [String: AutomationCanvasPoint]
  /// Chains of steps not reachable from the source, each in link order.
  var detached: [[AutomationStep]]

  init(positions: [String: AutomationCanvasPoint] = [:], detached: [[AutomationStep]] = []) {
    self.positions = positions
    self.detached = detached.filter { !$0.isEmpty }
  }

  var detachedStepCount: Int {
    detached.reduce(0) { $0 + $1.count }
  }

  private enum CodingKeys: String, CodingKey {
    case positions, detached
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    positions = (try? container.decode([String: AutomationCanvasPoint].self, forKey: .positions)) ?? [:]
    let chains = (try? container.decode([[AutomationStep]].self, forKey: .detached)) ?? []
    detached = chains.map { $0.flatMap(\.migrated) }.filter { !$0.isEmpty }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(positions, forKey: .positions)
    if !detached.isEmpty {
      try container.encode(detached, forKey: .detached)
    }
  }

  /// Keeps positions only for nodes that still exist and caps detached steps so
  /// steps + detached never exceed `Automation.maxSteps`.
  func normalized(keepingStepIDs ids: Set<UUID>, room: Int) -> AutomationCanvasLayout {
    var remaining = max(0, room)
    var chains: [[AutomationStep]] = []
    for chain in detached where remaining > 0 {
      let kept = Array(chain.prefix(remaining))
      remaining -= kept.count
      chains.append(kept)
    }
    let allIDs = ids.union(chains.flatMap { $0.map(\.id) })
    let keys = Set(allIDs.map(\.uuidString)).union([Self.triggerKey, Self.sourceKey])
    return AutomationCanvasLayout(
      positions: positions.filter { keys.contains($0.key) },
      detached: chains
    )
  }

  /// Same layout after step ids changed (duplicating an automation).
  func remapped(_ map: [UUID: UUID]) -> AutomationCanvasLayout {
    var moved: [String: AutomationCanvasPoint] = [:]
    for (key, point) in positions {
      if let old = UUID(uuidString: key), let new = map[old] {
        moved[new.uuidString] = point
      } else {
        moved[key] = point
      }
    }
    let chains = detached.map { chain in
      chain.map { step -> AutomationStep in
        var copy = step
        copy.id = map[step.id] ?? step.id
        return copy
      }
    }
    return AutomationCanvasLayout(positions: moved, detached: chains)
  }
}
