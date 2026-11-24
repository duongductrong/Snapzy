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
//  transforms write into a per-run working directory, and a failed upload
//  leaves the image on the clipboard plus a Quick Access card to retry from.
//

import AppKit
import Foundation

@MainActor
final class AutomationRunner {
  static let shared = AutomationRunner(environment: LiveAutomationRunEnvironment())

  struct Result {
    let state: AutomationRunState
    let message: String
    let isError: Bool
    let outcome: AutomationRunRecord.Outcome

    var report: AutomationRunReport {
      AutomationRunReport(
        runID: state.runID,
        automationID: state.automation.id,
        files: state.inputFiles,
        link: state.linkText,
        message: message,
        isError: isError,
        text: state.payload.text,
        outputFiles: state.payload.savedFile.map { [$0] } ?? state.files
      )
    }
  }

  typealias FinishHandler = @MainActor (AutomationLaunchOutcome) -> Void

  private struct PendingRun {
    let automation: Automation
    let invocation: AutomationInvocation
    let startedAt: Date
    /// `nil` never expires (recordings run until the user stops them).
    let expiresAt: Date?
    /// Frontmost app when triggered; refined by the capture (`noteCaptureContext`).
    var app: AutomationAppSnapshot
    let onFinish: FinishHandler?
  }

  private enum RunSource {
    case capture
    /// A capture not started by an automation, running its default
    /// after-capture automation (milestone 6). Like `.capture`, but the
    /// capture mode is unknown.
    case standardCapture
    case input(AutomationInput)
  }

  /// Area selection can stay open a long time; older screenshot registrations are dropped.
  static let pendingLifetime: TimeInterval = 30 * 60

  private let environment: AutomationRunEnvironment
  private var pendingRuns: [UUID: PendingRun] = [:]
  private var runningTasks: [UUID: Task<StepLoopResult, Never>] = [:]
  private let now: () -> Date
  private let frontmostApp: () -> AutomationAppSnapshot

  /// `frontmostApp` wins over `frontmostAppName` (kept for tests that only care about the name).
  init(
    environment: AutomationRunEnvironment,
    now: @escaping () -> Date = Date.init,
    frontmostAppName: (() -> String?)? = nil,
    frontmostApp: (() -> AutomationAppSnapshot)? = nil
  ) {
    self.environment = environment
    self.now = now
    if let frontmostApp {
      self.frontmostApp = frontmostApp
    } else if let frontmostAppName {
      self.frontmostApp = { AutomationAppSnapshot(name: frontmostAppName()) }
    } else {
      self.frontmostApp = { AutomationAppSnapshot(CaptureContext.fromFrontmostApp()) }
    }
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
    let startedAt = now()
    let lifetime: TimeInterval? = automation.captureSpec?.mode.isRecording == true ? nil : Self.pendingLifetime
    pendingRuns[runID] = PendingRun(
      automation: automation,
      invocation: invocation,
      startedAt: startedAt,
      expiresAt: lifetime.map { startedAt.addingTimeInterval($0) },
      // Snapshot now: the capture overlay takes the frontmost status away.
      app: frontmostApp(),
      onFinish: onFinish
    )
    logStart(automation, runID: runID, invocation: invocation, source: "capture")
    if onFinish != nil, let lifetime {
      // A waiting caller (CLI, Shortcuts) must not hang if a capture path never reports back.
      Task { [weak self] in
        try? await Task.sleep(nanoseconds: UInt64(lifetime * 1_000_000_000))
        self?.expire(runID: runID)
      }
    }
    return .automation(runID: runID)
  }

  /// What the capture knows about its source (window under the selection, its
  /// app). Wins over the trigger-time snapshot for conditions and variables.
  func noteCaptureContext(_ context: CaptureContext) {
    guard case .automation(let runID) = context.postCaptureRouting, var pending = pendingRuns[runID] else { return }
    pending.app = pending.app.merged(with: AutomationAppSnapshot(context))
    pendingRuns[runID] = pending
  }

