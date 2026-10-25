//
//  CLIAuthorizationCoordinator.swift
//  Snapzy
//
//  Decides whether a CLI caller may run a command: a stored decision, or a
//  prompt the first time an app asks. Prompts are shown one at a time, and
//  concurrent requests from the same app share one prompt.
//

import Foundation
import SnapzyCLIProtocol

nonisolated enum CLIAuthorizationOutcome: Equatable, Sendable {
  case allowed
  /// "Allow Once": allowed for the rest of this connection only.
  case allowedForConnection
  case denied(CLIError)
}

nonisolated protocol CLIAuthorizing: Sendable {
  func authorize(_ context: CLIRequestContext, method: String) async -> CLIAuthorizationOutcome
}

enum CLIAuthorizationPromptResult: Equatable {
  case alwaysAllow
  case allowOnce
  case deny
  case timedOut
}

@MainActor
protocol CLIAuthorizationPrompting {
  func ask(_ caller: CLICallerIdentity, command: String) -> CLIAuthorizationPromptResult
}

@MainActor
final class CLIAuthorizationCoordinator {
  static let shared = CLIAuthorizationCoordinator(store: .shared, prompter: CLIAuthorizationPromptController())

  /// Answered before authorization so `snapzy doctor` can explain what is missing.
  nonisolated static let exemptMethods: Set<String> = [CLIMethod.hello.rawValue, CLIMethod.systemStatus.rawValue]

  private let store: CLIAuthorizationStore
  private let prompter: CLIAuthorizationPrompting
  private var promptsByCaller: [String: Task<CLIAuthorizationPromptResult, Never>] = [:]
  private var lastPrompt: Task<CLIAuthorizationPromptResult, Never>?
  /// Requests still waiting on each caller's prompt. A queued prompt whose
  /// requests all went away (CLI killed, timed out) is never shown.
  private var waiters: [String: [Waiter]] = [:]

  /// Distinct apps that may wait for a prompt at once; more are refused so a
  /// script cannot queue prompts until the user gives in.
  static let maxPendingPrompts = 3

  /// Freed after every prompt, so it needs the explicit deinit too.
  private final class Waiter {
    var isCancelled = false

    /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
    /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
    deinit {}
  }

  init(store: CLIAuthorizationStore, prompter: CLIAuthorizationPrompting) {
    self.store = store
    self.prompter = prompter
  }

  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  deinit {}

  func authorize(caller: CLICallerIdentity?, method: String,
                 allowedForConnection: Bool) async -> CLIAuthorizationOutcome {
    guard !Self.exemptMethods.contains(method) else { return .allowed }
    guard let caller else {
      return .denied(CLIError(.notAuthorized, "Snapzy could not tell which app is running snapzy"))
    }
    if allowedForConnection { return .allowed }

    switch store.decision(for: caller.key) {
    case .allow:
      store.touch(caller.key)
      return .allowed
    case .deny:
      return .denied(Self.deniedError(caller))
    case nil:
      break
    }

    guard promptsByCaller[caller.key] != nil || promptsByCaller.count < Self.maxPendingPrompts else {
      return .denied(CLIError(
        .notAuthorized,
        "Too many apps are waiting for approval in Snapzy",
        hint: "Answer the open Snapzy prompts, then retry"
      ))
    }

    switch await prompt(caller, command: Self.commandName(for: method)) {
    case .alwaysAllow:
      return .allowed
    case .allowOnce:
      return .allowedForConnection
    case .deny:
      return .denied(Self.deniedError(caller))
    case .timedOut:
      return .denied(CLIError(
        .notAuthorized,
        "Nobody approved \(caller.displayName) in Snapzy in time",
        hint: "Approve the request in Snapzy, or run `snapzy doctor`"
      ))
    }
  }

  func authorizationStatus(for caller: CLICallerIdentity?, allowedForConnection: Bool) -> CLIStatus.Authorization {
    if allowedForConnection { return .allowed }
    switch caller.flatMap({ store.decision(for: $0.key) }) {
    case .allow: return .allowed
    case .deny: return .denied
    case nil: return .undetermined
    }
  }

  private func prompt(_ caller: CLICallerIdentity, command: String) async -> CLIAuthorizationPromptResult {
    let key = caller.key
    let waiter = Waiter()
    waiters[key, default: []].append(waiter)
    defer {
      waiters[key]?.removeAll { $0 === waiter }
      if waiters[key]?.isEmpty == true { waiters[key] = nil }
    }

    let task: Task<CLIAuthorizationPromptResult, Never>
    if let pending = promptsByCaller[key] {
      task = pending
    } else {
      let previous = lastPrompt
      task = Task { @MainActor [weak self, prompter] in
        _ = await previous?.value
        defer { self?.promptsByCaller[key] = nil }
        guard let self, waiters[key]?.contains(where: { !$0.isCancelled }) == true else {
          return .timedOut
        }
        let result = prompter.ask(caller, command: command)
        // Recorded before the pending prompt is cleared, so a request arriving
        // in between finds the decision instead of opening a second prompt.
        switch result {
        case .alwaysAllow: store.record(caller, decision: .allow)
        case .deny: store.record(caller, decision: .deny)
        case .allowOnce, .timedOut: break
        }
        return result
      }
      promptsByCaller[key] = task
      lastPrompt = task
    }

    return await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      Task { @MainActor in waiter.isCancelled = true }
    }
  }

  /// `capture.window` → `capture window`, as the user typed it. Only known
  /// methods are named: the prompt never shows text a client chose.
  nonisolated static func commandName(for method: String) -> String {
    guard let known = CLIMethod(rawValue: method) else { return "?" }
    return known.rawValue.replacingOccurrences(of: ".", with: " ")
  }

  private static func deniedError(_ caller: CLICallerIdentity) -> CLIError {
    CLIError(
      .notAuthorized,
      "\(caller.displayName) is not allowed to use Snapzy from the command line",
      hint: "Remove it from Snapzy → Settings → Command Line → Allowed apps, then retry"
    )
  }
}

/// Bridges the connection queue to the main-actor coordinator.
nonisolated struct CLIAuthorizer: CLIAuthorizing {
  func authorize(_ context: CLIRequestContext, method: String) async -> CLIAuthorizationOutcome {
    await CLIAuthorizationCoordinator.shared.authorize(
      caller: context.caller,
      method: method,
      allowedForConnection: context.isAllowedForConnection
    )
  }
}
