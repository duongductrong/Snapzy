//
//  SnapzyConfigurationAutomationsCodec.swift
//  Snapzy
//
//  `[automations.<id>]` tables in config.toml. One keyed table per automation
//  (the TOML parser has no arrays of tables); `order` keeps the list order.
//  Steps are keyed sub-tables `[automations.<id>.steps.<nn>]` in run order.
//  `capture = "input"` runs on a handed-in file, `capture = "clipboard"` on the
//  clipboard image (`save_to_export` and shortcuts don't apply to input).
//
//    [automations.8f0c…]
//    order = 0
//    name = "Docs Shot"
//    preset = "docs-shot"
//    enabled = true
//    capture = "active_window"
//    save_to_export = false
//    shortcut_key = "4"
//    shortcut_modifiers = ["control", "shift"]
//    menu_bar = false
//    quick_access = true
//    history = true
//    external_invocation = false
//    data = "{…}"   # full JSON; keeps what the keys can't (newer steps or
//                   # sources). Keys win when edited.
//
//    [automations.8f0c….steps.01]
//    kind = "resize"
//    max_dimension = 1600
//
//    [automations.8f0c….steps.02]
//    kind = "save_to_folder"
//    folder = "~/repo/docs/img"   # or "export"; a bookmark is created on import
//    name = "{date}-{appName}"
//
//  Milestone 1 files used `steps = ["copy_image", "upload_copy_link:markdown"]`;
//  that form is still read.
//

import Foundation

enum SnapzyConfigurationAutomationsCodec {
  static let sectionName = "automations"

  // MARK: - Export

  @MainActor
  static func write(_ automations: [Automation], to writer: inout SimpleTOMLWriter) {
    // Always present, so an empty list round-trips as "no automations".
    writer.section(sectionName)
    for (index, automation) in automations.enumerated() {
      writer.section("\(sectionName).\(automation.id.uuidString.lowercased())")
      writer.value("order", index)
      writer.value("name", automation.name)
      if let data = try? JSONEncoder().encode(automation), let json = String(data: data, encoding: .utf8) {
        writer.value("data", json)
      }
      let captureValue: String
      switch automation.source {
      case .capture(let spec): captureValue = captureToken(spec.mode)
      case .input: captureValue = inputToken
      case .clipboardImage: captureValue = clipboardToken
      case .unsupported: continue
      }
      if let presetID = automation.presetID {
        writer.value("preset", presetID)
      }
      writer.value("enabled", automation.isEnabled)
      writer.value("capture", captureValue)
      if let spec = automation.captureSpec {
        writer.value("save_to_export", spec.saveToExportDirectory)
        if spec.mode.isRecording {
          writer.value("recording_output", spec.recordingOutput.rawValue)
        }
      }
      if let hotkey = automation.hotkey {
        writer.value("shortcut_key", SnapzyConfigurationShortcutCodec.exportKey(hotkey))
        writer.stringArray("shortcut_modifiers", SnapzyConfigurationShortcutCodec.exportModifiers(hotkey))
      }
      writer.value("menu_bar", automation.showsInMenuBar)
      writer.value("quick_access", automation.showsInQuickAccess)
      writer.value("history", automation.showsInHistory)
      writer.value("external_invocation", automation.externalInvocation)

      for (stepIndex, step) in automation.steps.flatMap(\.migrated).enumerated() {
        writer.section("\(sectionName).\(automation.id.uuidString.lowercased()).steps.\(stepKey(stepIndex))")
        SnapzyConfigurationAutomationStepCodec.write(step, to: &writer)
      }
    }
  }

  /// `01`, `02`, … so keys sort in run order.
  static func stepKey(_ index: Int) -> String {
    String(format: "%02d", index + 1)
  }

  // MARK: - Import

  struct ParseResult {
    /// `nil` when the file has no `[automations]` section: leave automations untouched.
    let automations: [Automation]?
    let warnings: [String]
  }

