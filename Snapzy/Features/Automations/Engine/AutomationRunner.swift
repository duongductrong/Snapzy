//
//  AutomationRunner.swift
//  Snapzy
//
//  Runs automations. A capture-sourced run is registered with `begin(_:)`,
//  which returns the routing the capture carries; the saved files come back
//  through `complete(runID:capturedURLs:)` and the steps run in order.
//  Input runs (`run(_:input:invocation:)`) skip the capture and run the steps
//  on files a trigger handed in.
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

    var report: AutomationRunReport {
      AutomationRunReport(
        runID: state.runID,
        automationID: state.automation.id,
        files: state.files,
        link: state.linkText,
        message: message,
        isError: isError
      )
    }
  }

  typealias FinishHandler = @MainActor (AutomationLaunchOutcome) -> Void

  private struct PendingRun {
    let automation: Automation
    let invocation: AutomationInvocation
    let startedAt: Date
    let onFinish: FinishHandler?
  }

  private enum RunSource {
    case capture
    case input(AutomationInput)
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
  /// `onFinish` is called exactly once: with the report, or `.cancelled` when
  /// the capture is abandoned or the registration expires.
  func begin(
    _ automation: Automation,
    invocation: AutomationInvocation = .hotkey,
    onFinish: FinishHandler? = nil
  ) -> PostCaptureRouting {
    pruneStaleRuns()
    let runID = UUID()
    pendingRuns[runID] = PendingRun(
      automation: automation,
      invocation: invocation,
      startedAt: now(),
      onFinish: onFinish
    )
    logStart(automation, runID: runID, invocation: invocation, source: "capture")
    if onFinish != nil {
      // A waiting caller (CLI, Shortcuts) must not hang if a capture path never reports back.
      Task { [weak self] in
        try? await Task.sleep(nanoseconds: UInt64(Self.pendingLifetime * 1_000_000_000))
        self?.expire(runID: runID)
      }
    }
    return .automation(runID: runID)
  }

  /// The capture behind `routing` was cancelled or failed before saving a file.
  func abandon(routing: PostCaptureRouting) {
    guard case .automation(let runID) = routing,
          let pending = pendingRuns.removeValue(forKey: runID) else { return }
    DiagnosticLogger.shared.log(.info, .action, "Automation run ended without a capture", context: ["runID": runID.uuidString])
    pending.onFinish?(.cancelled)
  }

  private func expire(runID: UUID) {
    guard let pending = pendingRuns.removeValue(forKey: runID) else { return }
    DiagnosticLogger.shared.log(.warning, .action, "Automation run expired without a capture", context: ["runID": runID.uuidString])
    pending.onFinish?(.cancelled)
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
    let result = await execute(pending.automation, files: capturedURLs, source: .capture, runID: runID)
    pending.onFinish?(result.map { .finished($0.report) } ?? .cancelled)
  }

  // MARK: - Execution

  /// Runs the steps on freshly captured screenshots.
  @discardableResult
  func run(_ automation: Automation, files: [URL], runID: UUID = UUID()) async -> Result? {
    await execute(automation, files: files, source: .capture, runID: runID)
  }

  /// Runs the steps on files handed in by a trigger. No capture, no canvas
  /// preset, and no new History entry when the files already have one.
  @discardableResult
  func run(
    _ automation: Automation,
    input: AutomationInput,
    invocation: AutomationInvocation,
    runID: UUID = UUID()
  ) async -> Result? {
    logStart(automation, runID: runID, invocation: invocation, source: "input")
    return await execute(automation, files: input.files, source: .input(input), runID: runID)
  }

  private func execute(_ automation: Automation, files: [URL], source: RunSource, runID: UUID) async -> Result? {
    let existing = files.filter { FileManager.default.fileExists(atPath: $0.path) }
    guard !existing.isEmpty else {
      DiagnosticLogger.shared.log(.error, .action, "Automation run skipped: file missing", context: ["runID": runID.uuidString])
      return nil
    }

    var state = AutomationRunState(runID: runID, automation: automation, files: existing)
    for file in existing {
      state.fileKinds[file] = AutomationFileKind.of(file) ?? .image
    }

    let recordsHistory: Bool
    switch source {
    case .capture:
      recordsHistory = true
      for file in existing {
        if let sessionData = environment.prepareScreenshot(file) {
          state.sessionData[file] = sessionData
        }
      }
    case .input(let input):
      recordsHistory = !input.isAlreadyInHistory
      if let itemID = input.sourceQuickAccessItemID, let file = state.primaryFile {
        state.quickAccessItemIDs[file] = itemID
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

      let handler = AutomationStepRegistry.handler(for: action.kind)
      let stepFiles = existing.filter { handler.accepts.contains(state.kind(of: $0)) }
      guard !stepFiles.isEmpty else {
        DiagnosticLogger.shared.log(
          .warning,
          .action,
          "Automation step skipped: file kind not accepted",
          context: ["runID": runID.uuidString, "step": action.kind.rawValue]
        )
        continue
      }

      let startedAt = now()
      do {
        try await handler.run(action, files: stepFiles, state: &state, environment: environment)
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

    if recordsHistory {
      for file in existing {
        await environment.recordHistory(file, kind: state.kind(of: file))
      }
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
      state.ownPasteboardChangeCount = AutomationStepCopy.copy(state.files, state: state, environment: environment)
      state.didCopyImage = true
    }
    if state.quickAccessItemIDs.isEmpty, let file = state.primaryFile,
       let itemID = await environment.showQuickAccess(
         file,
         kind: state.kind(of: file),
         sessionData: state.sessionData[file]
       )
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
      return (state.isImageOnly ? L10n.Automations.resultImageCopied : L10n.Automations.resultFileCopied, false)
    }
    return (L10n.Automations.resultCaptureSaved, false)
  }

  private func pruneStaleRuns() {
    let cutoff = now().addingTimeInterval(-Self.pendingLifetime)
    let stale = pendingRuns.filter { $0.value.startedAt < cutoff }
    for (runID, pending) in stale {
      pendingRuns.removeValue(forKey: runID)
      pending.onFinish?(.cancelled)
    }
  }

  private func logStart(_ automation: Automation, runID: UUID, invocation: AutomationInvocation, source: String) {
    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Automation run started",
      context: [
        "automation": automation.id.uuidString,
        "runID": runID.uuidString,
        "invocation": invocation.rawValue,
        "source": source,
      ]
    )
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
