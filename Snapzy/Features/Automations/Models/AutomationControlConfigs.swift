//
//  AutomationControlConfigs.swift
//  Snapzy
//
//  Control step settings (milestone 5): `condition` branches on the run
//  context, `runAutomation` reuses another automation's steps and `ask` lets
//  the user pick at run time. The chain stays linear: a failed condition stops
//  the run or skips the next steps, so if / else is
//  `condition(else skip 2) · A · stop · B`.
//
//  Every type decodes tolerantly; a predicate written by a newer Snapzy is
//  kept as `.unsupported` and evaluates to false.
//

import Foundation

// MARK: - Condition

nonisolated struct AutomationConditionConfig: Codable, Equatable, Sendable {
  enum Match: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Every predicate must hold.
    case all
    /// At least one predicate must hold.
    case any

    var id: String { rawValue }
  }

  /// What happens when the predicates don't hold.
  enum Otherwise: Equatable, Sendable {
    /// End the run (successfully).
    case stop
    /// Skip the next `n` steps of the list (disabled steps count too).
    case skip(Int)

    static let maxSkip = Automation.maxSteps

    /// `stop` or `skip:2` (JSON and config.toml).
    var token: String {
      switch self {
      case .stop: "stop"
      case .skip(let count): "skip:\(count)"
      }
    }

    init?(token: String) {
      let raw = token.trimmingCharacters(in: .whitespaces).lowercased()
      if raw == "stop" {
        self = .stop
      } else if raw.hasPrefix("skip:"), let count = Int(raw.dropFirst(5)), count >= 1 {
        self = .skip(min(count, Self.maxSkip))
      } else if raw == "skip" {
        self = .skip(1)
      } else {
        return nil
      }
    }
  }

  var match: Match
  var predicates: [AutomationPredicate]
  var otherwise: Otherwise

  init(match: Match = .all, predicates: [AutomationPredicate] = [], otherwise: Otherwise = .stop) {
    self.match = match
    self.predicates = predicates
    self.otherwise = otherwise
  }

  private enum CodingKeys: String, CodingKey {
    case match, predicates, otherwise
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    match = container.value(.match, default: .all)
    predicates = container.value(.predicates, default: [])
    otherwise = container.value(.otherwise, default: String?.none).flatMap(Otherwise.init(token:)) ?? .stop
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(match, forKey: .match)
    try container.encode(predicates, forKey: .predicates)
    try container.encode(otherwise.token, forKey: .otherwise)
  }

  /// Steps after this one that `.skip(n)` jumps over.
  var skipCount: Int {
    if case .skip(let count) = otherwise { return count }
    return 0
  }
}

nonisolated enum AutomationComparison: String, Codable, CaseIterable, Identifiable, Sendable {
  case greaterThan = "gt"
  case lessThan = "lt"

  var id: String { rawValue }

  func holds(_ lhs: Int, _ rhs: Int) -> Bool {
    switch self {
    case .greaterThan: lhs > rhs
    case .lessThan: lhs < rhs
    }
  }
}

nonisolated enum AutomationDimension: String, Codable, CaseIterable, Identifiable, Sendable {
  case width
  case height
  /// The longer edge.
  case longest

  var id: String { rawValue }
}

