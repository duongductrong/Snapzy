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

  enum Field: String, Equatable, Sendable {
    case folder
    case template
    case canvasPreset
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
    canvasPresetExists: (UUID) -> Bool = { _ in true }
  ) -> [AutomationChainIssue] {
    var kinds = initialKinds ?? automation.source.initialPayloadKinds
    var issues: [AutomationChainIssue] = []

    for step in automation.steps where step.isEnabled {
      guard let action = step.action else { continue }
      let handler = AutomationStepRegistry.handler(for: action.kind)

      if let field = missingField(action, canvasPresetExists: canvasPresetExists) {
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
    canvasPresetExists: (UUID) -> Bool
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
    default:
      return nil
    }
  }
}