  @MainActor
  static func parse(
    _ document: SimpleTOMLDocument,
    folderStore: AutomationFolderAccessStore? = nil,
    storedAutomation: ((UUID) -> Automation?)? = nil
  ) -> ParseResult {
    // The review baseline is what this Mac already has, never the file's own `data`.
    let storedAutomation = storedAutomation ?? { AutomationStore.shared.automation(id: $0) }
    let folderStore = folderStore ?? .shared
    guard let section = document.value(at: [sectionName]) else {
      return ParseResult(automations: nil, warnings: [])
    }
    guard case .table(let tables) = section else {
      return ParseResult(automations: nil, warnings: ["\(sectionName) must be a table of automations"])
    }

    var warnings: [String] = []
    var parsed: [(order: Int, automation: Automation)] = []

    for key in tables.keys.sorted() {
      let path = "\(sectionName).\(key)"
      guard case .table(let fields)? = tables[key] else {
        warnings.append("\(path) must be a table; skipped")
        continue
      }
      let base: Automation? = fields["data"]?.stringValue
        .flatMap { try? JSONDecoder().decode(Automation.self, from: Data($0.utf8)) }
      let id = UUID(uuidString: key) ?? base?.id ?? UUID()

      let source: AutomationSource
      if fields["capture"]?.stringValue?.lowercased() == inputToken {
        source = .input
      } else if fields["capture"]?.stringValue?.lowercased() == clipboardToken {
        source = .clipboardImage
      } else if let captureRaw = fields["capture"]?.stringValue, let mode = captureMode(captureRaw) {
        source = .capture(AutomationCaptureSpec(
          mode: mode,
          saveToExportDirectory: fields["save_to_export"]?.boolValue ?? base?.captureSpec?.saveToExportDirectory ?? false,
          recordingOutput: fields["recording_output"]?.stringValue.flatMap(AutomationRecordingOutput.init(rawValue:))
            ?? base?.captureSpec?.recordingOutput ?? .video
        ))
      } else if let base, base.hasUnsupportedSource, fields["capture"] == nil {
        source = base.source  // written by a newer Snapzy; keep as is
      } else {
        warnings.append("\(path).capture must be one of \(captureTokens.joined(separator: ", ")); skipped")
        continue
      }

      let steps: [AutomationStep]
      if case .table(let stepTables)? = fields["steps"] {
        var parsedSteps: [AutomationStep] = []
        for stepKey in stepTables.keys.sorted() {
          guard case .table(let stepFields)? = stepTables[stepKey] else {
            warnings.append("\(path).steps.\(stepKey) must be a table; skipped")
            continue
          }
          let result = SnapzyConfigurationAutomationStepCodec.parse(
            stepFields,
            path: "\(path).steps.\(stepKey)",
            folderStore: folderStore
          )
          warnings.append(contentsOf: result.warnings)
          guard var step = result.step else { continue }
          // Keep the stored id when the step at this position is the same kind.
          let index = parsedSteps.count
          if let baseSteps = base?.steps, baseSteps.indices.contains(index),
             baseSteps[index].action?.kind == step.action?.kind
          {
            step.id = baseSteps[index].id
          }
          parsedSteps.append(step)
        }
        steps = parsedSteps
      } else if let tokenValues = fields["steps"]?.stringArrayValue {
        var tokens: [String] = []
        for token in tokenValues {
          if legacyStepAction(token) != nil {
            tokens.append(token.lowercased())
          } else {
            warnings.append("\(path).steps: unknown step \"\(token)\" ignored")
          }
        }
        steps = tokens.compactMap(legacyStepAction).map { AutomationStep($0) }
      } else if let base {
        steps = base.steps  // keep disabled/newer steps and failure policies
      } else {
        steps = []
      }

      var automation = base ?? Automation(name: "", source: source, steps: [])
      automation.id = id
      automation.name = fields["name"]?.stringValue ?? base?.name ?? ""
      automation.isEnabled = fields["enabled"]?.boolValue ?? base?.isEnabled ?? true
      automation.source = source
      automation.steps = steps
      automation.externalInvocation = fields["external_invocation"]?.boolValue ?? base?.externalInvocation ?? false
      if fields["external_invocation"]?.boolValue == true {
        // The user's own dotfile may opt in; logged so an unexpected opt-in is traceable.
        DiagnosticLogger.shared.log(
          .info,
          .action,
          "Automation imported with external invocation allowed",
          context: ["automation": id.uuidString]
        )
      }
      if let menuBar = fields["menu_bar"]?.boolValue {
        automation.showsInMenuBar = menuBar
      }
      if let quickAccess = fields["quick_access"]?.boolValue {
        automation.showsInQuickAccess = quickAccess
      }
      if let history = fields["history"]?.boolValue {
        automation.showsInHistory = history
      }
      automation.presetID = fields["preset"]?.stringValue.flatMap { AutomationPreset(rawValue: $0)?.rawValue }
        ?? (fields["preset"] == nil ? base?.presetID : nil)
      if automation.symbol == nil {
        automation.symbol = automation.presetID.flatMap(AutomationPreset.init(rawValue:))?.symbol
      }
      if base != nil, fields["shortcut_key"] == nil {
        automation.hotkey = nil
      }

      if let keyName = fields["shortcut_key"]?.stringValue, !keyName.isEmpty {
        let modifiers = fields["shortcut_modifiers"]?.stringArrayValue ?? []
        if let shortcut = SnapzyConfigurationShortcutCodec.shortcut(key: keyName, modifiers: modifiers, requireModifier: true) {
          automation.hotkey = shortcut
        } else {
          warnings.append("\(path): shortcut \"\(keyName)\" with \(modifiers) is invalid; left unbound")
        }
      }

      // Network / script steps the file added or changed wait for a review in the
      // editor before they can run; the second external opt-in is never imported.
      let stored = storedAutomation(id)
      let reviewed = automation.normalized().flaggedForReview(comparedTo: stored)
      if reviewed.needsReview, !(stored?.needsReview ?? false) {
        warnings.append("\(path): has webhook, upload or script steps; open it in Settings → Automations and save to allow it")
      }
      parsed.append((fields["order"]?.intValue ?? Int.max, reviewed))
    }

    var automations = parsed.sorted { $0.order < $1.order }.map(\.automation)
    if automations.count > AutomationStore.maxAutomations {
      warnings.append("Only the first \(AutomationStore.maxAutomations) automations were imported")
      automations = Array(automations.prefix(AutomationStore.maxAutomations))
    }

    var seenHotkeys = Set<String>()
    for index in automations.indices {
      guard let hotkey = automations[index].hotkey else { continue }
      let signature = "\(hotkey.keyCode)-\(hotkey.modifiers)"
      if !seenHotkeys.insert(signature).inserted {
        warnings.append("\(automations[index].name): shortcut already used by another automation; left unbound")
        automations[index].hotkey = nil
      }
    }

    return ParseResult(automations: automations, warnings: warnings)
  }