  /// The capture behind `routing` was cancelled or failed before saving a file.
  func abandon(routing: PostCaptureRouting) {
    CaptureToolbarController.shared.abandon(routing: routing)
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

  /// The automation a pending capture belongs to (recording toolbar chip, output mode).
  func pendingAutomation(for routing: PostCaptureRouting) -> Automation? {
    guard case .automation(let runID) = routing else { return nil }
    return pendingRuns[runID]?.automation
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
    let result = await execute(
      pending.automation,
      files: capturedURLs,
      source: .capture,
      runID: runID,
      invocation: pending.invocation,
      app: pending.app
    )
    pending.onFinish?(result.map { .finished($0.report) } ?? .cancelled)
  }

  /// Stops a running run between (or inside) steps. Files are kept; no fallback.
  func cancel(runID: UUID) {
    runningTasks[runID]?.cancel()
  }

  var hasRunningRuns: Bool { !runningTasks.isEmpty }

  // MARK: - Execution

  /// Runs the steps on freshly captured files. `quiet`: no progress HUD and
  /// only failures logged (instant capture toolbar actions).
  @discardableResult
  func run(
    _ automation: Automation,
    files: [URL],
    invocation: AutomationInvocation = .hotkey,
    quiet: Bool = false,
    runID: UUID = UUID()
  ) async -> Result? {
    await execute(automation, files: files, source: .capture, runID: runID, invocation: invocation, app: frontmostApp(), quiet: quiet)
  }

  /// Milestone 6: a standard capture runs its default after-capture automation.
  /// `pinToScreen` / `skipQuickAccess` are the capture path's runtime flags.
  /// While the automation is still the simple matrix form the run is quiet:
  /// no progress HUD, and only failures reach the activity log.
  @discardableResult
  func runDefault(
    _ automation: Automation,
    type: CaptureType,
    files: [URL],
    pinToScreen: Bool = false,
    skipQuickAccess: Bool = false,
    runID: UUID = UUID(),
    environment: AutomationRunEnvironment? = nil
  ) async -> Result? {
    var runtime = automation.migrated()
    if automation.needsReview {
      // An imported custom pipeline with webhook / script / AI steps waits for
      // the editor's review: until then the simple steps it implies run.
      DiagnosticLogger.shared.log(.warning, .action, "Default automation needs review; running its simple form")
      runtime = AutomationSystemDefault.make(
        for: type,
        matrix: AutomationSystemDefault.lenientMatrix(automation, type: type),
        reusing: automation
      )
    }
    // Decided before the runtime Pin / Quick Access changes, which aren't customizations.
    let quiet = !runtime.isCustomizedSystemDefault
    runtime.steps = AutomationSystemDefault.runtimeSteps(
      runtime.steps,
      type: type,
      pinToScreen: pinToScreen,
      skipQuickAccess: skipQuickAccess
    )
    return await execute(
      runtime,
      files: files,
      source: .standardCapture,
      runID: runID,
      invocation: .afterCapture,
      app: frontmostApp(),
      quiet: quiet,
      environment: environment
    )
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
    return await execute(
      automation,
      files: input.files,
      source: .input(input),
      runID: runID,
      invocation: invocation,
      // Handed-in files have no capture app; the name still feeds `{appName}`.
      app: AutomationAppSnapshot(name: frontmostApp().name)
    )
  }

  private func execute(
    _ snapshot: Automation,
    files: [URL],
    source: RunSource,
    runID: UUID,
    invocation: AutomationInvocation,
    app: AutomationAppSnapshot,
    quiet: Bool = false,
    environment override: AutomationRunEnvironment? = nil
  ) async -> Result? {
    let environment = override ?? self.environment
    let automation = snapshot.migrated()
    let existing = files.filter { FileManager.default.fileExists(atPath: $0.path) }
    guard !existing.isEmpty else {
      DiagnosticLogger.shared.log(.error, .action, "Automation run skipped: file missing", context: ["runID": runID.uuidString])
      return nil
    }

    let startedAt = now()
    let context = AutomationRunContext(
      runID: runID,
      automationID: automation.id,
      automationName: automation.displayName,
      invocation: invocation,
      startedAt: startedAt,
      appName: app.name,
      windowTitle: app.windowTitle,
      bundleID: app.bundleID,
      captureMode: {
        if case .capture = source { return automation.captureSpec?.mode }
        return nil
      }(),
      workingDirectory: AutomationRunContext.workingDirectory(for: runID)
    )
    let inputFiles = existing.map { AutomationFile(url: $0, kind: AutomationFileKind.of($0) ?? .image) }
    var state = AutomationRunState(runID: runID, automation: automation, files: inputFiles, context: context)

    let recordsHistory: Bool
    switch source {
    case .capture, .standardCapture:
      recordsHistory = true
      // An explicit canvas preset step decides instead of the default preset.
      if !automation.contains(.applyCanvasPreset) {
        for file in inputFiles where file.kind == .image {
          if let sessionData = environment.prepareScreenshot(file.url) {
            state.sessionData[file.url] = sessionData
          }
        }
      }
    case .input(let input):
      recordsHistory = !input.isAlreadyInHistory
      if let itemID = input.sourceQuickAccessItemID, let file = state.primaryFile {
        state.quickAccessItemIDs[file] = itemID
      }
    }

    if !quiet {
      environment.runDidUpdate(.started(runID: runID, name: automation.displayName))
    }
    let initialState = state
    let task = Task { @MainActor [environment, now = self.now] () -> StepLoopResult in
      await Self.runSteps(
        automation.steps,
        state: initialState,
        chain: [automation.id],
        environment: environment,
        now: now
      )
    }
    runningTasks[runID] = task
    let finished = await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
    runningTasks.removeValue(forKey: runID)
    state = finished.state
    let steps = finished.steps

    if recordsHistory {
      for file in inputFiles {
        await environment.recordHistory(file.url, kind: file.kind)
      }
    }
    // CLI / Shortcuts / URL callers get the output paths back: keep those files.
    if invocation.isExternal, state.payload.savedFile == nil {
      state.retain(state.files)
    }
    cleanUpWorkingDirectory(state)

    // Nested runs count by their own steps: a Run Automation record only stands for itself without children.
    let leaves = steps.flatMap(\.leaves)
    let outcome = Self.outcome(steps: leaves, cancelled: finished.cancelled)
    let (message, isError) = outcomeMessage(for: state, steps: leaves, cancelled: finished.cancelled)
    if !finished.cancelled, state.wantsNotification || isError {
      await environment.notify(
        title: automation.displayName,
        body: message,
        isError: isError,
        context: AutomationNotificationContext(
          outcome: isError ? .failed : .succeeded,
          automationID: automation.id,
          inputFiles: state.inputFiles,
          link: state.payload.link,
          savedFile: state.payload.savedFile
        )
      )
    }
    if !quiet {
      environment.runDidUpdate(.finished(runID: runID))
    }

    let durationMs = Int(now().timeIntervalSince(startedAt) * 1000)
    // A plain after-capture run is every capture: only its failures are worth a log entry.
    if !quiet || outcome != .succeeded {
      environment.recordRun(AutomationRunRecord(
        id: runID,
        automationID: automation.id,
        automationName: automation.displayName,
        invocation: invocation.rawValue,
        startedAt: startedAt,
        durationMs: durationMs,
        outcome: outcome,
        steps: steps,
        inputFiles: state.inputFiles.map(\.path),
        link: state.payload.link?.absoluteString,
        text: state.payload.text,
        savedPaths: state.payload.savedFile.map { [$0.path] } ?? [],
        warnings: state.warnings.map { AutomationSecretStore.mask($0, values: state.secretValues) }
      ))
    }

    DiagnosticLogger.shared.log(
      isError ? .warning : .info,
      .action,
      "Automation run finished",
      context: [
        "automation": automation.id.uuidString,
        "runID": runID.uuidString,
        "files": "\(existing.count)",
        "outcome": outcome.rawValue,
        "duration_ms": "\(durationMs)",
        "app": state.context.bundleID ?? "",
        "imageCopied": state.didCopyImage ? "true" : "false",
        "linkCopied": state.didCopyLink ? "true" : "false",
        "uploadFailed": state.uploadFailure == nil ? "false" : "true",
      ]
    )
    return Result(state: state, message: message, isError: isError, outcome: outcome)
  }

  private struct StepLoopResult {
    var state: AutomationRunState
    var steps: [AutomationRunRecord.StepRecord]
    var cancelled: Bool
    /// A failing step with policy Stop ended this level.
    var aborted = false
  }

  /// Where the loop goes after a control step.
  private enum ControlFlow {
    case next
    /// Skip the next `n` steps of the list.
    case skip(Int)
    /// End this level (a nested run returns to its parent).
    case stop
    case cancel
  }

  private typealias StepRecord = AutomationRunRecord.StepRecord

  /// The step loop. Runs in its own task so `cancel(runID:)` can stop it.
  /// `chain` holds the automations being run, outermost first (cycle and depth guard).
  private static func runSteps(
    _ steps: [AutomationStep],
    state initial: AutomationRunState,
    chain: [UUID],
    environment: AutomationRunEnvironment,
    now: () -> Date
  ) async -> StepLoopResult {
    var state = initial
    var records: [StepRecord] = []
    var cancelled = false
    var aborted = false
    let runID = state.runID
    /// Steps at an index up to this one were skipped by a condition.
    var skipThrough = -1

    for (index, step) in steps.enumerated() where step.isEnabled {
      if Task.isCancelled {
        cancelled = true
        break
      }
      if index <= skipThrough {
        records.append(StepRecord(
          kind: stepKindLabel(step),
          durationMs: 0,
          status: .skipped,
          error: nil,
          detail: L10n.Automations.logSkippedByCondition
        ))
        continue
      }
      guard let action = step.action else {
        let kind = stepKindLabel(step)
        DiagnosticLogger.shared.log(
          .warning,
          .action,
          "Automation step skipped: unsupported kind",
          context: ["runID": runID.uuidString, "kind": kind]
        )
        records.append(.init(kind: kind, durationMs: 0, status: .skipped, error: nil))
        continue
      }

      if action.kind.isControl {
        environment.runDidUpdate(.step(runID: runID, title: action.kind.displayName))
        let startedAt = now()
        var flow = ControlFlow.next
        var record: StepRecord
        do {
          let result = try await runControl(action, state: &state, chain: chain, environment: environment, now: now)
          flow = result.flow
          record = result.record
        } catch {
          let message = AutomationSecretStore.mask(error.localizedDescription, values: state.secretValues)
          record = StepRecord(kind: action.kind.rawValue, durationMs: 0, status: .failed, error: message)
        }
        let duration = milliseconds(since: startedAt, now: now)
        record = StepRecord(
          kind: record.kind,
          durationMs: duration,
          status: record.status,
          error: record.error,
          detail: record.detail,
          children: record.children
        )
        logStep(action, runID: runID, durationMs: duration, error: record.error)
        records.append(record)
        if case .cancel = flow {
          cancelled = true
          break
        }
        if record.status == .failed, step.onFailure == .stop {
          aborted = true
          break
        }
        if case .stop = flow { break }
        if case .skip(let count) = flow { skipThrough = index + count }
        continue
      }

      let handler = AutomationStepRegistry.handler(for: action.kind)
      let accepted = handler.accepts(action)
      let stepFiles = state.payload.files
        .filter { accepted.contains(AutomationPayloadKind($0.kind)) }
        .map(\.url)
      let hasOtherInput = !accepted.isDisjoint(with: state.payload.kinds.subtracting(AutomationPayloadKind.files))
      guard !stepFiles.isEmpty || hasOtherInput else {
        DiagnosticLogger.shared.log(
          .warning,
          .action,
          "Automation step skipped: payload kind not accepted",
          context: ["runID": runID.uuidString, "step": action.kind.rawValue]
        )
        records.append(.init(kind: action.kind.rawValue, durationMs: 0, status: .skipped, error: nil))
        continue
      }

      environment.runDidUpdate(.step(runID: runID, title: action.kind.displayName))
      let startedAt = now()
      state.stepDetail = nil
      do {
        try await handler.run(action, files: stepFiles, state: &state, environment: environment)
        let duration = milliseconds(since: startedAt, now: now)
        logStep(action, runID: runID, durationMs: duration, error: nil)
        records.append(.init(
          kind: action.kind.rawValue,
          durationMs: duration,
          status: .succeeded,
          error: nil,
          detail: state.stepDetail
        ))
        state.stepDetail = nil
      } catch {
        let duration = milliseconds(since: startedAt, now: now)
        if error is CancellationError || Task.isCancelled {
          cancelled = true
          records.append(.init(kind: action.kind.rawValue, durationMs: duration, status: .skipped, error: nil))
          break
        }
        // Secrets a step resolved never reach the log, the run record or a notification.
        let message = AutomationSecretStore.mask(error.localizedDescription, values: state.secretValues)
        logStep(action, runID: runID, durationMs: duration, error: message)
        records.append(.init(
          kind: action.kind.rawValue,
          durationMs: duration,
          status: .failed,
          error: message
        ))
        if action.kind == .upload || action.kind == .uploadAndCopyLink {
          state.uploadFailure = (error as? AutomationStepError) == .cloudNotConfigured
            ? .notConfigured
            : .failed(message)
          await applyUploadFallback(&state, environment: environment)
        }
        if step.onFailure == .stop {
          aborted = true
          break
        }
      }
    }
    return StepLoopResult(state: state, steps: records, cancelled: cancelled, aborted: aborted)
  }

  /// Runs a control step. A nested run's failure comes back as a `.failed`
  /// record (with the nested steps as children), not as a thrown error.
  private static func runControl(
    _ action: AutomationStepAction,
    state: inout AutomationRunState,
    chain: [UUID],
    environment: AutomationRunEnvironment,
    now: () -> Date
  ) async throws -> (record: StepRecord, flow: ControlFlow) {
    let kind = action.kind.rawValue
    switch action {
    case .condition(let config):
      if AutomationConditionEvaluator.evaluate(config, state: state) {
        return (StepRecord(kind: kind, durationMs: 0, status: .succeeded, error: nil, detail: L10n.Automations.logConditionMet), .next)
      }
      let detail = L10n.Automations.logConditionNotMet
      switch config.otherwise {
      case .stop:
        return (StepRecord(kind: kind, durationMs: 0, status: .succeeded, error: nil, detail: detail), .stop)
      case .skip(let count):
        return (StepRecord(kind: kind, durationMs: 0, status: .succeeded, error: nil, detail: detail), .skip(count))
      }

    case .stop:
      return (StepRecord(kind: kind, durationMs: 0, status: .succeeded, error: nil), .stop)

    case .runAutomation(let config):
      guard let targetID = config.automationID else {
        throw AutomationStepError.automationUnavailable(L10n.Automations.unknownAutomation)
      }
      return try await runNested(targetID, kind: kind, state: &state, chain: chain, environment: environment, now: now, then: .next)

    case .ask(let config):
      var choices: [AutomationPickerChoice] = []
      for choice in config.choices {
        switch choice {
        case .automation(let id):
          // Unavailable targets are left out instead of failing the whole picker.
          guard let target = environment.automation(id: id), target.isEnabled, !target.needsReview,
                !target.hasUnsupportedSource, !chain.contains(id) else { continue }
          choices.append(AutomationPickerChoice(
            value: .automation(id),
            title: target.displayName,
            symbol: target.symbol ?? target.sourceSymbol
          ))
        case .continueRun:
          choices.append(AutomationPickerChoice(value: .continueRun, title: L10n.Automations.askContinue, symbol: "arrow.down.circle"))
        case .stopRun:
          choices.append(AutomationPickerChoice(value: .stopRun, title: L10n.Automations.askStop, symbol: "stop.circle"))
        }
      }
      guard !choices.isEmpty else { throw AutomationStepError.noChoices }
      environment.runDidUpdate(.step(runID: state.runID, title: L10n.Automations.waitingForChoice))
      let title = config.prompt.trimmingCharacters(in: .whitespaces).isEmpty
        ? state.context.automationName
        : config.prompt
      let thumbnail = state.payload.files.first { $0.kind == .image }?.url
      guard let picked = await environment.pick(title: title, thumbnail: thumbnail, choices: choices) else {
        // Never lose a capture: a dismissed picker leaves a Quick Access card for it.
        if state.context.captureMode != nil || state.context.invocation == .afterCapture, state.quickAccessItemIDs.isEmpty, !state.didCopyImage,
           let original = state.inputFiles.first,
           let itemID = await environment.showQuickAccess(
             original,
             kind: AutomationFileKind.of(original) ?? .image,
             sessionData: state.sessionData[original]
           )
        {
          state.quickAccessItemIDs[original] = itemID
        }
        return (StepRecord(kind: kind, durationMs: 0, status: .skipped, error: nil, detail: L10n.Automations.logChoiceCancelled), .cancel)
      }
      switch picked.value {
      case .continueRun:
        return (StepRecord(kind: kind, durationMs: 0, status: .succeeded, error: nil, detail: picked.title), .next)
      case .stopRun:
        return (StepRecord(kind: kind, durationMs: 0, status: .succeeded, error: nil, detail: picked.title), .stop)
      case .automation(let id):
        // The choice is the outcome: the parent ends after it.
        return try await runNested(id, kind: kind, state: &state, chain: chain, environment: environment, now: now, then: .stop)
      }

    default:
      return (StepRecord(kind: kind, durationMs: 0, status: .skipped, error: nil), .next)
    }
  }

  /// Runs `targetID`'s steps (not its source) on the current payload.
  private static func runNested(
    _ targetID: UUID,
    kind: String,
    state: inout AutomationRunState,
    chain: [UUID],
    environment: AutomationRunEnvironment,
    now: () -> Date,
    then flow: ControlFlow
  ) async throws -> (record: StepRecord, flow: ControlFlow) {
    guard let target = environment.automation(id: targetID) else {
      throw AutomationStepError.automationUnavailable(L10n.Automations.unknownAutomation)
    }
    guard target.isEnabled, !target.needsReview, !target.hasUnsupportedSource else {
      throw AutomationStepError.automationUnavailable(target.displayName)
    }
    guard !chain.contains(targetID), chain.count <= AutomationControlLimits.maxDepth else {
      throw AutomationStepError.recursionLimit
    }
    // The launcher checked trust when the run started; the target may have changed since
    // (a capture can wait in selection), so check code steps again.
    if target.containsCodeSteps {
      guard environment.allowsCodeSteps else { throw AutomationStepError.codeStepsDisabled }
      let invocation = state.context.invocation
      if invocation == .urlScheme || invocation == .appIntent, !state.automation.allowExternalCode {
        throw AutomationStepError.codeStepsDisabled
      }
    }
    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Automation nested run started",
      context: ["runID": state.runID.uuidString, "target": targetID.uuidString, "depth": "\(chain.count)"]
    )
    let nested = await runSteps(
      target.migrated().steps,
      state: state,
      chain: chain + [targetID],
      environment: environment,
      now: now
    )
    state = nested.state
    if nested.cancelled {
      return (StepRecord(kind: kind, durationMs: 0, status: .skipped, error: nil, detail: target.displayName, children: nested.steps), .cancel)
    }
    if nested.aborted {
      let error = nested.steps.flatMap(\.leaves).first { $0.status == .failed }?.error
      return (StepRecord(kind: kind, durationMs: 0, status: .failed, error: error, detail: target.displayName, children: nested.steps), flow)
    }
    return (StepRecord(kind: kind, durationMs: 0, status: .succeeded, error: nil, detail: target.displayName, children: nested.steps), flow)
  }

