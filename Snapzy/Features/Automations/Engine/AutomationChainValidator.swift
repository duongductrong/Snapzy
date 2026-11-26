//
//  AutomationChainValidator.swift
//  Snapzy
//
//  Walks the steps with the payload kinds the source produces and reports
//  steps that have nothing to work on (e.g. Translate before OCR) or miss
//  required settings. The editor shows the issues and blocks saving on
//  blocking ones; the launcher refuses to start a chain with any of them.
//  Milestone 5: conditions split the walk into paths (each checked on its
//  own), Run Automation / Ask are followed into their targets with cycle and
//  depth checks.
//

import Foundation

extension AutomationPredicate {
  /// No value chosen yet (e.g. "frontmost app is" without an app).
  var isIncomplete: Bool {
    switch self {
    case .frontmostApp(let bundleIDs, _): bundleIDs.isEmpty
    case .captureMode(let modes): modes.isEmpty
    case .invocation(let invocations): invocations.isEmpty
    case .fileKind(let kinds): kinds.isEmpty
    case .pixelSize, .fileSize, .hasText, .unsupported: false
    }
  }
}

struct AutomationChainIssue: Equatable, Sendable {
  enum Reason: Equatable, Sendable {
    /// None of these kinds is available when the step runs.
    case needs(Set<AutomationPayloadKind>)
    /// A required setting is missing (e.g. Save to Folder without a folder).
    case missingConfig(Field)
    /// Run Automation / Ask reaches an automation already running (A → B → A)
    /// or nests deeper than `AutomationControlLimits.maxDepth`.
    case recursion
    /// The automation Run Automation / Ask runs has a step with nothing to work on here.
    case targetCannotRun
    /// Redact runs after a step that already sent the image off the Mac (milestone 6).
    case redactAfterNetwork
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
    /// Run Automation / Ask points at an automation that is gone or not chosen.
    case automation
    /// Ask without choices.
    case choices
    /// A condition predicate without values (e.g. no app chosen).
    case condition
    /// "Otherwise skip" reaches past the last step.
    case skipRange
  }

  let stepID: UUID
  let reason: Reason

  /// `.needs` / recursion make the chain impossible; `.missingConfig` only needs setup.
  var blocksRun: Bool {
    switch reason {
    case .needs, .recursion, .targetCannotRun: true
    // An unset predicate would silently end (or skip) every run.
    case .missingConfig(.condition): true
    case .missingConfig, .redactAfterNetwork: false
    }
  }

  /// Advice only: the automation runs as is and needs no setup.
  var isWarning: Bool {
    reason == .redactAfterNetwork
  }
}

@MainActor
enum AutomationChainValidator {
  /// Payload kinds that can reach a point of the chain, one set per path.
  /// A condition splits the path (taken / skipped); kinds are tracked per path
  /// so a step that only one path can feed is still reported.
  typealias Paths = Set<Set<AutomationPayloadKind>>

  /// Issues in step order. Disabled and unsupported steps are ignored.
  /// `canvasPresetExists` reports whether a preset id still exists;
  /// `automationLookup` resolves Run Automation / Ask targets.
  static func validate(
    _ automation: Automation,
    initialKinds: Set<AutomationPayloadKind>? = nil,
    canvasPresetExists: @escaping (UUID) -> Bool = { _ in true },
    uploaderExists: ((UUID) -> Bool)? = nil,
    secretExists: ((String) -> Bool)? = nil,
    automationLookup: ((UUID) -> Automation?)? = nil
  ) -> [AutomationChainIssue] {
    let checks = Checks(
      canvasPresetExists: canvasPresetExists,
      uploaderExists: uploaderExists ?? { CustomUploaderStore.shared.uploader(id: $0) != nil },
      secretExists: secretExists ?? { AutomationSecretStore.shared.contains($0) },
      lookup: automationLookup ?? { AutomationStore.shared.automation(id: $0) }
    )
    let initial = initialKinds ?? automation.source.initialPayloadKinds
    return analyze(automation.steps, paths: [initial], chain: [automation.id], checks: checks).issues
      + redactOrderIssues(automation.steps)
  }

  /// Redact protects only what comes after it: warn when an earlier step
  /// already uploaded / sent the image.
  private static func redactOrderIssues(_ steps: [AutomationStep]) -> [AutomationChainIssue] {
    var sentOff = false
    var issues: [AutomationChainIssue] = []
    for step in steps where step.isEnabled {
      guard let action = step.action else { continue }
      if action.kind == .redact, sentOff {
        issues.append(AutomationChainIssue(stepID: step.id, reason: .redactAfterNetwork))
      }
      if AutomationTrust.tier(of: action) != .local, action.kind != .translate {
        sentOff = true
      }
    }
    return issues
  }

  static func blockingIssues(
    _ automation: Automation,
    automationLookup: ((UUID) -> Automation?)? = nil
  ) -> [AutomationChainIssue] {
    validate(automation, automationLookup: automationLookup).filter(\.blocksRun)
  }

  private struct Checks {
    let canvasPresetExists: (UUID) -> Bool
    let uploaderExists: (UUID) -> Bool
    let secretExists: (String) -> Bool
    let lookup: (UUID) -> Automation?
  }