  // MARK: - Tokens

  /// `capture` value of an automation that runs on a handed-in file.
  static let inputToken = "input"
  /// `capture` value of an automation that runs on the clipboard image.
  static let clipboardToken = "clipboard"

  static var captureTokens: [String] {
    AutomationCaptureMode.allCases.map { captureToken($0) } + [inputToken, clipboardToken]
  }

  static func captureToken(_ mode: AutomationCaptureMode) -> String {
    switch mode {
    case .area: "area"
    case .fullscreen: "fullscreen"
    case .activeWindow: "active_window"
    case .applicationWindow: "application_window"
    case .recordingArea: "recording_area"
    case .recordingWindow: "recording_window"
    case .scrolling: "scrolling"
    }
  }

  static func captureMode(_ token: String) -> AutomationCaptureMode? {
    AutomationCaptureMode.allCases.first { captureToken($0) == token.lowercased() }
  }

  /// Milestone 1 `steps = [...]` tokens.
  static func legacyStepAction(_ token: String) -> AutomationStepAction? {
    switch token.lowercased() {
    case "copy_image": .copyImage
    case "upload_copy_link", "upload_copy_link:url": .uploadAndCopyLink(.url)
    case "upload_copy_link:markdown": .uploadAndCopyLink(.markdown)
    case "show_quick_access": .showQuickAccess
    case "open_annotate": .openAnnotate
    case "notify": .notify
    default: nil
    }
  }
}
