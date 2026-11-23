//
//  AutomationChainValidator.swift
//  Snapzy
//
//  Walks the steps with the payload kinds the source produces and reports
//  steps that have nothing to work on (e.g. Translate before OCR) or miss
//  required settings. The editor shows the issues and blocks saving on
//  `.needs`; the launcher refuses to start a chain with any `.needs` issue.
//

import Foundation

struct AutomationChainIssue: Equatable, Sendable {
  enum Reason: Equatable, Sendable {
    /// None of these kinds is available when the step runs.
    case needs(Set<AutomationPayloadKind>)
    /// A required setting is missing (e.g. Save to Folder without a folder).
    case missingConfig(Field)
  }

  enum Field: Equatable, Sendable {
    case folder
    case template
    case canvasPreset
    /// Upload to a custom uploader that no longer exists.
    case uploader
    /// Webhook without a valid `https://` URL.
    case webhookURL
    case script
    case shortcut
    case app
    /// A `{secret:NAME}` with no such secret.
    case secret(String)
  }

  let stepID: UUID
  let reason: Reason

  /// `.needs` makes the chain impossible; `.missingConfig` only needs setup.
  var blocksRun: Bool {
    if case .needs = reason { return true }
    return false
  }
}

@MainActor
enum AutomationChainValidator {
  /// Issues in step order. Disabled and unsupported steps are ignored.
  /// `canvasPresetExists` reports whether a preset id still exists.
  static func validate(
    _ automation: Automation,
    initialKinds: Set<AutomationPayloadKind>? = nil,
    canvasPresetExists: (UUID) -> Bool = { _ in true },
    uploaderExists: ((UUID) -> Bool)? = nil,
    secretExists: ((String) -> Bool)? = nil
  ) -> [AutomationChainIssue] {
    let uploaderExists = uploaderExists ?? { CustomUploaderStore.shared.uploader(id: $0) != nil }
    let secretExists = secretExists ?? { AutomationSecretStore.shared.contains($0) }
    var kinds = initialKinds ?? automation.source.initialPayloadKinds
    var issues: [AutomationChainIssue] = []

    for step in automation.steps where step.isEnabled {
      guard let action = step.action else { continue }
      let handler = AutomationStepRegistry.handler(for: action.kind)

      if let field = missingField(
        action,
        canvasPresetExists: canvasPresetExists,
        uploaderExists: uploaderExists,
        secretExists: secretExists
      ) {
        issues.append(AutomationChainIssue(stepID: step.id, reason: .missingConfig(field)))
      }

      let accepted = handler.accepts(action)
      guard !accepted.isDisjoint(with: kinds) else {
        issues.append(AutomationChainIssue(stepID: step.id, reason: .needs(accepted)))
        continue
      }
      kinds = handler.produces(action, given: kinds)
    }
    return issues
  }

  static func blockingIssues(_ automation: Automation) -> [AutomationChainIssue] {
    validate(automation).filter(\.blocksRun)
  }

  private static func missingField(
    _ action: AutomationStepAction,
    canvasPresetExists: (UUID) -> Bool,
    uploaderExists: (UUID) -> Bool,
    secretExists: (String) -> Bool
  ) -> AutomationChainIssue.Field? {
    switch action {
    case .saveToFolder(let config):
      return config.folder == nil ? .folder : nil
    case .copyLink(let template):
      return template.style == .custom && template.custom.trimmingCharacters(in: .whitespaces).isEmpty
        ? .template : nil
    case .copyText(let template):
      return template.template.trimmingCharacters(in: .whitespaces).isEmpty ? .template : nil
    case .applyCanvasPreset(let config):
      guard let id = config.presetID else { return nil }
      return canvasPresetExists(id) ? nil : .canvasPreset
    case .upload(let config):
      guard case .customUploader(let id) = config.destination else { return nil }
      return uploaderExists(id) ? nil : .uploader
    case .webhook(let config):
      guard AutomationWebhookPolicy.isAcceptableTemplate(config.url) else { return .webhookURL }
      let templates = [config.url, config.jsonTemplate]
        + config.headers.map(\.value) + config.fields.map(\.value)
      let missing = templates.flatMap(AutomationSecretStore.references(in:)).first { !secretExists($0) }
      return missing.map(AutomationChainIssue.Field.secret)
    case .runScript(let config):
      return config.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .script : nil
    case .runShortcut(let config):
      return config.trimmedName.isEmpty ? .shortcut : nil
    case .openInApp(let config):
      return config.trimmedBundleID.isEmpty ? .app : nil
    default:
      return nil
    }
  }
}
