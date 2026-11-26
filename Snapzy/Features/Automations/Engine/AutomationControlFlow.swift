//
//  AutomationControlFlow.swift
//  Snapzy
//
//  Control steps (milestone 5). The runner executes them itself (they steer
//  the run instead of acting on files); the handlers here only declare kinds
//  and trust for the validator and the launcher. `AutomationConditionEvaluator`
//  decides a condition from the run context and the current payload.
//

import Foundation

/// How deep `runAutomation` / Ask may nest (A runs B runs C).
enum AutomationControlLimits {
  static let maxDepth = 3
}

/// The app a run is about: the captured window's app when the capture knows
/// it, else the app that was frontmost when the run was triggered.
struct AutomationAppSnapshot: Equatable, Sendable {
  var name: String?
  var bundleID: String?
  var windowTitle: String?

  static let none = AutomationAppSnapshot()

  init(name: String? = nil, bundleID: String? = nil, windowTitle: String? = nil) {
    self.name = name
    self.bundleID = bundleID
    self.windowTitle = windowTitle
  }

  init(_ context: CaptureContext) {
    self.init(name: context.appName, bundleID: context.bundleID, windowTitle: context.windowTitle)
  }

  /// Capture-time facts win; missing ones keep the trigger-time value.
  func merged(with capture: AutomationAppSnapshot) -> AutomationAppSnapshot {
    let sameApp = capture.bundleID == nil || capture.bundleID == bundleID
    return AutomationAppSnapshot(
      name: capture.name ?? (sameApp ? name : nil),
      bundleID: capture.bundleID ?? bundleID,
      windowTitle: capture.windowTitle ?? (sameApp ? windowTitle : nil)
    )
  }
}

/// A row in the picker HUD (Ask step, Finder service, menu bar drop).
struct AutomationPickerChoice: Equatable, Identifiable, Sendable {
  enum Value: Equatable, Hashable, Sendable {
    case automation(UUID)
    case continueRun
    case stopRun
  }

  let value: Value
  let title: String
  let symbol: String

  var id: Value { value }
}

@MainActor
extension AutomationRunEnvironment {
  func automation(id _: UUID) -> Automation? { nil }

  func pick(title _: String, thumbnail _: URL?, choices _: [AutomationPickerChoice]) async -> AutomationPickerChoice? {
    nil
  }
}

// MARK: - Condition evaluation

@MainActor
enum AutomationConditionEvaluator {
  static func evaluate(_ config: AutomationConditionConfig, state: AutomationRunState) -> Bool {
    // No predicates: nothing to test, the condition holds.
    guard !config.predicates.isEmpty else { return true }
    let results = config.predicates.map { evaluate($0, state: state) }
    switch config.match {
    case .all: return results.allSatisfy { $0 }
    case .any: return results.contains(true)
    }
  }

  static func evaluate(_ predicate: AutomationPredicate, state: AutomationRunState) -> Bool {
    let context = state.context
    let firstFile = state.payload.files.first
    switch predicate {
    case .frontmostApp(let bundleIDs, let negate):
      let wanted = Set(bundleIDs.map { $0.lowercased() })
      let matches = context.bundleID.map { wanted.contains($0.lowercased()) } ?? false
      return negate ? !matches : matches
    case .captureMode(let modes):
      return context.captureMode.map(modes.contains) ?? false
    case .invocation(let invocations):
      return invocations.contains(context.invocation)
    case .fileKind(let kinds):
      return firstFile.map { kinds.contains($0.kind) } ?? false
    case .pixelSize(let dimension, let comparison, let value):
      guard let file = firstFile, file.kind == .image,
            let size = AutomationRunState.pixelSize(of: file.url) else { return false }
      let measured: Int = switch dimension {
      case .width: Int(size.width)
      case .height: Int(size.height)
      case .longest: Int(max(size.width, size.height))
      }
      return comparison.holds(measured, value)
    case .fileSize(let comparison, let bytes):
      guard let file = firstFile,
            let size = (try? FileManager.default.attributesOfItem(atPath: file.url.path))?[.size] as? NSNumber
      else { return false }
      return comparison.holds(size.intValue, bytes)
    case .hasText(let contains):
      guard let text = state.payload.text, !text.isEmpty else { return false }
      guard let contains, !contains.isEmpty else { return true }
      return text.localizedCaseInsensitiveContains(contains)
    case .unsupported:
      return false
    }
  }
}

// MARK: - Handlers (kinds and trust only)

/// Passes the payload through unchanged. `run` is never called: the runner
/// handles control steps before reaching a handler.
struct ControlStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { AutomationPayloadKind.all }

  func run(
    _: AutomationStepAction,
    files _: [URL],
    state _: inout AutomationRunState,
    environment _: AutomationRunEnvironment
  ) async throws {}
}

extension AutomationStepError {
  static func automationUnavailable(_ name: String) -> AutomationStepError {
    .failed(L10n.Automations.errorAutomationUnavailable(name))
  }

  static var recursionLimit: AutomationStepError {
    .failed(L10n.Automations.errorRecursionLimit)
  }

  static var noChoices: AutomationStepError {
    .failed(L10n.Automations.errorNoChoices)
  }
}

// MARK: - Referenced automations

@MainActor
extension Automation {
  /// Ids of automations this one's enabled steps run (Run Automation, Ask).
  var referencedAutomationIDs: [UUID] {
    activeActions.flatMap(\.referencedAutomationIDs)
  }

  /// This automation plus every automation it can reach through Run Automation
  /// and Ask, each once (cycles stop the walk).
  func reachableAutomations(lookup: (UUID) -> Automation?) -> [Automation] {
    var result = [self]
    var seen: Set<UUID> = [id]
    var queue = referencedAutomationIDs
    while let next = queue.first {
      queue.removeFirst()
      guard seen.insert(next).inserted, let target = lookup(next) else { continue }
      result.append(target)
      queue.append(contentsOf: target.referencedAutomationIDs)
    }
    return result
  }

  /// Highest tier this automation can reach, including referenced automations.
  func effectiveMaxTrust(lookup: (UUID) -> Automation?) -> AutomationTrustTier {
    reachableAutomations(lookup: lookup).map(\.maxTrust).max() ?? .local
  }
}
