//
//  Automation.swift
//  Snapzy
//
//  Persisted automation model: triggers + source + ordered steps.
//  Milestone 1 ships hotkey triggers, screenshot capture sources and five steps;
//  every enum keeps unknown cases as `.unsupported` so automations written by a
//  newer Snapzy survive a round trip through this build.
//

import Foundation

// MARK: - Capture source

enum AutomationCaptureMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case area
  case fullscreen
  case activeWindow
  case applicationWindow

  var id: String { rawValue }
}

struct AutomationCaptureSpec: Codable, Equatable, Sendable {
  var mode: AutomationCaptureMode
  /// `false` writes the capture into the temp capture directory, like turning
  /// off the after-capture Save action.
  var saveToExportDirectory: Bool
}

enum AutomationSource: Equatable {
  case capture(AutomationCaptureSpec)
  /// Runs only on files handed in by the trigger (Quick Access, History, CLI,
  /// Shortcuts). Never starts a capture, so it has no hotkey or menu bar item.
  case input
  case unsupported(AutomationJSONValue)
}

extension AutomationSource: Codable {
  private enum CodingKeys: String, CodingKey {
    case kind, mode, saveToExportDirectory
  }

  init(from decoder: Decoder) throws {
    let raw = try AutomationJSONValue(from: decoder)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try? container.decode(String.self, forKey: .kind)
    if kind == "capture",
       let mode = try? container.decode(AutomationCaptureMode.self, forKey: .mode)
    {
      let save = (try? container.decode(Bool.self, forKey: .saveToExportDirectory)) ?? false
      self = .capture(AutomationCaptureSpec(mode: mode, saveToExportDirectory: save))
    } else if kind == "input" {
      self = .input
    } else {
      self = .unsupported(raw)
    }
  }

  func encode(to encoder: Encoder) throws {
    switch self {
    case .capture(let spec):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode("capture", forKey: .kind)
      try container.encode(spec.mode, forKey: .mode)
      try container.encode(spec.saveToExportDirectory, forKey: .saveToExportDirectory)
    case .input:
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode("input", forKey: .kind)
    case .unsupported(let raw):
      try raw.encode(to: encoder)
    }
  }
}

// MARK: - Triggers

enum AutomationTrigger: Equatable {
  case hotkey(ShortcutConfig)
  /// Listed in the menu bar "Automations" submenu.
  case menuBar
  /// Listed in a Quick Access card's "Run Automation" menu.
  case quickAccessAction
  /// Listed in a History item's "Run Automation" menu.
  case historyAction
  case unsupported(AutomationJSONValue)

  /// Stored kinds without a payload, keyed by their JSON `kind`.
  fileprivate static let simpleKinds: [String: AutomationTrigger] = [
    "menuBar": .menuBar,
    "quickAccessAction": .quickAccessAction,
    "historyAction": .historyAction,
  ]

  fileprivate var simpleKind: String? {
    switch self {
    case .menuBar: "menuBar"
    case .quickAccessAction: "quickAccessAction"
    case .historyAction: "historyAction"
    case .hotkey, .unsupported: nil
    }
  }
}

extension AutomationTrigger: Codable {
  private enum CodingKeys: String, CodingKey {
    case kind, shortcut
  }

  init(from decoder: Decoder) throws {
    let raw = try AutomationJSONValue(from: decoder)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try? container.decode(String.self, forKey: .kind)
    if kind == "hotkey",
       let shortcut = try? container.decode(ShortcutConfig.self, forKey: .shortcut)
    {
      self = .hotkey(shortcut)
    } else if let kind, let simple = Self.simpleKinds[kind] {
      self = simple
    } else {
      self = .unsupported(raw)
    }
  }

  func encode(to encoder: Encoder) throws {
    switch self {
    case .hotkey(let shortcut):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode("hotkey", forKey: .kind)
      try container.encode(shortcut, forKey: .shortcut)
    case .menuBar, .quickAccessAction, .historyAction:
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(simpleKind, forKey: .kind)
    case .unsupported(let raw):
      try raw.encode(to: encoder)
    }
  }
}

// MARK: - Steps

enum AutomationLinkFormat: String, Codable, CaseIterable, Identifiable, Sendable {
  /// `https://…/file.png`
  case url
  /// `![file](https://…/file.png)`
  case markdown

  var id: String { rawValue }
}

enum AutomationFailurePolicy: String, Codable, Sendable {
  case stop
  case `continue`
}

/// What a step does. The order of `allSupportedKinds` is the canonical order
/// the M1 editor writes steps in.
enum AutomationStepAction: Equatable {
  case copyImage
  case uploadAndCopyLink(AutomationLinkFormat)
  case showQuickAccess
  case openAnnotate
  case notify