  /// A failed upload must still leave something to paste and a way to retry.
  private static func applyUploadFallback(_ state: inout AutomationRunState, environment: AutomationRunEnvironment) async {
    if !state.didCopyImage {
      state.ownPasteboardChangeCount = AutomationStepCopy.copy(state.files, state: state, environment: environment)
      state.didCopyImage = true
      state.retain(state.files)
    }
    if state.quickAccessItemIDs.isEmpty, let file = state.primaryFile,
       let itemID = await environment.showQuickAccess(
         file,
         kind: state.kind(of: file),
         sessionData: state.sessionData[file]
       )
    {
      state.quickAccessItemIDs[file] = itemID
      state.retain([file])
    }
  }

  /// Deletes working files nothing still shows; the directory goes when empty.
  private func cleanUpWorkingDirectory(_ state: AutomationRunState) {
    let directory = state.context.workingDirectory
    let fileManager = FileManager.default
    guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
    let retained = Set(state.retainedFiles.map(\.standardizedFileURL.path))
    for file in contents where !retained.contains(file.standardizedFileURL.path) {
      try? fileManager.removeItem(at: file)
    }
    if (try? fileManager.contentsOfDirectory(atPath: directory.path))?.isEmpty ?? true {
      try? fileManager.removeItem(at: directory)
    }
  }

