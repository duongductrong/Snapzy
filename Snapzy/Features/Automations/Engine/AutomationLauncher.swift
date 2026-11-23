//
//  AutomationLauncher.swift
//  Snapzy
//
//  The one entry point every trigger uses (hotkey, URL scheme, CLI, menu bar,
//  Quick Access, History, Shortcuts). Resolves the automation, applies the
//  gates, then either runs the steps on handed-in files or starts the capture
//  and waits for it to finish.
//

import Foundation

/// Starts the capture of a capture-sourced automation. Implemented by
/// `ScreenCaptureViewModel`; a seam so the launcher is testable.
@MainActor
protocol AutomationCaptureStarting: AnyObject {
  /// Why a capture cannot start right now, or `nil` when it can. May prompt
  /// for permission as a side effect.
  func automationCaptureBlocker() -> AutomationLaunchRejection?
  /// Starts the capture. The capture must eventually complete or abandon `routing`.
  func startAutomationCapture(spec: AutomationCaptureSpec, routing: PostCaptureRouting)
}

@MainActor
final class AutomationLauncher {
  static let shared = AutomationLauncher(
    store: .shared,
    runner: .shared,
    isURLSchemeEnabled: {
      UserDefaults.standard.object(forKey: PreferencesKeys.urlSchemeEnabled) as? Bool ?? true
    },
    readClipboardImage: {
      ClipboardHelper.readImageFile(into: TempCaptureManager.shared.tempCaptureDirectory)
    }
  )

  /// Set once at launch to the app's capture view model.
  weak var captureStarter: AutomationCaptureStarting?

  private let store: AutomationStore
  private let runner: AutomationRunner
  private let isURLSchemeEnabled: () -> Bool
  /// Saves the clipboard image as a new file (clipboard-image source); `nil` when there is none.
  private let readClipboardImage: () -> URL?

  init(
    store: AutomationStore,
    runner: AutomationRunner,
    isURLSchemeEnabled: @escaping () -> Bool,
    readClipboardImage: @escaping () -> URL? = { nil }
  ) {
    self.store = store
    self.runner = runner
    self.isURLSchemeEnabled = isURLSchemeEnabled
    self.readClipboardImage = readClipboardImage
  }

  /// Runs `ref`. With `input`, the steps run on those files (no capture);
  /// otherwise the automation's capture starts and this returns once it finished.
  func launch(
    _ ref: AutomationRef,
    invocation: AutomationInvocation,
    input: AutomationInput? = nil
  ) async -> AutomationLaunchOutcome {
    let automation: Automation
    switch store.resolve(ref) {
    case .success(let resolved):
      automation = resolved
    case .failure(let rejection):
      return reject(rejection, invocation: invocation, automationID: nil)
    }

    if let rejection = gate(automation, invocation: invocation, input: input) {
      return reject(rejection, invocation: invocation, automationID: automation.id)
    }

    if let input, !input.files.isEmpty {
      guard let result = await runner.run(automation, input: input, invocation: invocation) else {
        return .cancelled
      }
      return .finished(result.report)
    }

    if automation.source == .clipboardImage {
      guard let file = readClipboardImage() else {
        return reject(.clipboardEmpty, invocation: invocation, automationID: automation.id)
      }
      let input = AutomationInput(files: [file], isAlreadyInHistory: false)
      guard let result = await runner.run(automation, input: input, invocation: invocation) else {
        return .cancelled
      }
      return .finished(result.report)
    }

    guard let spec = automation.captureSpec else {
      return reject(.needsFile, invocation: invocation, automationID: automation.id)
    }
    guard let starter = captureStarter else {
      return reject(.captureInProgress, invocation: invocation, automationID: automation.id)
    }
    if let blocker = starter.automationCaptureBlocker() {
      return reject(blocker, invocation: invocation, automationID: automation.id)
    }

    return await withCheckedContinuation { continuation in
      let routing = runner.begin(automation, invocation: invocation) { outcome in
        continuation.resume(returning: outcome)
      }
      starter.startAutomationCapture(spec: spec, routing: routing)
    }
  }

  /// Checks that don't need the capture system, in a fixed order.
  private func gate(
    _ automation: Automation,
    invocation: AutomationInvocation,
    input: AutomationInput?
  ) -> AutomationLaunchRejection? {
    guard automation.isEnabled else { return .disabled }
    if invocation.isExternal, !automation.externalInvocation { return .externalNotAllowed }
    if invocation == .urlScheme, !isURLSchemeEnabled() { return .urlSchemeDisabled }
    if automation.hasUnsupportedSource { return .unsupportedSource }
    // Never start a capture (or touch a file) for a chain that cannot run.
    if !AutomationChainValidator.blockingIssues(automation.migrated()).isEmpty { return .invalidChain }

    guard let files = input?.files, !files.isEmpty else {
      return automation.runsWithoutInput ? nil : .needsFile
    }
    for file in files {
      guard FileManager.default.fileExists(atPath: file.path) else {
        return .fileMissing(file.lastPathComponent)
      }
      guard let kind = AutomationFileKind.of(file) else {
        return .unsupportedFile(file.lastPathComponent)
      }
      guard automation.acceptsFile(of: kind) else {
        return .noStepAcceptsFile(kind)
      }
    }
    return nil
  }

  private func reject(
    _ rejection: AutomationLaunchRejection,
    invocation: AutomationInvocation,
    automationID: UUID?
  ) -> AutomationLaunchOutcome {
    var context = ["invocation": invocation.rawValue, "reason": rejection.code]
    if let automationID {
      context["automation"] = automationID.uuidString
    }
    DiagnosticLogger.shared.log(.info, .action, "Automation launch rejected", context: context)
    return .rejected(rejection)
  }
}
