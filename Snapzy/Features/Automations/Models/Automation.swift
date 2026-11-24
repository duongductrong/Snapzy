//
//  Automation.swift
//  Snapzy
//
//  Persisted automation model: triggers + source + ordered steps.
//  Schema 2 (milestone 3): steps carry a typed `config`, can repeat and run in
//  any order; sources add recordings, scrolling captures and the clipboard.
//  Every enum keeps unknown cases as `.unsupported` so automations written by a
//  newer Snapzy survive a round trip through this build.
//

import Foundation

// MARK: - Capture source

enum AutomationCaptureMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case area
  case fullscreen
  case activeWindow
  case applicationWindow
  case recordingArea
  case recordingWindow
  case scrolling

  var id: String { rawValue }

  var isRecording: Bool {
    self == .recordingArea || self == .recordingWindow
  }
}

/// What a recording source hands to the steps.
enum AutomationRecordingOutput: String, Codable, CaseIterable, Identifiable, Sendable {
  case video
  case gif

  var id: String { rawValue }
}

struct AutomationCaptureSpec: Codable, Equatable, Sendable {
  var mode: AutomationCaptureMode
  /// `false` writes the capture into the temp capture directory, like turning
  /// off the after-capture Save action.
  var saveToExportDirectory: Bool
  /// Recording sources only; ignored for screenshots.
  var recordingOutput: AutomationRecordingOutput

  init(mode: AutomationCaptureMode, saveToExportDirectory: Bool, recordingOutput: AutomationRecordingOutput = .video) {
    self.mode = mode
    self.saveToExportDirectory = saveToExportDirectory
    self.recordingOutput = recordingOutput
  }
}

enum AutomationSource: Equatable {
  case capture(AutomationCaptureSpec)
  /// Runs only on files handed in by the trigger (Quick Access, History, CLI,
  /// Shortcuts). Never starts a capture, so it has no hotkey or menu bar item.
  case input
  /// The image on the clipboard, saved as a new capture when the run starts.
  case clipboardImage
  case unsupported(AutomationJSONValue)
}

extension AutomationSource: Codable {
  private enum CodingKeys: String, CodingKey {
    case kind, mode, saveToExportDirectory, recordingOutput
  }

  init(from decoder: Decoder) throws {
    let raw = try AutomationJSONValue(from: decoder)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try? container.decode(String.self, forKey: .kind)
    if kind == "capture",
       let mode = try? container.decode(AutomationCaptureMode.self, forKey: .mode)
    {
      self = .capture(AutomationCaptureSpec(
        mode: mode,
        saveToExportDirectory: container.value(.saveToExportDirectory, default: false),
        recordingOutput: container.value(.recordingOutput, default: .video)
      ))
    } else if kind == "input" {
      self = .input
    } else if kind == "clipboardImage" {
      self = .clipboardImage
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
      if spec.mode.isRecording {
        try container.encode(spec.recordingOutput, forKey: .recordingOutput)
      }
    case .input:
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode("input", forKey: .kind)
    case .clipboardImage:
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode("clipboardImage", forKey: .kind)
    case .unsupported(let raw):
      try raw.encode(to: encoder)
    }
  }
}