/// One test on the run context or the current payload.
nonisolated enum AutomationPredicate: Equatable, Sendable {
  /// App that was frontmost when the run was triggered (the captured window's app wins).
  case frontmostApp(bundleIDs: [String], negate: Bool)
  case captureMode([AutomationCaptureMode])
  case invocation([AutomationInvocation])
  /// Kind of the first file.
  case fileKind([AutomationFileKind])
  /// Pixel size of the first image.
  case pixelSize(dimension: AutomationDimension, comparison: AutomationComparison, value: Int)
  /// Size on disk of the first file.
  case fileSize(comparison: AutomationComparison, bytes: Int)
  /// Text recognized by an earlier step; with `contains`, case-insensitive.
  case hasText(contains: String?)
  case unsupported(AutomationJSONValue)

  /// Stable `type` used in JSON and config.toml.
  var type: String {
    switch self {
    case .frontmostApp: "frontmost_app"
    case .captureMode: "capture_mode"
    case .invocation: "invocation"
    case .fileKind: "file_kind"
    case .pixelSize: "pixel_size"
    case .fileSize: "file_size"
    case .hasText: "has_text"
    case .unsupported(let raw):
      if case .object(let members) = raw, case .string(let type)? = members["type"] { type } else { "unknown" }
    }
  }

  /// Types offered by the editor, in menu order.
  static let editableTypes = ["frontmost_app", "capture_mode", "file_kind", "pixel_size", "file_size", "has_text", "invocation"]

  /// A new predicate of `type` with sensible values.
  static func makeDefault(type: String) -> AutomationPredicate? {
    switch type {
    case "frontmost_app": .frontmostApp(bundleIDs: [], negate: false)
    case "capture_mode": .captureMode([.area])
    case "invocation": .invocation([.hotkey])
    case "file_kind": .fileKind([.image])
    case "pixel_size": .pixelSize(dimension: .longest, comparison: .greaterThan, value: 1600)
    case "file_size": .fileSize(comparison: .greaterThan, bytes: 5_000_000)
    case "has_text": .hasText(contains: nil)
    default: nil
    }
  }
}

extension AutomationPredicate: Codable {
  private enum CodingKeys: String, CodingKey {
    case type, bundleIDs, negate, modes, invocations, kinds, dimension, comparison, value, bytes, contains
  }

  init(from decoder: Decoder) throws {
    let raw = try AutomationJSONValue(from: decoder)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = container.value(.type, default: "")

    /// Raw strings mapped through `make`; unknown values are dropped.
    func list<T>(_ key: CodingKeys, _ make: (String) -> T?) -> [T] {
      container.value(key, default: [String]()).compactMap(make)
    }

    switch type {
    case "frontmost_app":
      self = .frontmostApp(
        bundleIDs: container.value(.bundleIDs, default: [String]()),
        negate: container.value(.negate, default: false)
      )
    case "capture_mode":
      self = .captureMode(list(.modes, AutomationCaptureMode.init(rawValue:)))
    case "invocation":
      self = .invocation(list(.invocations, AutomationInvocation.init(rawValue:)))
    case "file_kind":
      self = .fileKind(list(.kinds, AutomationFileKind.init(rawValue:)))
    case "pixel_size":
      self = .pixelSize(
        dimension: container.value(.dimension, default: .longest),
        comparison: container.value(.comparison, default: .greaterThan),
        value: container.value(.value, default: 0)
      )
    case "file_size":
      self = .fileSize(
        comparison: container.value(.comparison, default: .greaterThan),
        bytes: container.value(.bytes, default: 0)
      )
    case "has_text":
      let contains: String? = container.value(.contains, default: nil)
      self = .hasText(contains: contains?.isEmpty == true ? nil : contains)
    default:
      self = .unsupported(raw)
    }
  }

  func encode(to encoder: Encoder) throws {
    if case .unsupported(let raw) = self {
      try raw.encode(to: encoder)
      return
    }
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    switch self {
    case .frontmostApp(let bundleIDs, let negate):
      try container.encode(bundleIDs, forKey: .bundleIDs)
      if negate { try container.encode(true, forKey: .negate) }
    case .captureMode(let modes):
      try container.encode(modes.map(\.rawValue), forKey: .modes)
    case .invocation(let invocations):
      try container.encode(invocations.map(\.rawValue), forKey: .invocations)
    case .fileKind(let kinds):
      try container.encode(kinds.map(\.rawValue), forKey: .kinds)
    case .pixelSize(let dimension, let comparison, let value):
      try container.encode(dimension, forKey: .dimension)
      try container.encode(comparison, forKey: .comparison)
      try container.encode(value, forKey: .value)
    case .fileSize(let comparison, let bytes):
      try container.encode(comparison, forKey: .comparison)
      try container.encode(bytes, forKey: .bytes)
    case .hasText(let contains):
      try container.encodeIfPresent(contains, forKey: .contains)
    case .unsupported:
      break
    }
  }
}

