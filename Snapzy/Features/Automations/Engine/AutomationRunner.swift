//
//  AutomationRunner.swift
//  Snapzy
//
//  Runs automations. A capture-sourced run is registered with `begin(_:)`,
//  which returns the routing the capture carries; the saved files come back
//  through `complete(runID:capturedURLs:)` and the steps run in order.
//
//  Guarantee: a capture is never lost. Files are saved before any step runs,
//  and a failed upload leaves the image on the clipboard plus a Quick Access
//  card to retry from.
//

import Foundation

@MainActor
final class AutomationRunner {
  static let shared = AutomationRunner(environment: LiveAutomationRunEnvironment())

  struct Result {
    let state: AutomationRunState
    let message: String
    let isError: Bool
  }

  private struct PendingRun {
    let automation: Automation
    let startedAt: Date
  }

  /// Area selection can stay open a long time; older registrations are dropped.
  private static let pendingLifetime: TimeInterval = 30 * 60

  private let environment: AutomationRunEnvironment
  private var pendingRuns: [UUID: PendingRun] = [:]
  private let now: () -> Date

  init(environment: AutomationRunEnvironment, now: @escaping () -> Date = Date.init) {
    self.environment = environment
    self.now = now
  }

  // MARK: - Capture-sourced runs

  /// Registers a run and returns the routing its capture must carry. The
  /// automation is snapshotted: editing it mid-capture does not change this run.
  func begin(_ automation: Automation) -> PostCaptureRouting {
    pruneStaleRuns()
    let runID = UUID()
    pendingRuns[runID] = PendingRun(automation: automation, startedAt: now())
    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Automation run started",
      context: ["automation": automation.id.uuidString, "runID": runID.uuidString]
    )
    return .automation(runID: runID)
  }

  /// The capture behind `routing` was cancelled or failed before saving a file.
  func abandon(routing: PostCaptureRouting) {
    guard case .automation(let runID) = routing,
          pendingRuns.removeValue(forKey: runID) != nil else { return }
    DiagnosticLogger.shared.log(.info, .action, "Automation run ended without a capture", context: ["runID": runID.uuidString])
  }

  /// The automation's Save choice for a capture that carries `routing`.
  func saveToExportOverride(for routing: PostCaptureRouting) -> Bool? {
    guard case .automation(let runID) = routing else { return nil }
    return pendingRuns[runID]?.automation.captureSpec?.saveToExportDirectory
  }

  func complete(runID: UUID, capturedURLs: [URL]) async {
    guard let pending = pendingRuns.removeValue(forKey: runID) else {
      // The registration expired. Never drop the capture: route it the standard way.
      DiagnosticLogger.shared.log(
        .warning,
        .action,
        "Automation run unknown; using standard post-capture routing",
        context: ["runID": runID.uuidString]
      )
      await PostCaptureActionHandler.shared.handleScreenshotCaptures(urls: capturedURLs)
      return
    }
    await run(pending.automation, files: capturedURLs, runID: runID)
  }

  // MARK: - Execution

  @discardableResult
  func run(_ automation: Automation, files: [URL], runID: UUID = UUID()) async -> Result? {
    let existing = files.filter { FileManager.default.fileExists(atPath: $0.path) }
    guard !existing.isEmpty else {
      DiagnosticLogger.shared.log(.error, .action, "Automation run skipped: capture file missing", context: ["runID": runID.uuidString])
      return nil
    }

    var state = AutomationRunState(runID: runID, automation: automation, files: existing)
    for file in existing {
      if let sessionData = environment.prepareScreenshot(file) {
        state.sessionData[file] = sessionData
      }
    }

    for step in automation.steps where step.isEnabled {
      guard let action = step.action else {
        DiagnosticLogger.shared.log(
          .warning,
          .action,
          "Automation step skipped: unsupported kind",
          context: ["runID": runID.uuidString, "kind": stepKindLabel(step)]
        )
        continue
      }

      let startedAt = now()
      do {
        try await AutomationStepRegistry.handler(for: action.kind).run(action, state: &state, environment: environment)
        logStep(action, runID: runID, startedAt: startedAt, error: nil)
      } catch {
        logStep(action, runID: runID, startedAt: startedAt, error: error)
        if action.kind == .uploadAndCopyLink {
          state.uploadFailure = (error as? AutomationStepError) == .cloudNotConfigured
            ? .notConfigured
            : .failed(error.localizedDescription)
          await applyUploadFallback(&state)
        }
        if step.onFailure == .stop { break }
      }
    }

    for file in existing {
      await environment.recordHistory(file)
    }

    let (message, isError) = outcomeMessage(for: state)
    if state.wantsNotification || isError {
      await environment.notify(title: automation.displayName, body: message, isError: isError)
    }

    DiagnosticLogger.shared.log(
      isError ? .warning : .info,
      .action,
      "Automation run finished",
      context: [
        "automation": automation.id.uuidString,
        "runID": runID.uuidString,
        "files": "\(existing.count)",
        "imageCopied": state.didCopyImage ? "true" : "false",
        "linkCopied": state.didCopyLink ? "true" : "false",
        "uploadFailed": state.uploadFailure == nil ? "false" : "true",
      ]
    )
    return Result(state: state, message: message, isError: isError)
  }

  /// A failed upload must still leave something to paste and a way to retry.
  private func applyUploadFallback(_ state: inout AutomationRunState) async {
    if !state.didCopyImage {
      state.ownPasteboardChangeCount = environment.copyImages(state.files)
      state.didCopyImage = true
    }
    if state.quickAccessItemIDs.isEmpty, let file = state.primaryFile,
       let itemID = await environment.showQuickAccess(file, sessionData: state.sessionData[file])
    {
      state.quickAccessItemIDs[file] = itemID
    }
  }

  private func outcomeMessage(for state: AutomationRunState) -> (String, Bool) {
    switch state.uploadFailure {
    case .notConfigured?:
      return (L10n.Automations.resultCloudNotConfigured, true)
    case .failed?:
      return (L10n.Automations.resultUploadFailed, true)
    case nil:
      break
    }
    if state.linkText != nil {
      return (state.didCopyLink ? L10n.Automations.resultLinkCopied : L10n.Automations.resultLinkReady, false)
    }
    if state.didCopyImage {
      return (L10n.Automations.resultImageCopied, false)
    }
    return (L10n.Automations.resultCaptureSaved, false)
  }

  private func pruneStaleRuns() {
    let cutoff = now().addingTimeInterval(-Self.pendingLifetime)
    pendingRuns = pendingRuns.filter { $0.value.startedAt >= cutoff }
  }

  private func stepKindLabel(_ step: AutomationStep) -> String {
    if case .unsupported(let raw) = step.content { return raw.kind ?? "unknown" }
    return step.action?.kind.rawValue ?? "unknown"
  }

  private func logStep(_ action: AutomationStepAction, runID: UUID, startedAt: Date, error: Error?) {
    let durationMs = Int(now().timeIntervalSince(startedAt) * 1000)
    var context = [
      "runID": runID.uuidString,
      "step": action.kind.rawValue,
      "duration_ms": "\(durationMs)",
    ]
    if let error {
      context["error"] = error.localizedDescription
      DiagnosticLogger.shared.log(.warning, .action, "Automation step failed", context: context)
    } else {
      DiagnosticLogger.shared.log(.debug, .action, "Automation step finished", context: context)
    }
  }
}
