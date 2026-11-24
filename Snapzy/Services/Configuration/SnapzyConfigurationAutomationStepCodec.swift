//
//  SnapzyConfigurationAutomationStepCodec.swift
//  Snapzy
//
//  One `[automations.<id>.steps.<nn>]` table ↔ one `AutomationStep`.
//  Keys are snake_case; unknown keys warn. A step kind this build doesn't
//  know is written as `kind` + `json` and read back unchanged.
//

import Foundation

enum SnapzyConfigurationAutomationStepCodec {
  struct ParseResult {
    let step: AutomationStep?
    let warnings: [String]
  }

  // MARK: - Kind tokens

  static func token(_ kind: AutomationStepKind) -> String {
    switch kind {
    case .copyImage: "copy_image"
    case .uploadAndCopyLink: "upload_copy_link"
    case .showQuickAccess: "show_quick_access"
    case .openAnnotate: "open_annotate"
    case .notify: "notify"
    case .applyCanvasPreset: "apply_canvas_preset"
    case .resize: "resize"
    case .convert: "convert"
    case .stripMetadata: "strip_metadata"
    case .ocr: "ocr"
    case .translate: "translate"
    case .convertToGIF: "convert_to_gif"
    case .upload: "upload"
    case .copyLink: "copy_link"
    case .copyText: "copy_text"
    case .copyFile: "copy_file"
    case .saveToFolder: "save_to_folder"
    case .reveal: "reveal"
    case .pin: "pin"
    case .webhook: "webhook"
    case .runScript: "run_script"
    case .runShortcut: "run_shortcut"
    case .shareSheet: "share_sheet"
    case .openInApp: "open_in_app"
    case .condition: "condition"
    case .stop: "stop"
    case .runAutomation: "run_automation"
    case .ask: "ask"
    }
  }

  static func kind(_ token: String) -> AutomationStepKind? {
    AutomationStepKind.allCases.first { self.token($0) == token.lowercased() }
  }

  private static let commonKeys: Set<String> = ["kind", "enabled", "on_failure", "json"]

  private static func keys(for kind: AutomationStepKind) -> Set<String> {
    switch kind {
    case .applyCanvasPreset: ["preset"]
    case .resize: ["mode", "max_dimension", "scale_percent"]
    case .convert: ["format", "quality", "max_file_size_kb", "optimize_preset"]
    case .ocr: ["language", "include_qr"]
    case .translate: ["target"]
    case .convertToGIF: ["fps", "max_width"]
    case .copyLink: ["style", "template"]
    case .copyText: ["template"]
    case .saveToFolder: ["folder", "name", "conflict"]
    case .uploadAndCopyLink: ["format"]
    case .upload: ["destination"]
    case .webhook: ["method", "url", "headers", "body", "template", "fields", "file_field", "timeout", "response_to_text", "response_link"]
    case .runScript: ["script", "shell", "login_shell", "timeout", "output"]
    case .runShortcut: ["shortcut", "input", "output", "timeout"]
    case .shareSheet: ["service"]
    case .openInApp: ["app", "app_name"]
    case .condition: ["match", "otherwise", "predicates"]
    case .runAutomation: ["target"]
    case .ask: ["prompt", "choices"]
    default: []
    }
  }

  // MARK: - Export