// MARK: - Run automation

nonisolated struct AutomationRunAutomationConfig: Codable, Equatable, Sendable {
  /// The automation whose steps run on the current payload (its source and
  /// triggers are ignored). `nil` until chosen in the editor.
  var automationID: UUID?

  init(automationID: UUID? = nil) {
    self.automationID = automationID
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    automationID = container.value(.automationID, default: nil)
  }
}

// MARK: - Ask

nonisolated enum AutomationAskChoice: Equatable, Hashable, Sendable {
  /// Run that automation's steps on the current payload, then end this run.
  case automation(UUID)
  /// Go on with the next step.
  case continueRun
  /// End the run here.
  case stopRun

  /// `<uuid>`, `continue` or `stop` (JSON and config.toml).
  var token: String {
    switch self {
    case .automation(let id): id.uuidString.lowercased()
    case .continueRun: "continue"
    case .stopRun: "stop"
    }
  }

  init?(token: String) {
    let raw = token.trimmingCharacters(in: .whitespaces)
    switch raw.lowercased() {
    case "continue": self = .continueRun
    case "stop": self = .stopRun
    default:
      guard let id = UUID(uuidString: raw) else { return nil }
      self = .automation(id)
    }
  }

  var automationID: UUID? {
    if case .automation(let id) = self { return id }
    return nil
  }
}

nonisolated struct AutomationAskConfig: Codable, Equatable, Sendable {
  /// Title of the picker; empty uses the automation's name.
  var prompt: String
  var choices: [AutomationAskChoice]

  /// Number keys 1–9 pick a row; the picker shows a search field beyond that.
  static let maxChoices = 12

  init(prompt: String = "", choices: [AutomationAskChoice] = []) {
    self.prompt = prompt
    self.choices = choices
  }

  private enum CodingKeys: String, CodingKey {
    case prompt, choices
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    prompt = container.value(.prompt, default: "")
    choices = container.value(.choices, default: [String]()).compactMap(AutomationAskChoice.init(token:))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    if !prompt.isEmpty { try container.encode(prompt, forKey: .prompt) }
    try container.encode(choices.map(\.token), forKey: .choices)
  }

  var referencedAutomationIDs: [UUID] {
    choices.compactMap(\.automationID)
  }
}

// MARK: - Editing steps inside skip ranges

extension Automation {
  /// Removes a step and shrinks the "Otherwise skip" of conditions whose range held it,
  /// so the steps after the range keep running where they did.
  mutating func removeStep(at index: Int) {
    guard steps.indices.contains(index) else { return }
    for conditionIndex in steps.indices where conditionIndex < index {
      guard case .condition(var config)? = steps[conditionIndex].action,
            case .skip(let count) = config.otherwise,
            index <= conditionIndex + count, count > 1
      else { continue }
      config.otherwise = .skip(count - 1)
      steps[conditionIndex].content = .action(.condition(config))
    }
    steps.remove(at: index)
  }

  /// Inserts a step; inside a condition's skip range it joins that branch.
  mutating func insertStep(_ step: AutomationStep, at index: Int) {
    let index = min(max(0, index), steps.count)
    for conditionIndex in steps.indices where conditionIndex < index {
      guard case .condition(var config)? = steps[conditionIndex].action,
            case .skip(let count) = config.otherwise,
            index <= conditionIndex + count
      else { continue }
      config.otherwise = .skip(min(count + 1, AutomationConditionConfig.Otherwise.maxSkip))
      steps[conditionIndex].content = .action(.condition(config))
    }
    steps.insert(step, at: index)
  }
}