  var kind: AutomationStepKind {
    switch self {
    case .copyImage: .copyImage
    case .uploadAndCopyLink: .uploadAndCopyLink
    case .showQuickAccess: .showQuickAccess
    case .openAnnotate: .openAnnotate
    case .notify: .notify
    }
  }
}

enum AutomationStepKind: String, Codable, CaseIterable, Identifiable, Sendable {
  case copyImage
  case uploadAndCopyLink
  case showQuickAccess
  case openAnnotate
  case notify

  var id: String { rawValue }
}

struct AutomationStep: Identifiable, Equatable {
  enum Content: Equatable {
    case action(AutomationStepAction)
    /// A step kind added by a newer Snapzy; kept as written and skipped when run.
    case unsupported(AutomationJSONValue)
  }

  var id: UUID
  var content: Content
  var isEnabled: Bool
  var onFailure: AutomationFailurePolicy

  init(
    id: UUID = UUID(),
    _ action: AutomationStepAction,
    isEnabled: Bool = true,
    onFailure: AutomationFailurePolicy = .stop
  ) {
    self.id = id
    self.content = .action(action)
    self.isEnabled = isEnabled
    self.onFailure = onFailure
  }

  var action: AutomationStepAction? {
    guard case .action(let action) = content else { return nil }
    return action
  }
}

extension AutomationStep: Codable {
  private enum CodingKeys: String, CodingKey {
    case id, kind, format, isEnabled, onFailure
  }

  init(from decoder: Decoder) throws {
    let raw = try AutomationJSONValue(from: decoder)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
    isEnabled = (try? container.decode(Bool.self, forKey: .isEnabled)) ?? true
    onFailure = (try? container.decode(AutomationFailurePolicy.self, forKey: .onFailure)) ?? .stop

    let kindRaw = try? container.decode(String.self, forKey: .kind)
    switch kindRaw.flatMap(AutomationStepKind.init(rawValue:)) {
    case .copyImage?: content = .action(.copyImage)
    case .uploadAndCopyLink?:
      let format = (try? container.decode(AutomationLinkFormat.self, forKey: .format)) ?? .url
      content = .action(.uploadAndCopyLink(format))
    case .showQuickAccess?: content = .action(.showQuickAccess)
    case .openAnnotate?: content = .action(.openAnnotate)
    case .notify?: content = .action(.notify)
    case nil: content = .unsupported(raw)
    }
  }

  func encode(to encoder: Encoder) throws {
    guard case .action(let action) = content else {
      if case .unsupported(let raw) = content {
        try raw.encode(to: encoder)
      }
      return
    }
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(action.kind, forKey: .kind)
    if case .uploadAndCopyLink(let format) = action {
      try container.encode(format, forKey: .format)
    }
    try container.encode(isEnabled, forKey: .isEnabled)
    try container.encode(onFailure, forKey: .onFailure)
  }
}

// MARK: - Automation

struct Automation: Identifiable, Equatable {
  static let currentSchemaVersion = 1
  static let maxNameLength = 60

  var id: UUID
  var name: String
  var symbol: String?
  var isEnabled: Bool
  var triggers: [AutomationTrigger]
  var source: AutomationSource
  var steps: [AutomationStep]
  /// Allow running from the URL scheme, CLI and Shortcuts (milestone 2). Off by default.
  var externalInvocation: Bool
  /// Built-in preset this automation was seeded from, if any.
  var presetID: String?
  var schemaVersion: Int

  init(
    id: UUID = UUID(),
    name: String,
    symbol: String? = nil,
    isEnabled: Bool = true,
    triggers: [AutomationTrigger] = [],
    source: AutomationSource,
    steps: [AutomationStep],
    externalInvocation: Bool = false,
    presetID: String? = nil,
    schemaVersion: Int = Automation.currentSchemaVersion
  ) {
    self.id = id
    self.name = name
    self.symbol = symbol
    self.isEnabled = isEnabled
    self.triggers = triggers
    self.source = source
    self.steps = steps
    self.externalInvocation = externalInvocation
    self.presetID = presetID
    self.schemaVersion = schemaVersion
  }

  /// The keyboard shortcut trigger, if any. Setting `nil` removes it.
  var hotkey: ShortcutConfig? {
    get {
      for trigger in triggers {
        if case .hotkey(let config) = trigger { return config }
      }
      return nil
    }
    set {
      triggers.removeAll {
        if case .hotkey = $0 { return true }
        return false
      }
      if let newValue {
        triggers.insert(.hotkey(newValue), at: 0)
      }
    }
  }