  private struct Analysis {
    var issues: [AutomationChainIssue] = []
    /// Kinds when this level ends (last step, Stop, failed condition): what a
    /// nested run hands back to its parent.
    var exits: Paths = []
  }

  private static func analyze(
    _ steps: [AutomationStep],
    paths initial: Paths,
    chain: [UUID],
    checks: Checks
  ) -> Analysis {
    var analysis = Analysis()
    var incoming = [Paths](repeating: [], count: steps.count + 1)
    incoming[0] = initial

    func add(_ issue: AutomationChainIssue) {
      if !analysis.issues.contains(issue) { analysis.issues.append(issue) }
    }

    for (index, step) in steps.enumerated() {
      let paths = incoming[index]
      // Unreachable (every path stopped before it): nothing to check.
      guard !paths.isEmpty else { continue }
      guard step.isEnabled, let action = step.action else {
        incoming[index + 1].formUnion(paths)
        continue
      }

      if let field = missingField(action, checks: checks) {
        add(AutomationChainIssue(stepID: step.id, reason: .missingConfig(field)))
      }

      switch action {
      case .condition(let config):
        incoming[index + 1].formUnion(paths)
        switch config.otherwise {
        case .stop:
          analysis.exits.formUnion(paths)
        case .skip(let count):
          var target = index + 1 + count
          if target > steps.count {
            add(AutomationChainIssue(stepID: step.id, reason: .missingConfig(.skipRange)))
            target = steps.count
          }
          incoming[target].formUnion(paths)
        }

      case .stop:
        analysis.exits.formUnion(paths)

      case .runAutomation(let config):
        guard let targetID = config.automationID else {
          incoming[index + 1].formUnion(paths)
          continue
        }
        // A disabled target fails at run time (Ask only hides it).
        if let target = checks.lookup(targetID), !target.isEnabled {
          add(AutomationChainIssue(stepID: step.id, reason: .missingConfig(.automation)))
        }
        let nested = nestedExits(targetID, stepID: step.id, paths: paths, chain: chain, checks: checks)
        nested.issues.forEach(add)
        incoming[index + 1].formUnion(nested.exits ?? paths)

      case .ask(let config):
        for choice in config.choices {
          switch choice {
          case .continueRun:
            incoming[index + 1].formUnion(paths)
          case .stopRun:
            analysis.exits.formUnion(paths)
          case .automation(let targetID):
            let nested = nestedExits(targetID, stepID: step.id, paths: paths, chain: chain, checks: checks)
            nested.issues.forEach(add)
            analysis.exits.formUnion(nested.exits ?? paths)
          }
        }

      default:
        let handler = AutomationStepRegistry.handler(for: action.kind)
        let accepted = handler.accepts(action)
        var next: Paths = []
        for kinds in paths {
          if accepted.isDisjoint(with: kinds) {
            add(AutomationChainIssue(stepID: step.id, reason: .needs(accepted)))
            // The runner skips the step on this path; kinds pass through.
            next.insert(kinds)
          } else {
            next.insert(handler.produces(action, given: kinds))
          }
        }
        incoming[index + 1].formUnion(next)
      }
    }
    analysis.exits.formUnion(incoming[steps.count])
    return analysis
  }

  /// Kinds a nested run of `targetID` hands back, plus issues reported on the
  /// calling step. `exits == nil` when the target can't be analyzed.
  private static func nestedExits(
    _ targetID: UUID,
    stepID: UUID,
    paths: Paths,
    chain: [UUID],
    checks: Checks
  ) -> (issues: [AutomationChainIssue], exits: Paths?) {
    guard let target = checks.lookup(targetID) else {
      return ([AutomationChainIssue(stepID: stepID, reason: .missingConfig(.automation))], nil)
    }
    guard !chain.contains(targetID), chain.count <= AutomationControlLimits.maxDepth else {
      return ([AutomationChainIssue(stepID: stepID, reason: .recursion)], nil)
    }
    let nested = analyze(target.migrated().steps, paths: paths, chain: chain + [targetID], checks: checks)
    var issues: [AutomationChainIssue] = []
    if nested.issues.contains(where: { if case .recursion = $0.reason { true } else { false } }) {
      issues.append(AutomationChainIssue(stepID: stepID, reason: .recursion))
    } else if nested.issues.contains(where: \.blocksRun) {
      issues.append(AutomationChainIssue(stepID: stepID, reason: .targetCannotRun))
    }
    return (issues, nested.exits)
  }

  private static func missingField(_ action: AutomationStepAction, checks: Checks) -> AutomationChainIssue.Field? {
    let canvasPresetExists = checks.canvasPresetExists
    let uploaderExists = checks.uploaderExists
    let secretExists = checks.secretExists
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
    case .condition(let config):
      return config.predicates.contains(where: \.isIncomplete) ? .condition : nil
    case .runAutomation(let config):
      return config.automationID == nil ? .automation : nil
    case .ask(let config):
      if config.choices.isEmpty { return .choices }
      return config.referencedAutomationIDs.contains { checks.lookup($0) == nil } ? .automation : nil
    default:
      return nil
    }
  }
}