  /// `section` is the step's own table path; conditions add
  /// `[<section>.predicates.<nn>]` sub-tables after the step's keys.
  @MainActor
  static func write(_ step: AutomationStep, to writer: inout SimpleTOMLWriter, section: String? = nil) {
    guard let action = step.action else {
      if case .unsupported(let raw) = step.content {
        writer.value("kind", raw.kind ?? "unknown")
        if let data = try? JSONEncoder().encode(raw), let json = String(data: data, encoding: .utf8) {
          writer.value("json", json)
        }
      }
      return
    }
    writer.value("kind", token(action.kind))
    if !step.isEnabled { writer.value("enabled", false) }
    if step.onFailure != .stop { writer.value("on_failure", step.onFailure.rawValue) }

    switch action {
    case .applyCanvasPreset(let config):
      writer.value("preset", config.presetID?.uuidString.lowercased() ?? "default")
    case .resize(let config):
      writer.value("mode", config.mode == .maxDimension ? "max_dimension" : "scale_percent")
      writer.value("max_dimension", config.maxDimension)
      writer.value("scale_percent", config.scalePercent)
    case .convert(let config):
      writer.value("format", config.format.rawValue)
      writer.value("quality", config.quality)
      if let maxKB = config.maxFileSizeKB { writer.value("max_file_size_kb", maxKB) }
      if let preset = config.optimizePresetID { writer.value("optimize_preset", preset.uuidString.lowercased()) }
    case .ocr(let config):
      if let language = config.languageIdentifier { writer.value("language", language) }
      writer.value("include_qr", config.includeQR)
    case .translate(let config):
      if let target = config.targetLanguage { writer.value("target", target) }
    case .convertToGIF(let config):
      writer.value("fps", config.fps)
      writer.value("max_width", config.maxWidth)
    case .copyLink(let template):
      writer.value("style", template.style.rawValue)
      if template.style == .custom { writer.value("template", template.custom) }
    case .copyText(let template):
      writer.value("template", template.template)
    case .saveToFolder(let config):
      if let folder = config.folder {
        let path = folder == .exportDirectory
          ? AutomationFolderRef.exportToken
          : (AutomationFolderAccessStore.shared.path(for: folder) ?? config.folderPath ?? "")
        writer.value("folder", (path as NSString).abbreviatingWithTildeInPath)
      } else if let path = config.folderPath {
        writer.value("folder", (path as NSString).abbreviatingWithTildeInPath)
      }
      writer.value("name", config.nameTemplate)
      writer.value("conflict", config.conflict.rawValue)
    case .uploadAndCopyLink(let format):
      writer.value("format", format.rawValue)
    case .upload(let config):
      if case .customUploader(let id) = config.destination {
        writer.value("destination", id.uuidString.lowercased())
      }
    case .webhook(let config):
      // Secret values never reach the file: fields hold `{secret:NAME}` references only.
      writer.value("method", config.method.rawValue)
      writer.value("url", config.url)
      if !config.headers.isEmpty {
        writer.stringArray("headers", config.headers.map { "\($0.name): \($0.value)" })
      }
      writer.value("body", config.bodyKind.rawValue)
      switch config.bodyKind {
      case .json: writer.value("template", config.jsonTemplate)
      case .form, .multipart:
        writer.stringArray("fields", config.fields.map { "\($0.name)=\($0.value)" })
        if config.bodyKind == .multipart { writer.value("file_field", config.fileField) }
      case .none: break
      }
      writer.value("timeout", Int(config.clampedTimeout))
      if config.responseToText { writer.value("response_to_text", true) }
      if let path = config.trimmedResponseLinkPath { writer.value("response_link", path) }
    case .runScript(let config):
      writer.value("script", config.script)
      writer.value("shell", config.shell.rawValue)
      if config.useLoginShell { writer.value("login_shell", true) }
      writer.value("timeout", Int(config.clampedTimeout))
      writer.value("output", config.output.rawValue)
    case .runShortcut(let config):
      writer.value("shortcut", config.name)
      writer.value("input", config.input.rawValue)
      writer.value("output", config.output.rawValue)
      writer.value("timeout", Int(config.clampedTimeout))
    case .shareSheet(let config):
      writer.value("service", config.service.token)
    case .openInApp(let config):
      writer.value("app", config.appBundleID)
      if !config.appName.isEmpty { writer.value("app_name", config.appName) }
    case .condition(let config):
      writer.value("match", config.match.rawValue)
      writer.value("otherwise", config.otherwise.token)
      if let section {
        for (index, predicate) in config.predicates.enumerated() {
          writer.section("\(section).predicates.\(SnapzyConfigurationAutomationsCodec.stepKey(index))")
          writePredicate(predicate, to: &writer)
        }
      }
    case .runAutomation(let config):
      if let id = config.automationID { writer.value("target", id.uuidString.lowercased()) }
    case .ask(let config):
      if !config.prompt.isEmpty { writer.value("prompt", config.prompt) }
      writer.stringArray("choices", config.choices.map(\.token))
    case .copyImage, .showQuickAccess, .openAnnotate, .notify, .stripMetadata,
         .copyFile, .reveal, .pin, .stop:
      break
    }
  }