  private static func outcome(steps: [AutomationRunRecord.StepRecord], cancelled: Bool) -> AutomationRunRecord.Outcome {
    if cancelled { return .cancelled }
    guard let failedIndex = steps.firstIndex(where: { $0.status == .failed }) else { return .succeeded }
    // A failure followed by steps that still ran is partial; a failure that ended the run is failed.
    return steps[(failedIndex + 1)...].contains { $0.status == .succeeded } ? .partial : .failed
  }

  private func outcomeMessage(
    for state: AutomationRunState,
    steps: [AutomationRunRecord.StepRecord],
    cancelled: Bool
  ) -> (String, Bool) {
    if cancelled {
      return (L10n.Automations.resultCancelled, false)
    }
    switch state.uploadFailure {
    case .notConfigured?:
      return (L10n.Automations.resultCloudNotConfigured, true)
    case .failed?:
      return (L10n.Automations.resultUploadFailed, true)
    case nil:
      break
    }
    if let failed = steps.first(where: { $0.status == .failed }) {
      let title = AutomationStepKind(rawValue: failed.kind)?.displayName ?? failed.kind
      return (L10n.Automations.resultStepFailed(title, failed.error ?? ""), true)
    }
    switch state.lastDelivery {
    case .linkCopied?:
      return (L10n.Automations.resultLinkCopied, false)
    case .linkReady?:
      return (state.didCopyLink ? L10n.Automations.resultLinkCopied : L10n.Automations.resultLinkReady, false)
    case .textCopied?:
      return (L10n.Automations.resultTextCopied, false)
    case .saved(let url)?:
      return (L10n.Automations.resultSavedTo(url.lastPathComponent), false)
    case .imageCopied?:
      return (L10n.Automations.resultImageCopied, false)
    case .fileCopied?:
      return (state.isImageOnly ? L10n.Automations.resultImageCopied : L10n.Automations.resultFileCopied, false)
    case nil:
      return (L10n.Automations.resultCaptureSaved, false)
    }
  }

  private func pruneStaleRuns() {
    let current = now()
    let stale = pendingRuns.filter { $0.value.expiresAt.map { $0 < current } ?? false }
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

  private static func stepKindLabel(_ step: AutomationStep) -> String {
    if case .unsupported(let raw) = step.content { return raw.kind ?? "unknown" }
    return step.action?.kind.rawValue ?? "unknown"
  }

  private static func milliseconds(since start: Date, now: () -> Date) -> Int {
    max(0, Int(now().timeIntervalSince(start) * 1000))
  }

  private static func logStep(_ action: AutomationStepAction, runID: UUID, durationMs: Int, error: String?) {
    var context = [
      "runID": runID.uuidString,
      "step": action.kind.rawValue,
      "duration_ms": "\(durationMs)",
    ]
    if let error {
      context["error"] = error
      DiagnosticLogger.shared.log(.warning, .action, "Automation step failed", context: context)
    } else {
      DiagnosticLogger.shared.log(.debug, .action, "Automation step finished", context: context)
    }
  }
}
