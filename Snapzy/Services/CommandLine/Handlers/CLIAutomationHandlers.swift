//
//  CLIAutomationHandlers.swift
//  Snapzy
//
//  `automation.list` and `automation.run`: a snapshot of the automation store,
//  and `AutomationLauncher` with `invocation: .cli`. The launcher owns every
//  gate (enabled, external invocation, file kinds, permission); this file only
//  translates its outcome into wire models and `CLIError`s.
//

import Foundation
import SnapzyCLIProtocol

nonisolated struct CLIAutomationListHandler: CLIRequestHandling {
  func handle(_: CLIEmpty, context _: CLIRequestContext) async throws -> CLIAutomationList {
    await CLIAutomationBridge.list()
  }
}

nonisolated struct CLIAutomationRunHandler: CLIRequestHandling {
  func handle(_ params: CLIAutomationRunParams, context: CLIRequestContext) async throws -> CLIAutomationRunResult {
    try await CLIAutomationBridge.run(params, caller: context.caller)
  }
}

@MainActor
enum CLIAutomationBridge {
  static let externalSettingHint =
    "Enable 'Allow URL scheme, command line and Shortcuts' for this automation in Settings → Automations"

  // MARK: - List

  /// Every automation, runnable ones (enabled + external) first, each group in Settings order.
  static func list() -> CLIAutomationList {
    list(AutomationStore.shared.automations)
  }

  static func list(_ automations: [Automation]) -> CLIAutomationList {
    let summaries = automations.map(summary)
    return CLIAutomationList(
      automations: summaries.filter(\.isRunnable) + summaries.filter { !$0.isRunnable }
    )
  }

  static func summary(_ automation: Automation) -> CLIAutomationSummary {
    CLIAutomationSummary(
      id: automation.id.uuidString,
      name: automation.displayName,
      source: sourceName(automation.source),
      steps: automation.activeActions.map(\.kind.rawValue),
      enabled: automation.isEnabled,
      external: automation.externalInvocation
    )
  }

  static func sourceName(_ source: AutomationSource) -> String {
    switch source {
    case .capture(let spec): spec.mode.rawValue
    case .input: "input"
    case .clipboardImage: "clipboard"
    case .unsupported: "unsupported"
    }
  }

  // MARK: - Run

  static func run(_ params: CLIAutomationRunParams, caller: CLICallerIdentity?) async throws -> CLIAutomationRunResult {
    let input = try input(for: params.files)
    let ref = AutomationRef(params.ref)
    // Only for a cancelled run, which reports no automation of its own.
    let resolvedID = try? AutomationStore.shared.resolve(ref).get().id

    CLIActivityIndicator.shared.begin(caller: caller)
    defer { CLIActivityIndicator.shared.end() }
    let outcome = await AutomationLauncher.shared.launch(ref, invocation: .cli, input: input)
    return try result(for: outcome, ref: params.ref, automationID: resolvedID)
  }

  /// `nil` (capture) when no files were passed. Paths must be absolute: the CLI resolves them.
  static func input(for files: [String]?) throws -> AutomationInput? {
    guard let files, !files.isEmpty else { return nil }
    let urls = try files.map { path -> URL in
      guard path.hasPrefix("/") else {
        throw CLIError(.invalidArguments, "File paths must be absolute: \(path)")
      }
      return URL(fileURLWithPath: path).standardizedFileURL
    }
    return AutomationInput(files: urls, isAlreadyInHistory: false)
  }

  static func result(
    for outcome: AutomationLaunchOutcome,
    ref: String,
    automationID: UUID?
  ) throws -> CLIAutomationRunResult {
    switch outcome {
    case .finished(let report):
      return CLIAutomationRunResult(
        runId: report.runID.uuidString,
        automationId: report.automationID.uuidString,
        state: .finished,
        files: report.outputFiles.map(\.path),
        link: report.link,
        message: report.message,
        isError: report.isError,
        text: report.text
      )
    case .cancelled:
      return CLIAutomationRunResult(
        runId: "",
        automationId: automationID?.uuidString ?? "",
        state: .cancelled,
        message: "Cancelled"
      )
    case .rejected(let rejection):
      throw cliError(for: rejection, ref: ref)
    }
  }

  // MARK: - Rejections

  /// One `CLIError` per rejection. Codes pick the exit status; messages are English like all CLI output.
  static func cliError(for rejection: AutomationLaunchRejection, ref rawRef: String) -> CLIError {
    let ref = "\"\(rawRef.trimmingCharacters(in: .whitespacesAndNewlines))\""
    switch rejection {
    case .notFound:
      return CLIError(.targetNotFound, "No automation \(ref)", hint: "Run `snapzy automation list` for names and ids")
    case .ambiguousName(let ids):
      return CLIError(
        .invalidArguments,
        "Several automations are named \(ref): \(ids.map(\.uuidString).joined(separator: ", "))",
        hint: "Pass one of the ids instead, or rename the others in Settings → Automations"
      )
    case .disabled:
      return CLIError(.disabled, "Automation \(ref) is turned off", hint: "Turn it on in Settings → Automations")
    case .externalNotAllowed:
      return CLIError(.notAuthorized, "Automation \(ref) cannot be run from the command line",
                      hint: externalSettingHint)
    case .urlSchemeDisabled:
      return CLIError(.disabled, "Running automations from links is turned off",
                      hint: "Turn on the URL scheme in Settings → Advanced")
    case .unsupportedSource:
      return CLIError(.versionMismatch, "Automation \(ref) was made by a newer Snapzy",
                      hint: "Update Snapzy to run it")
    case .needsFile:
      return CLIError(.invalidArguments, "Automation \(ref) runs on files, not a new capture",
                      hint: "Pass an image or video with --file")
    case .unsupportedFile(let name):
      return CLIError(.invalidArguments, "\(name) is not an image, GIF or video",
                      hint: "Pass PNG, JPEG, HEIC, GIF, MOV or MP4 files")
    case .noStepAcceptsFile(let kind):
      return CLIError(.invalidArguments, "No enabled step of automation \(ref) works on \(kind.rawValue) files",
                      hint: "Pass another file, or add a matching step in Settings → Automations")
    case .fileMissing(let name):
      return CLIError(.targetNotFound, "No file named \(name)", hint: "Check the --file path")
    case .permissionRequired:
      return CLIError(.permissionDenied, "Snapzy needs Screen Recording permission to capture",
                      hint: "Grant it in System Settings → Privacy & Security → Screen Recording, then retry")
    case .captureInProgress:
      return CLIError(.busy, "Another capture is in progress", hint: "Retry when it finishes")
    case .clipboardEmpty:
      return CLIError(.invalidArguments, "The clipboard holds no image", hint: "Copy an image, then retry")
    case .invalidChain:
      return CLIError(.invalidArguments, "Automation \(ref) has a step with nothing to work on",
                      hint: "Fix the steps marked in Settings → Automations")
    case .needsReview:
      return CLIError(.disabled, "Automation \(ref) was imported with network or script steps and needs a review",
                      hint: "Open it in Settings → Automations, check the steps and save")
    case .codeStepsDisabled:
      return CLIError(.disabled, "Automation \(ref) runs a script or Shortcut, and script steps are turned off",
                      hint: "Allow them in Settings → Automations → Advanced")
    case .externalCodeNotAllowed:
      return CLIError(.notAuthorized, "Automation \(ref) runs a script and cannot be started from outside Snapzy",
                      hint: "Allow other apps to run its script steps in the automation's editor")
    }
  }
}