  private static func writePredicate(_ predicate: AutomationPredicate, to writer: inout SimpleTOMLWriter) {
    if case .unsupported(let raw) = predicate {
      writer.value("type", predicate.type)
      if let data = try? JSONEncoder().encode(raw), let json = String(data: data, encoding: .utf8) {
        writer.value("json", json)
      }
      return
    }
    writer.value("type", predicate.type)
    switch predicate {
    case .frontmostApp(let bundleIDs, let negate):
      writer.stringArray("bundle_ids", bundleIDs)
      if negate { writer.value("negate", true) }
    case .captureMode(let modes):
      writer.stringArray("modes", modes.map { SnapzyConfigurationAutomationsCodec.captureToken($0) })
    case .invocation(let invocations):
      writer.stringArray("invocations", invocations.map(\.rawValue))
    case .fileKind(let kinds):
      writer.stringArray("kinds", kinds.map(\.rawValue))
    case .pixelSize(let dimension, let comparison, let value):
      writer.value("dimension", dimension.rawValue)
      writer.value("comparison", comparison.rawValue)
      writer.value("value", value)
    case .fileSize(let comparison, let bytes):
      writer.value("comparison", comparison.rawValue)
      writer.value("bytes", bytes)
    case .hasText(let contains):
      if let contains { writer.value("contains", contains) }
    case .unsupported:
      break
    }
  }

  private static func parsePredicate(
    _ fields: [String: SimpleTOMLValue],
    path: String,
    warnings: inout [String]
  ) -> AutomationPredicate? {
    guard let type = fields["type"]?.stringValue?.lowercased() else {
      warnings.append("\(path).type is missing; predicate ignored")
      return nil
    }
    func strings(_ key: String) -> [String] { fields[key]?.stringArrayValue ?? [] }
    func comparison() -> AutomationComparison {
      fields["comparison"]?.stringValue.flatMap { AutomationComparison(rawValue: $0.lowercased()) } ?? .greaterThan
    }
    switch type {
    case "frontmost_app":
      return .frontmostApp(bundleIDs: strings("bundle_ids"), negate: fields["negate"]?.boolValue ?? false)
    case "capture_mode":
      return .captureMode(strings("modes").compactMap(SnapzyConfigurationAutomationsCodec.captureMode))
    case "invocation":
      return .invocation(strings("invocations").compactMap { AutomationInvocation(rawValue: $0) })
    case "file_kind":
      return .fileKind(strings("kinds").compactMap { AutomationFileKind(rawValue: $0.lowercased()) })
    case "pixel_size":
      return .pixelSize(
        dimension: fields["dimension"]?.stringValue.flatMap { AutomationDimension(rawValue: $0.lowercased()) } ?? .longest,
        comparison: comparison(),
        value: fields["value"]?.intValue ?? 0
      )
    case "file_size":
      return .fileSize(comparison: comparison(), bytes: fields["bytes"]?.intValue ?? 0)
    case "has_text":
      return .hasText(contains: fields["contains"]?.stringValue)
    default:
      if let json = fields["json"]?.stringValue,
         let raw = try? JSONDecoder().decode(AutomationJSONValue.self, from: Data(json.utf8))
      {
        return .unsupported(raw)
      }
      warnings.append("\(path): unknown predicate \"\(type)\" ignored")
      return nil
    }
  }