extension AutomationSource {
  /// Payload kinds the first step receives. `.input` assumes any file kind:
  /// the real kinds are only known when a file is handed in.
  var initialPayloadKinds: Set<AutomationPayloadKind> {
    switch self {
    case .capture(let spec):
      guard spec.mode.isRecording else { return [.image] }
      return spec.recordingOutput == .gif ? [.gif] : [.video]
    case .clipboardImage: return [.image]
    case .input, .unsupported: return AutomationPayloadKind.files
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
  /// Offered by Finder's "Run Snapzy Automation…" service and when files are
  /// dropped on the menu bar icon (milestone 5).
  case finderQuickAction
  /// A button in the unified capture toolbar (milestone 6, #498).
  case captureToolbar
  case unsupported(AutomationJSONValue)

  /// Stored kinds without a payload, keyed by their JSON `kind`.
  fileprivate static let simpleKinds: [String: AutomationTrigger] = [
    "menuBar": .menuBar,
    "quickAccessAction": .quickAccessAction,
    "historyAction": .historyAction,
    "finderQuickAction": .finderQuickAction,
    "captureToolbar": .captureToolbar,
  ]

  fileprivate var simpleKind: String? {
    switch self {
    case .menuBar: "menuBar"
    case .quickAccessAction: "quickAccessAction"
    case .historyAction: "historyAction"
    case .finderQuickAction: "finderQuickAction"
    case .captureToolbar: "captureToolbar"
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
    case .menuBar, .quickAccessAction, .historyAction, .finderQuickAction, .captureToolbar:
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(simpleKind, forKey: .kind)
    case .unsupported(let raw):
      try raw.encode(to: encoder)
    }
  }
}

// MARK: - Steps

/// Milestone 1 link format, kept to decode `uploadAndCopyLink` steps.
enum AutomationLinkFormat: String, Codable, CaseIterable, Identifiable, Sendable {
  /// `https://…/file.png`
  case url
  /// `![file](https://…/file.png)`
  case markdown

  var id: String { rawValue }
}

enum AutomationFailurePolicy: String, Codable, CaseIterable, Identifiable, Sendable {
  case stop
  case `continue`

  var id: String { rawValue }
}

/// What a step does, with its settings.
enum AutomationStepAction: Equatable {
  // Milestone 1
  case copyImage
  case showQuickAccess
  case openAnnotate
  case notify
  /// Milestone 1 combined step; migrated to `upload` + `copyLink` on load.
  case uploadAndCopyLink(AutomationLinkFormat)
  // Transform
  case applyCanvasPreset(AutomationCanvasPresetConfig)
  case resize(AutomationResizeConfig)
  case convert(AutomationConvertConfig)
  case stripMetadata
  case ocr(AutomationOCRConfig)
  case translate(AutomationTranslateConfig)
  case convertToGIF(AutomationGIFConfig)
  // Deliver
  case upload(AutomationUploadConfig)
  case copyLink(AutomationLinkTemplate)
  case copyText(AutomationTextTemplate)
  case copyFile
  case saveToFolder(AutomationSaveToFolderConfig)
  case reveal
  case pin
  // Integrations (milestone 4)
  case webhook(AutomationWebhookConfig)
  case runScript(AutomationRunScriptConfig)
  case runShortcut(AutomationRunShortcutConfig)
  case shareSheet(AutomationShareSheetConfig)
  case openInApp(AutomationOpenInAppConfig)
  // Control (milestone 5)
  case condition(AutomationConditionConfig)
  case stop
  case runAutomation(AutomationRunAutomationConfig)
  case ask(AutomationAskConfig)
  // AI (milestone 6)
  case redact(AutomationRedactConfig)
  case aiAnnotate(AutomationAIAnnotateConfig)

  var kind: AutomationStepKind {
    switch self {
    case .copyImage: .copyImage
    case .showQuickAccess: .showQuickAccess
    case .openAnnotate: .openAnnotate
    case .notify: .notify
    case .uploadAndCopyLink: .uploadAndCopyLink
    case .applyCanvasPreset: .applyCanvasPreset
    case .resize: .resize
    case .convert: .convert
    case .stripMetadata: .stripMetadata
    case .ocr: .ocr
    case .translate: .translate
    case .convertToGIF: .convertToGIF
    case .upload: .upload
    case .copyLink: .copyLink
    case .copyText: .copyText
    case .copyFile: .copyFile
    case .saveToFolder: .saveToFolder
    case .reveal: .reveal
    case .pin: .pin
    case .webhook: .webhook
    case .runScript: .runScript
    case .runShortcut: .runShortcut
    case .shareSheet: .shareSheet
    case .openInApp: .openInApp
    case .condition: .condition
    case .stop: .stop
    case .runAutomation: .runAutomation
    case .ask: .ask
    case .redact: .redact
    case .aiAnnotate: .aiAnnotate
    }
  }

  /// Automations this step runs (Run Automation target, Ask choices).
  var referencedAutomationIDs: [UUID] {
    switch self {
    case .runAutomation(let config): config.automationID.map { [$0] } ?? []
    case .ask(let config): config.referencedAutomationIDs
    default: []
    }
  }
}

enum AutomationStepKind: String, Codable, CaseIterable, Identifiable, Sendable {
  case copyImage
  case uploadAndCopyLink
  case showQuickAccess
  case openAnnotate
  case notify
  case applyCanvasPreset
  case resize
  case convert
  case stripMetadata
  case ocr
  case translate
  case convertToGIF
  case upload
  case copyLink
  case copyText
  case copyFile
  case saveToFolder
  case reveal
  case pin
  case webhook
  case runScript
  case runShortcut
  case shareSheet
  case openInApp
  case condition
  case stop
  case runAutomation
  case ask
  case redact
  case aiAnnotate

  var id: String { rawValue }

  /// Steps the runner handles itself: they steer the run instead of acting on the payload.
  var isControl: Bool {
    self == .condition || self == .stop || self == .runAutomation || self == .ask
  }

  /// Kinds that are only read from old data and never offered in the editor.
  var isLegacy: Bool { self == .uploadAndCopyLink }

  /// The step a new "Add Step" item inserts.
  var defaultAction: AutomationStepAction {
    switch self {
    case .copyImage: .copyImage
    case .uploadAndCopyLink: .uploadAndCopyLink(.url)
    case .showQuickAccess: .showQuickAccess
    case .openAnnotate: .openAnnotate
    case .notify: .notify
    case .applyCanvasPreset: .applyCanvasPreset(AutomationCanvasPresetConfig())
    case .resize: .resize(AutomationResizeConfig())
    case .convert: .convert(AutomationConvertConfig())
    case .stripMetadata: .stripMetadata
    case .ocr: .ocr(AutomationOCRConfig())
    case .translate: .translate(AutomationTranslateConfig())
    case .convertToGIF: .convertToGIF(AutomationGIFConfig())
    case .upload: .upload(AutomationUploadConfig())
    case .copyLink: .copyLink(AutomationLinkTemplate())
    case .copyText: .copyText(AutomationTextTemplate())
    case .copyFile: .copyFile
    case .saveToFolder: .saveToFolder(AutomationSaveToFolderConfig())
    case .reveal: .reveal
    case .pin: .pin
    case .webhook: .webhook(AutomationWebhookConfig())
    case .runScript: .runScript(AutomationRunScriptConfig())
    case .runShortcut: .runShortcut(AutomationRunShortcutConfig())
    case .shareSheet: .shareSheet(AutomationShareSheetConfig())
    case .openInApp: .openInApp(AutomationOpenInAppConfig())
    case .condition: .condition(AutomationConditionConfig(predicates: [.frontmostApp(bundleIDs: [], negate: false)]))
    case .stop: .stop
    case .runAutomation: .runAutomation(AutomationRunAutomationConfig())
    case .ask: .ask(AutomationAskConfig())
    case .redact: .redact(AutomationRedactConfig())
    case .aiAnnotate: .aiAnnotate(AutomationAIAnnotateConfig())
    }
  }
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
    get {
      guard case .action(let action) = content else { return nil }
      return action
    }
    set {
      if let newValue { content = .action(newValue) }
    }
  }

  /// `uploadAndCopyLink` becomes `upload` (same id) + `copyLink` (new id).
  var migrated: [AutomationStep] {
    guard case .uploadAndCopyLink(let format)? = action else { return [self] }
    var upload = self
    upload.content = .action(.upload(AutomationUploadConfig()))
    var copy = self
    copy.id = Self.derivedID(from: id)
    copy.content = .action(.copyLink(AutomationLinkTemplate(format)))
    return [upload, copy]
  }

  /// Stable id for the step split off a migrated one, so loading the same stored
  /// automation twice yields equal values.
  private static func derivedID(from id: UUID) -> UUID {
    var bytes = id.uuid
    bytes.15 ^= 0x5A
    bytes.14 ^= 0xC3
    return UUID(uuid: bytes)
  }
}

extension AutomationStep: Codable {
  private enum CodingKeys: String, CodingKey {
    case id, kind, format, config, isEnabled, onFailure
  }

