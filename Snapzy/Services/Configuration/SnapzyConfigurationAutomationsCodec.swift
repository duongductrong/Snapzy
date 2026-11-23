//
//  SnapzyConfigurationAutomationsCodec.swift
//  Snapzy
//
//  `[automations.<id>]` tables in config.toml. One keyed table per automation
//  (the TOML parser has no arrays of tables); `order` keeps the list order.
//
//    [automations.8f0c…]
//    order = 0
//    name = "Cloud Share"
//    preset = "cloud-share"
//    enabled = true
//    capture = "area"
//    save_to_export = false
//    steps = ["copy_image", "upload_copy_link:markdown", "notify"]
//    shortcut_key = "4"
//    shortcut_modifiers = ["control", "shift"]
//    data = "{…}"   # full JSON; keeps what the flat keys can't (disabled or
//                   # newer steps, failure policy). Flat keys win when edited.
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
      guard let spec = automation.captureSpec else { continue }
      if let presetID = automation.presetID {
        writer.value("preset", presetID)
      }
      writer.value("enabled", automation.isEnabled)
      writer.value("capture", captureToken(spec.mode))
      writer.value("save_to_export", spec.saveToExportDirectory)
      writer.stringArray("steps", automation.activeActions.map(stepToken))
      if let hotkey = automation.hotkey {
        writer.value("shortcut_key", SnapzyConfigurationShortcutCodec.exportKey(hotkey))
        writer.stringArray("shortcut_modifiers", SnapzyConfigurationShortcutCodec.exportModifiers(hotkey))
      }
      writer.value("external_invocation", automation.externalInvocation)
    }
  }

  // MARK: - Import

  struct ParseResult {
    /// `nil` when the file has no `[automations]` section: leave automations untouched.
    let automations: [Automation]?
    let warnings: [String]
  }

  @MainActor
  static func parse(_ document: SimpleTOMLDocument) -> ParseResult {
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
      if let captureRaw = fields["capture"]?.stringValue, let mode = captureMode(captureRaw) {
        source = .capture(AutomationCaptureSpec(
          mode: mode,
          saveToExportDirectory: fields["save_to_export"]?.boolValue ?? base?.captureSpec?.saveToExportDirectory ?? false
        ))
      } else if let base, base.hasUnsupportedSource, fields["capture"] == nil {
        source = base.source  // written by a newer Snapzy; keep as is
      } else {
        warnings.append("\(path).capture must be one of area, fullscreen, active_window, application_window; skipped")
        continue
      }

      var tokens: [String] = []
      for token in fields["steps"]?.stringArrayValue ?? [] {
        if stepAction(token) != nil {
          tokens.append(token.lowercased())
        } else {
          warnings.append("\(path).steps: unknown step \"\(token)\" ignored")
        }
      }
      let steps: [AutomationStep]
      if let base, fields["steps"] == nil || tokens == base.activeActions.map(stepToken) {
        steps = base.steps  // unchanged: keep disabled/newer steps and failure policies
      } else {
        steps = tokens.compactMap(stepAction).map { AutomationStep($0) }
      }

      var automation = base ?? Automation(name: "", source: source, steps: [])
      automation.id = id
      automation.name = fields["name"]?.stringValue ?? base?.name ?? ""
      automation.isEnabled = fields["enabled"]?.boolValue ?? base?.isEnabled ?? true
      automation.source = source
      automation.steps = steps
      automation.externalInvocation = fields["external_invocation"]?.boolValue ?? base?.externalInvocation ?? false
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

      parsed.append((fields["order"]?.intValue ?? Int.max, automation.normalized()))
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

  static func captureToken(_ mode: AutomationCaptureMode) -> String {
    switch mode {
    case .area: "area"
    case .fullscreen: "fullscreen"
    case .activeWindow: "active_window"
    case .applicationWindow: "application_window"
    }
  }

  static func captureMode(_ token: String) -> AutomationCaptureMode? {
    AutomationCaptureMode.allCases.first { captureToken($0) == token.lowercased() }
  }

  static func stepToken(_ action: AutomationStepAction) -> String {
    switch action {
    case .copyImage: "copy_image"
    case .uploadAndCopyLink(.url): "upload_copy_link"
    case .uploadAndCopyLink(.markdown): "upload_copy_link:markdown"
    case .showQuickAccess: "show_quick_access"
    case .openAnnotate: "open_annotate"
    case .notify: "notify"
    }
  }

  static func stepAction(_ token: String) -> AutomationStepAction? {
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