  /// A Run Automation / Ask target: an id, or a name resolved against the stored automations.
  /// Names win from the file being imported (`fileNames`, lowercased → ids), so
  /// automations can point at each other before they exist on this Mac.
  @MainActor
  private static func resolveTarget(
    _ raw: String,
    path: String,
    fileNames: [String: [UUID]],
    warnings: inout [String]
  ) -> UUID? {
    if let id = UUID(uuidString: raw.trimmingCharacters(in: .whitespaces)) { return id }
    let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let ids = fileNames[key] {
      if ids.count == 1 { return ids[0] }
      warnings.append("\(path): several automations are named \"\(raw)\"; use its id")
      return nil
    }
    switch AutomationStore.shared.resolve(.name(raw)) {
    case .success(let automation):
      return automation.id
    case .failure(.ambiguousName):
      warnings.append("\(path): several automations are named \"\(raw)\"; use its id")
      return nil
    case .failure:
      warnings.append("\(path): no automation named \"\(raw)\"")
      return nil
    }
  }

  // MARK: - Import

  @MainActor
  static func parse(
    _ fields: [String: SimpleTOMLValue],
    path: String,
    folderStore: AutomationFolderAccessStore,
    fileNames: [String: [UUID]] = [:]
  ) -> ParseResult {
    var warnings: [String] = []
    guard let kindToken = fields["kind"]?.stringValue else {
      return ParseResult(step: nil, warnings: ["\(path).kind is missing; skipped"])
    }
    guard let kind = kind(kindToken) else {
      if let json = fields["json"]?.stringValue,
         let raw = try? JSONDecoder().decode(AutomationJSONValue.self, from: Data(json.utf8))
      {
        var step = AutomationStep(.notify)
        step.content = .unsupported(raw)
        return ParseResult(step: step, warnings: [])
      }
      return ParseResult(step: nil, warnings: ["\(path): unknown step \"\(kindToken)\" ignored"])
    }

    for key in fields.keys where !commonKeys.contains(key) && !keys(for: kind).contains(key) {
      warnings.append("\(path).\(key) is not used by \(kindToken); ignored")
    }

    func string(_ key: String) -> String? { fields[key]?.stringValue }
    func int(_ key: String) -> Int? { fields[key]?.intValue }
    func bool(_ key: String) -> Bool? { fields[key]?.boolValue }

    let action: AutomationStepAction
    switch kind {
    case .applyCanvasPreset:
      let raw = string("preset")
      action = .applyCanvasPreset(AutomationCanvasPresetConfig(
        presetID: raw == nil || raw == "default" ? nil : raw.flatMap(UUID.init(uuidString:))
      ))
    case .resize:
      var config = AutomationResizeConfig()
      if string("mode") == "scale_percent" { config.mode = .scalePercent }
      config.maxDimension = int("max_dimension") ?? config.maxDimension
      config.scalePercent = int("scale_percent") ?? config.scalePercent
      if fields["mode"] == nil, fields["scale_percent"] != nil, fields["max_dimension"] == nil {
        config.mode = .scalePercent
      }
      action = .resize(config)
    case .convert:
      var config = AutomationConvertConfig()
      if let raw = string("format") {
        if let format = QuickAccessOptimizeFormat(rawValue: raw.lowercased()) {
          config.format = format
        } else {
          warnings.append("\(path).format \"\(raw)\" is unknown; using \(config.format.rawValue)")
        }
      }
      config.quality = int("quality") ?? config.quality
      config.maxFileSizeKB = int("max_file_size_kb")
      config.optimizePresetID = string("optimize_preset").flatMap(UUID.init(uuidString:))
      action = .convert(config)
    case .ocr:
      action = .ocr(AutomationOCRConfig(languageIdentifier: string("language"), includeQR: bool("include_qr") ?? false))
    case .translate:
      action = .translate(AutomationTranslateConfig(targetLanguage: string("target")))
    case .convertToGIF:
      action = .convertToGIF(AutomationGIFConfig(fps: int("fps") ?? 15, maxWidth: int("max_width") ?? 960))
    case .copyLink:
      let style = string("style").flatMap { AutomationLinkStyle(rawValue: $0.lowercased()) }
        ?? (fields["template"] != nil ? .custom : .url)
      action = .copyLink(AutomationLinkTemplate(style: style, custom: string("template") ?? ""))
    case .copyText:
      action = .copyText(AutomationTextTemplate(template: string("template") ?? AutomationTextTemplate.defaultTemplate))
    case .saveToFolder:
      var config = AutomationSaveToFolderConfig(
        nameTemplate: string("name") ?? AutomationSaveToFolderConfig.defaultNameTemplate,
        conflict: string("conflict").flatMap(AutomationConflictPolicy.init(rawValue:)) ?? .uniquify
      )
      if let folder = string("folder") {
        if folder == AutomationFolderRef.exportToken {
          config.folder = .exportDirectory
        } else {
          let expanded = (folder as NSString).expandingTildeInPath
          var isDirectory: ObjCBool = false
          config.folderPath = expanded
          if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
            config.folder = .bookmark(folderStore.register(URL(fileURLWithPath: expanded, isDirectory: true)))
          } else {
            warnings.append("\(path).folder \"\(folder)\" not found; choose it again in Settings → Automations")
          }
        }
      }
      action = .saveToFolder(config)
    case .uploadAndCopyLink:
      action = .uploadAndCopyLink(string("format").flatMap(AutomationLinkFormat.init(rawValue:)) ?? .url)
    case .copyImage: action = .copyImage
    case .showQuickAccess: action = .showQuickAccess
    case .openAnnotate: action = .openAnnotate
    case .notify: action = .notify
    case .stripMetadata: action = .stripMetadata
    case .upload:
      var config = AutomationUploadConfig()
      if let raw = string("destination"), raw != AutomationUploadDestination.defaultToken {
        if let id = UUID(uuidString: raw) {
          config.destination = .customUploader(id)
        } else {
          warnings.append("\(path).destination must be \"default\" or a custom uploader id; using default")
        }
      }
      action = .upload(config)
    case .webhook:
      var config = AutomationWebhookConfig()
      if let raw = string("method") {
        if let method = AutomationHTTPMethod(rawValue: raw.uppercased()) {
          config.method = method
        } else {
          warnings.append("\(path).method \"\(raw)\" is unknown; using POST")
        }
      }
      config.url = string("url") ?? ""
      config.headers = pairs(fields["headers"], separator: ":", path: "\(path).headers", warnings: &warnings)
      if let raw = string("body") {
        if let body = AutomationWebhookBodyKind(rawValue: raw.lowercased()) {
          config.bodyKind = body
        } else {
          warnings.append("\(path).body must be none, json, form or multipart; using json")
        }
      }
      config.jsonTemplate = string("template") ?? config.jsonTemplate
      config.fields = pairs(fields["fields"], separator: "=", path: "\(path).fields", warnings: &warnings)
      config.fileField = string("file_field") ?? config.fileField
      config.timeout = fields["timeout"]?.doubleValue ?? config.timeout
      config.responseToText = bool("response_to_text") ?? false
      config.responseLinkPath = string("response_link")
      if !config.url.isEmpty, !AutomationWebhookPolicy.isAcceptableTemplate(config.url) {
        warnings.append("\(path).url must start with https:// (or http://localhost)")
      }
      action = .webhook(config)
    case .runScript:
      var config = AutomationRunScriptConfig(script: string("script") ?? "")
      config.shell = string("shell").flatMap { AutomationScriptShell(rawValue: $0.lowercased()) } ?? .zsh
      config.useLoginShell = bool("login_shell") ?? false
      config.timeout = fields["timeout"]?.doubleValue ?? config.timeout
      config.output = string("output").flatMap { AutomationScriptOutput(rawValue: $0.lowercased()) } ?? .ignore
      action = .runScript(config)
    case .runShortcut:
      var config = AutomationRunShortcutConfig(name: string("shortcut") ?? "")
      config.input = string("input").flatMap { AutomationShortcutInput(rawValue: $0.lowercased()) } ?? .file
      config.output = string("output").flatMap { AutomationShortcutOutput(rawValue: $0.lowercased()) } ?? .ignore
      config.timeout = fields["timeout"]?.doubleValue ?? config.timeout
      action = .runShortcut(config)
    case .shareSheet:
      action = .shareSheet(AutomationShareSheetConfig(service: AutomationShareService(token: string("service") ?? "picker")))
    case .openInApp:
      action = .openInApp(AutomationOpenInAppConfig(appBundleID: string("app") ?? "", appName: string("app_name") ?? ""))
    case .copyFile: action = .copyFile
    case .reveal: action = .reveal
    case .pin: action = .pin
    case .stop: action = .stop
    case .condition:
      var config = AutomationConditionConfig()
      if let raw = string("match") {
        if let match = AutomationConditionConfig.Match(rawValue: raw.lowercased()) {
          config.match = match
        } else {
          warnings.append("\(path).match must be all or any; using all")
        }
      }
      if let raw = string("otherwise") {
        if let otherwise = AutomationConditionConfig.Otherwise(token: raw) {
          config.otherwise = otherwise
        } else {
          warnings.append("\(path).otherwise must be \"stop\" or \"skip:<n>\"; using stop")
        }
      }
      if case .table(let tables)? = fields["predicates"] {
        for key in tables.keys.sorted() {
          guard case .table(let predicateFields)? = tables[key] else { continue }
          if let predicate = parsePredicate(predicateFields, path: "\(path).predicates.\(key)", warnings: &warnings) {
            config.predicates.append(predicate)
          }
        }
      }
      action = .condition(config)
    case .runAutomation:
      let target = string("target").flatMap { resolveTarget($0, path: "\(path).target", fileNames: fileNames, warnings: &warnings) }
      action = .runAutomation(AutomationRunAutomationConfig(automationID: target))
    case .ask:
      var config = AutomationAskConfig(prompt: string("prompt") ?? "")
      for raw in fields["choices"]?.stringArrayValue ?? [] {
        switch raw.lowercased() {
        case "continue": config.choices.append(.continueRun)
        case "stop": config.choices.append(.stopRun)
        default:
          if let id = resolveTarget(raw, path: "\(path).choices", fileNames: fileNames, warnings: &warnings) {
            config.choices.append(.automation(id))
          }
        }
      }
      action = .ask(config)
    }