  init(from decoder: Decoder) throws {
    let raw = try AutomationJSONValue(from: decoder)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = container.value(.id, default: UUID())
    isEnabled = container.value(.isEnabled, default: true)
    onFailure = container.value(.onFailure, default: .stop)

    let kindRaw = try? container.decode(String.self, forKey: .kind)
    guard let kind = kindRaw.flatMap(AutomationStepKind.init(rawValue:)) else {
      content = .unsupported(raw)
      return
    }

    func config<T: Decodable>(_ fallback: T) -> T {
      container.value(.config, default: fallback)
    }

    let action: AutomationStepAction = switch kind {
    case .copyImage: .copyImage
    case .showQuickAccess: .showQuickAccess
    case .openAnnotate: .openAnnotate
    case .notify: .notify
    case .uploadAndCopyLink: .uploadAndCopyLink(container.value(.format, default: .url))
    case .applyCanvasPreset: .applyCanvasPreset(config(AutomationCanvasPresetConfig()))
    case .resize: .resize(config(AutomationResizeConfig()))
    case .convert: .convert(config(AutomationConvertConfig()))
    case .stripMetadata: .stripMetadata
    case .ocr: .ocr(config(AutomationOCRConfig()))
    case .translate: .translate(config(AutomationTranslateConfig()))
    case .convertToGIF: .convertToGIF(config(AutomationGIFConfig()))
    case .upload: .upload(config(AutomationUploadConfig()))
    case .copyLink: .copyLink(config(AutomationLinkTemplate()))
    case .copyText: .copyText(config(AutomationTextTemplate()))
    case .copyFile: .copyFile
    case .saveToFolder: .saveToFolder(config(AutomationSaveToFolderConfig()))
    case .reveal: .reveal
    case .pin: .pin
    case .webhook: .webhook(config(AutomationWebhookConfig()))
    case .runScript: .runScript(config(AutomationRunScriptConfig()))
    case .runShortcut: .runShortcut(config(AutomationRunShortcutConfig()))
    case .shareSheet: .shareSheet(config(AutomationShareSheetConfig()))
    case .openInApp: .openInApp(config(AutomationOpenInAppConfig()))
    case .condition: .condition(config(AutomationConditionConfig()))
    case .stop: .stop
    case .runAutomation: .runAutomation(config(AutomationRunAutomationConfig()))
    case .ask: .ask(config(AutomationAskConfig()))
    case .redact: .redact(config(AutomationRedactConfig()))
    case .aiAnnotate: .aiAnnotate(config(AutomationAIAnnotateConfig()))
    }
    content = .action(action)
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
    switch action {
    case .uploadAndCopyLink(let format): try container.encode(format, forKey: .format)
    case .applyCanvasPreset(let config): try container.encode(config, forKey: .config)
    case .resize(let config): try container.encode(config, forKey: .config)
    case .convert(let config): try container.encode(config, forKey: .config)
    case .ocr(let config): try container.encode(config, forKey: .config)
    case .translate(let config): try container.encode(config, forKey: .config)
    case .convertToGIF(let config): try container.encode(config, forKey: .config)
    case .copyLink(let config): try container.encode(config, forKey: .config)
    case .copyText(let config): try container.encode(config, forKey: .config)
    case .saveToFolder(let config): try container.encode(config, forKey: .config)
    case .upload(let config): try container.encode(config, forKey: .config)
    case .webhook(let config): try container.encode(config, forKey: .config)
    case .runScript(let config): try container.encode(config, forKey: .config)
    case .runShortcut(let config): try container.encode(config, forKey: .config)
    case .shareSheet(let config): try container.encode(config, forKey: .config)
    case .openInApp(let config): try container.encode(config, forKey: .config)
    case .condition(let config): try container.encode(config, forKey: .config)
    case .runAutomation(let config): try container.encode(config, forKey: .config)
    case .ask(let config): try container.encode(config, forKey: .config)
    case .redact(let config): try container.encode(config, forKey: .config)
    case .aiAnnotate(let config): try container.encode(config, forKey: .config)
    case .copyImage, .showQuickAccess, .openAnnotate, .notify, .stripMetadata,
         .copyFile, .reveal, .pin, .stop:
      break
    }
    try container.encode(isEnabled, forKey: .isEnabled)
    try container.encode(onFailure, forKey: .onFailure)
  }
}

// MARK: - Automation

struct Automation: Identifiable, Equatable {
  /// 2: steps carry a `config` object; `uploadAndCopyLink` split into `upload` + `copyLink`.
  static let currentSchemaVersion = 2
  static let maxNameLength = 60
  static let maxSteps = 20

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
  /// Imported (config file / recipe) with network or script steps the user has
  /// not looked at yet. Refused at launch until saved from the editor.
  var needsReview: Bool
  /// Second opt-in: the URL scheme and Shortcuts may run this automation even
  /// though it contains script / Shortcut steps. Never imported.
  var allowExternalCode: Bool

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
    schemaVersion: Int = Automation.currentSchemaVersion,
    needsReview: Bool = false,
    allowExternalCode: Bool = false
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
    self.needsReview = needsReview
    self.allowExternalCode = allowExternalCode
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

