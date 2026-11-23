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
    default: []
    }
  }

  // MARK: - Export

  @MainActor
  static func write(_ step: AutomationStep, to writer: inout SimpleTOMLWriter) {
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
    case .copyImage, .showQuickAccess, .openAnnotate, .notify, .stripMetadata,
         .upload, .copyFile, .reveal, .pin:
      break
    }
  }

  // MARK: - Import

  @MainActor
  static func parse(
    _ fields: [String: SimpleTOMLValue],
    path: String,
    folderStore: AutomationFolderAccessStore
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
    case .upload: action = .upload
    case .copyFile: action = .copyFile
    case .reveal: action = .reveal
    case .pin: action = .pin
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
}