    var onFailure = AutomationFailurePolicy.stop
    if let raw = string("on_failure") {
      if let policy = AutomationFailurePolicy(rawValue: raw.lowercased()) {
        onFailure = policy
      } else {
        warnings.append("\(path).on_failure must be stop or continue; using stop")
      }
    }
    let step = AutomationStep(action, isEnabled: bool("enabled") ?? true, onFailure: onFailure)
    return ParseResult(step: step, warnings: warnings)
  }

  /// `["Name: value", …]` (headers) or `["name=value", …]` (form fields).
  private static func pairs(
    _ value: SimpleTOMLValue?,
    separator: Character,
    path: String,
    warnings: inout [String]
  ) -> [AutomationKeyValue] {
    guard let value else { return [] }
    guard let items = value.stringArrayValue else {
      warnings.append("\(path) must be an array of strings; ignored")
      return []
    }
    return items.compactMap { text in
      guard let index = text.firstIndex(of: separator) else {
        warnings.append("\(path): entries look like \"name\(separator)value\"; one was ignored")
        return nil
      }
      let name = text[..<index].trimmingCharacters(in: .whitespaces)
      let rest = text[text.index(after: index)...]
      let value = separator == ":" ? rest.trimmingCharacters(in: .whitespaces) : String(rest)
      return AutomationKeyValue(name: name, value: value)
    }
  }
}