  var showsInMenuBar: Bool {
    get { triggers.contains(.menuBar) }
    set { setTrigger(.menuBar, on: newValue) }
  }

  var showsInQuickAccess: Bool {
    get { triggers.contains(.quickAccessAction) }
    set { setTrigger(.quickAccessAction, on: newValue) }
  }

  var showsInHistory: Bool {
    get { triggers.contains(.historyAction) }
    set { setTrigger(.historyAction, on: newValue) }
  }

  private mutating func setTrigger(_ trigger: AutomationTrigger, on: Bool) {
    triggers.removeAll { $0 == trigger }
    if on { triggers.append(trigger) }
  }

  /// True when the source starts a capture (so a hotkey or menu item can run it alone).
  var startsCapture: Bool {
    captureSpec != nil
  }

  var captureSpec: AutomationCaptureSpec? {
    guard case .capture(let spec) = source else { return nil }
    return spec
  }

  /// Supported, enabled step actions in run order.
  var activeActions: [AutomationStepAction] {
    steps.compactMap { $0.isEnabled ? $0.action : nil }
  }

  func contains(_ kind: AutomationStepKind) -> Bool {
    activeActions.contains { $0.kind == kind }
  }

  /// True when this build cannot run the source (it was written by a newer Snapzy).
  var hasUnsupportedSource: Bool {
    if case .unsupported = source { return true }
    return false
  }

  /// Sanitized copy: trimmed name, one step per kind, Copy Image always before
  /// Upload so a failed upload still leaves the image on the clipboard, and at
  /// least one step.
  func normalized() -> Automation {
    var copy = self
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    copy.name = trimmed.isEmpty
      ? L10n.Automations.defaultName
      : String(trimmed.prefix(Self.maxNameLength))

    var seenKinds = Set<AutomationStepKind>()
    copy.steps = steps.filter { step in
      guard let action = step.action else { return true }
      return seenKinds.insert(action.kind).inserted
    }

    if let uploadIndex = copy.steps.firstIndex(where: { $0.action?.kind == .uploadAndCopyLink }),
       let copyIndex = copy.steps.firstIndex(where: { $0.action?.kind == .copyImage }),
       copyIndex > uploadIndex
    {
      let copyStep = copy.steps.remove(at: copyIndex)
      copy.steps.insert(copyStep, at: uploadIndex)
    }

    if !copy.steps.contains(where: { $0.action != nil }) {
      copy.steps.insert(AutomationStep(.copyImage), at: 0)
    }

    var keptHotkey = false
    var seenSimple = Set<String>()
    let isInput = source == .input
    copy.triggers = triggers.filter { trigger in
      switch trigger {
      case .hotkey:
        // An input automation has no file to run on when started from a shortcut.
        guard !isInput else { return false }
        defer { keptHotkey = true }
        return !keptHotkey
      case .menuBar where isInput:
        return false
      case .menuBar, .quickAccessAction, .historyAction:
        return seenSimple.insert(trigger.simpleKind ?? "").inserted
      case .unsupported:
        return true
      }
    }
    return copy
  }

  /// Name shown in the UI: built-in presets follow the app language until renamed.
  var displayName: String {
    if let presetID, let preset = AutomationPreset(rawValue: presetID), name == preset.storedName {
      return preset.localizedName
    }
    return name
  }
}

extension Automation: Codable {
  private enum CodingKeys: String, CodingKey {
    case id, name, symbol, isEnabled, triggers, source, steps, externalInvocation, presetID, schemaVersion
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = (try? container.decode(String.self, forKey: .name)) ?? ""
    symbol = try? container.decodeIfPresent(String.self, forKey: .symbol)
    isEnabled = (try? container.decode(Bool.self, forKey: .isEnabled)) ?? true
    triggers = (try? container.decode([AutomationTrigger].self, forKey: .triggers)) ?? []
    source = try container.decode(AutomationSource.self, forKey: .source)
    steps = (try? container.decode([AutomationStep].self, forKey: .steps)) ?? []
    externalInvocation = (try? container.decode(Bool.self, forKey: .externalInvocation)) ?? false
    presetID = try? container.decodeIfPresent(String.self, forKey: .presetID)
    schemaVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? Self.currentSchemaVersion
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encodeIfPresent(symbol, forKey: .symbol)
    try container.encode(isEnabled, forKey: .isEnabled)
    try container.encode(triggers, forKey: .triggers)
    try container.encode(source, forKey: .source)
    try container.encode(steps, forKey: .steps)
    try container.encode(externalInvocation, forKey: .externalInvocation)
    try container.encodeIfPresent(presetID, forKey: .presetID)
    try container.encode(schemaVersion, forKey: .schemaVersion)
  }
}
