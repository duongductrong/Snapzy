//
//  AgentCLITextRunner.swift
//  Snapzy
//
//  Runs one text-only prompt (translation) through an agent CLI on this Mac and
//  returns its reply. Unlike `AgentCLIProvider` there is no MCP server, no tool
//  and no image: the CLI only reads the prompt and writes text back. Login,
//  quota and the model provider stay the CLI's; Snapzy never reads credentials.
//

import Foundation

/// A readable failure from an agent CLI text run.
struct AgentCLITextError: LocalizedError, Equatable {
  let message: String
  /// The CLI is missing: Settings › AI can fix it.
  var needsSetup = false

  var errorDescription: String? { message }
}

/// The model and effort a CLI uses for translation.
nonisolated enum TranslationAgentCLISettings {
  /// The translation-only model, or nil when it follows Settings › AI.
  static func modelOverride(_ kind: AnnotateAgentCLIKind, defaults: UserDefaults = .standard) -> String? {
    trimmed(defaults.string(forKey: key(kind)))
  }

  static func setModelOverride(_ model: String?, for kind: AnnotateAgentCLIKind, defaults: UserDefaults = .standard) {
    if let model = trimmed(model) {
      defaults.set(model, forKey: key(kind))
    } else {
      defaults.removeObject(forKey: key(kind))
    }
  }

  /// The model set for this CLI in Settings › AI (nil = the CLI's own default).
  static func aiModel(_ kind: AnnotateAgentCLIKind, defaults: UserDefaults = .standard) -> String? {
    trimmed(defaults.string(forKey: kind.modelDefaultsKey))
  }

  /// Override first, then Settings › AI, then the CLI's default.
  static func model(_ kind: AnnotateAgentCLIKind, defaults: UserDefaults = .standard) -> String? {
    modelOverride(kind, defaults: defaults) ?? aiModel(kind, defaults: defaults)
  }

  /// Settings › AI effort, only while the AI model is used: an effort picked for
  /// one model may not exist on the override.
  static func effort(_ kind: AnnotateAgentCLIKind, defaults: UserDefaults = .standard) -> String? {
    guard modelOverride(kind, defaults: defaults) == nil else { return nil }
    return trimmed(defaults.string(forKey: kind.effortDefaultsKey))
  }

  static func key(_ kind: AnnotateAgentCLIKind) -> String {
    "translate.cli.\(kind.rawValue).model"
  }

  private static func trimmed(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    return value
  }
}

@MainActor
struct AgentCLITextRunner {
  let kind: AnnotateAgentCLIKind
  var model: String?
  var effort: String?
  var timeout: TimeInterval
  var defaults: UserDefaults = .standard

  /// Model, effort and timeout from Settings (translation override first).
  init(kind: AnnotateAgentCLIKind, defaults: UserDefaults = .standard) {
    self.kind = kind
    self.defaults = defaults
    model = TranslationAgentCLISettings.model(kind, defaults: defaults)
    effort = TranslationAgentCLISettings.effort(kind, defaults: defaults)
    timeout = AnnotateAgentAISettings.cliTimeout(defaults: defaults)
  }

  init(kind: AnnotateAgentCLIKind, model: String?, effort: String?, timeout: TimeInterval, defaults: UserDefaults = .standard) {
    self.kind = kind
    self.model = model
    self.effort = effort
    self.timeout = timeout
    self.defaults = defaults
  }

  func complete(_ prompt: String) async throws -> String {
    let kind = kind
    let defaults = defaults
    guard let executable = await Task.detached(priority: .userInitiated, operation: {
      AnnotateAgentCLIEnvironment.locate(kind, defaults: defaults)
    }).value else {
      throw AgentCLITextError(message: L10n.AnnotateAI.cliNotInstalled(kind.displayName), needsSetup: true)
    }
    try Task.checkCancellation()

    let directory = try Self.workingDirectory(for: kind)
    let runID = UUID().uuidString
    var runFiles: [URL] = []
    defer { runFiles.forEach { try? FileManager.default.removeItem(at: $0) } }

    let invocation = AnnotateAgentCLIAdapter.textInvocation(
      for: kind,
      prompt: prompt,
      model: model,
      effort: effort,
      directory: directory.path,
      runID: runID
    )
    for (name, contents) in invocation.files {
      let url = directory.appendingPathComponent(name)
      try AgentCLIProvider.writePrivate(Data(contents.utf8), to: url)
      runFiles.append(url)
    }
    var stdinPath: String?
    if let stdin = invocation.stdin {
      let url = directory.appendingPathComponent("prompt-\(runID).txt")
      try AgentCLIProvider.writePrivate(Data(stdin.utf8), to: url)
      runFiles.append(url)
      stdinPath = url.path
    }

    var environment = await Task.detached(priority: .userInitiated) {
      AnnotateAgentCLIEnvironment.environment(forExecutable: executable)
    }.value
    environment.merge(invocation.environment) { _, new in new }
    try Task.checkCancellation()

    let process: AnnotateAgentCLIProcess
    do {
      process = try AnnotateAgentCLIProcess(
        executable: executable,
        arguments: invocation.arguments,
        environment: environment,
        directory: directory.path,
        stdinPath: stdinPath
      )
    } catch AnnotateAgentCLIProcess.LaunchError.spawnFailed(let code) {
      if code == ENOENT || code == EACCES || code == ENOEXEC {
        throw AgentCLITextError(message: L10n.AnnotateAI.cliNotInstalled(kind.displayName), needsSetup: true)
      }
      throw AgentCLITextError(message: L10n.AnnotateAI.cliFailed(kind.displayName, String(cString: strerror(code))))
    }
    defer { process.terminate() }
    DiagnosticLogger.shared.log(.info, .ocr, "Agent CLI text run started", context: [
      "cli": kind.rawValue,
      "model": model ?? "default",
    ])

    let outcome: AgentCLIProvider.Outcome
    do {
      outcome = try await AgentCLIProvider.collect(process: process, kind: kind, timeout: timeout)
    } catch AgentProviderError.failed(let message) {
      throw AgentCLITextError(message: message)
    }
    if let failure = outcome.failure {
      throw AgentCLITextError(message: L10n.AnnotateAI.cliFailed(kind.displayName, AgentCLIProvider.shorten(failure)))
    }
    let reply = outcome.reply?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if reply.isEmpty {
      let detail = AgentCLIProvider.shorten(outcome.exit.stderrTail)
      throw AgentCLITextError(message: L10n.AnnotateAI.cliFailed(
        kind.displayName,
        detail.isEmpty ? "exit \(outcome.exit.status)" : detail
      ))
    }
    return reply
  }

  /// Private (0700) and separate from the Annotate agent's, so translations never
  /// show up among the conversations that agent resumes.
  static func workingDirectory(for kind: AnnotateAgentCLIKind) throws -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let url = base.appendingPathComponent("Snapzy/AgentWork/text-\(kind.rawValue)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    return url
  }
}