  /// Offered by Finder's "Run Snapzy Automation…" and menu bar icon drops.
  var showsInFinder: Bool {
    get { triggers.contains(.finderQuickAction) }
    set { setTrigger(.finderQuickAction, on: newValue) }
  }

  /// A button in the unified capture toolbar (milestone 6).
  var showsInCaptureToolbar: Bool {
    get { triggers.contains(.captureToolbar) }
    set { setTrigger(.captureToolbar, on: newValue) }
  }

  private mutating func setTrigger(_ trigger: AutomationTrigger, on: Bool) {
    triggers.removeAll { $0 == trigger }
    if on { triggers.append(trigger) }
  }

  /// True when the source starts a capture (so a hotkey or menu item can run it alone).
  var startsCapture: Bool {
    captureSpec != nil
  }

  /// True when the automation can run without a handed-in file (capture or clipboard).
  var runsWithoutInput: Bool {
    startsCapture || source == .clipboardImage
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

  /// Steps in the current schema: legacy `uploadAndCopyLink` split in two.
  func migrated() -> Automation {
    var copy = self
    copy.steps = steps.flatMap(\.migrated)
    copy.schemaVersion = max(schemaVersion, Self.currentSchemaVersion)
    return copy
  }

  /// Sanitized copy: trimmed name, current schema, at most `maxSteps` steps and
  /// at least one, and only triggers the source can use. Steps keep the user's
  /// order and may repeat; `AutomationChainValidator` checks the chain.
  func normalized() -> Automation {
    var copy = migrated()
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    copy.name = trimmed.isEmpty
      ? L10n.Automations.defaultName
      : String(trimmed.prefix(Self.maxNameLength))

    if copy.steps.count > Self.maxSteps {
      copy.steps = Array(copy.steps.prefix(Self.maxSteps))
    }
    // A default after-capture automation may legitimately do nothing (every matrix cell off).
    if !copy.isSystemDefault, !copy.steps.contains(where: { $0.action != nil }) {
      copy.steps.insert(AutomationStep(.copyImage), at: 0)
    }
    if copy.isSystemDefault {
      // Runs on every standard capture: no triggers, always on, never external.
      copy.triggers = []
      copy.isEnabled = true
      copy.externalInvocation = false
      copy.allowExternalCode = false
      return copy
    }

    // The second opt-in only means something while the first is on.
    if !copy.externalInvocation { copy.allowExternalCode = false }

    var keptHotkey = false
    var seenSimple = Set<String>()
    let needsInput = !copy.runsWithoutInput && !copy.hasUnsupportedSource
    copy.triggers = triggers.filter { trigger in
      switch trigger {
      case .hotkey:
        // An input automation has no file to run on when started from a shortcut.
        guard !needsInput else { return false }
        defer { keptHotkey = true }
        return !keptHotkey
      case .menuBar where needsInput:
        return false
      case .menuBar, .quickAccessAction, .historyAction, .finderQuickAction, .captureToolbar:
        return seenSimple.insert(trigger.simpleKind ?? "").inserted
      case .unsupported:
        return true
      }
    }
    return copy
  }

  /// Name shown in the UI: built-in presets follow the app language until renamed.
  var displayName: String {
    if let type = systemCaptureType, name == AutomationSystemDefault.storedName(for: type) {
      return AutomationSystemDefault.localizedName(for: type)
    }
    if let presetID, let preset = AutomationPreset(rawValue: presetID), name == preset.storedName {
      return preset.localizedName
    }
    return name
  }
}

extension Automation: Codable {
  private enum CodingKeys: String, CodingKey {
    case id, name, symbol, isEnabled, triggers, source, steps, externalInvocation, presetID, schemaVersion
    case needsReview, allowExternalCode
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
    schemaVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? 1
    needsReview = (try? container.decode(Bool.self, forKey: .needsReview)) ?? false
    allowExternalCode = (try? container.decode(Bool.self, forKey: .allowExternalCode)) ?? false
    // Older data is migrated in memory; it is written back in the current schema.
    if schemaVersion < Self.currentSchemaVersion || steps.contains(where: { $0.action?.kind == .uploadAndCopyLink }) {
      self = migrated()
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encodeIfPresent(symbol, forKey: .symbol)
    try container.encode(isEnabled, forKey: .isEnabled)
    try container.encode(triggers, forKey: .triggers)
    try container.encode(source, forKey: .source)
    try container.encode(steps.flatMap(\.migrated), forKey: .steps)
    try container.encode(externalInvocation, forKey: .externalInvocation)
    try container.encodeIfPresent(presetID, forKey: .presetID)
    try container.encode(max(schemaVersion, Self.currentSchemaVersion), forKey: .schemaVersion)
    if needsReview { try container.encode(true, forKey: .needsReview) }
    if allowExternalCode { try container.encode(true, forKey: .allowExternalCode) }
  }
}
