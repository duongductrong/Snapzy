//
//  AgentCLIProvider.swift
//  Snapzy
//
//  Runs a Snapzy AI prompt (any surface) through an agent CLI on this Mac (Claude Code, Codex,
//  OpenCode). Snapzy starts the CLI headless in an empty private directory and
//  gives it exactly one MCP server, `snapzy mcp`, bound to this run by a token.
//  Login, model and quota belong to the CLI; Snapzy never reads its credentials.
//

import AppKit
import Foundation
import SnapzyCLIProtocol

@MainActor
final class AgentCLIProvider: AgentProvider {

  let kind: AnnotateAgentCLIKind
  private let defaults: UserDefaults

  var displayName: String { kind.displayName }
  let symbolName = "terminal"
  var logoImageName: String? { kind.logoImageName }

  /// The CLI sends the scene (and picture) to its own model provider.
  var remoteDestination: AgentRemoteDestination? {
    AgentRemoteDestination(id: "cli:\(kind.rawValue)", name: kind.displayName, host: kind.displayName, kind: .agentCLI)
  }

  init(kind: AnnotateAgentCLIKind, defaults: UserDefaults = .standard) {
    self.kind = kind
    self.defaults = defaults
  }

  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  private var timeout: TimeInterval {
    AnnotateAgentAISettings.cliTimeout(defaults: defaults)
  }

  private var model: String? {
    let value = defaults.string(forKey: kind.modelDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return value?.isEmpty == false ? value : nil
  }

  private var effort: String? {
    let value = defaults.string(forKey: kind.effortDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return value?.isEmpty == false ? value : nil
  }

  private var sendsImage: Bool {
    AnnotateAgentAISettings.sendsImage(defaults: defaults)
  }

  static var helperPath: String {
    Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/snapzy").path
  }

  // MARK: - Run

  func run(_ request: AgentRequest, session: AgentSession) async throws -> String {
    session.report(L10n.AnnotateAI.statusStarting(kind.displayName))

    let kind = kind
    let defaults = defaults
    guard let executable = await Task.detached(priority: .userInitiated, operation: {
      AnnotateAgentCLIEnvironment.locate(kind, defaults: defaults)
    }).value else {
      throw AgentProviderError.needsSetup(L10n.AnnotateAI.cliNotInstalled(kind.displayName))
    }
    try Task.checkCancellation()

    let helper = Self.helperPath
    guard FileManager.default.isExecutableFile(atPath: helper) else {
      throw AgentProviderError.failed(L10n.AnnotateAI.cliHelperMissing)
    }

    guard CLIServer.shared.beginAgentSession() else {
      CLIServer.shared.endAgentSession()
      throw AgentProviderError.failed(L10n.AnnotateAI.cliConnectionFailed(kind.displayName))
    }
    defer { CLIServer.shared.endAgentSession() }

    let surface = session.surface
    let sceneSize = request.scene?.imageUnitSize
    let image = sendsImage ? request.image : nil
    let bridge = AgentBridge.shared
    let token = bridge.open(session: session, image: image, sceneSize: sceneSize, allowsToolImages: sendsImage)
    defer { bridge.close(token) }

    let directory = try Self.workingDirectory(for: kind)
    let runID = UUID().uuidString
    var runFiles: [URL] = []
    defer { runFiles.forEach { try? FileManager.default.removeItem(at: $0) } }

    // Claude Code looks through get_snapshot; the others take the file with the prompt.
    var imagePath: String?
    if kind != .claudeCode, let image,
       let snapshot = await AgentBridge.snapshot(of: image, sceneSize: sceneSize),
       let data = Data(base64Encoded: snapshot.base64) {
      let url = directory.appendingPathComponent("screenshot-\(runID).jpg")
      do {
        try Self.writePrivate(data, to: url)
        runFiles.append(url)
        imagePath = url.path
      } catch {
        DiagnosticLogger.shared.log(.warning, surface.logCategory, "AI agent CLI: could not write the screenshot", context: ["error": "\(error)"])
      }
    }
    try Task.checkCancellation()

    var environment = await Task.detached(priority: .userInitiated) {
      AnnotateAgentCLIEnvironment.environment(forExecutable: executable)
    }.value
    try Task.checkCancellation()

    let mcp = AnnotateAgentMCPLaunch(
      helperPath: helper,
      token: token,
      socketOverride: ProcessInfo.processInfo.environment["SNAPZY_SOCKET"]
    )
    var resumeID = request.resumeSessionID
    while true {
      var turn = request
      turn.resumeSessionID = resumeID
      let input = AnnotateAgentCLIRunInput(
        prompt: Self.prompt(for: turn, surface: surface, hasImage: image != nil, attachesImage: imagePath != nil),
        systemPrompt: Self.instructions(for: surface),
        resumeSessionID: resumeID,
        model: model,
        effort: effort,
        mcp: mcp,
        directory: directory.path,
        runID: runID,
        imagePath: imagePath
      )
      let invocation = AnnotateAgentCLIAdapter.invocation(for: kind, input)
      for (name, contents) in invocation.files {
        let url = directory.appendingPathComponent(name)
        try Self.writePrivate(Data(contents.utf8), to: url)
        runFiles.append(url)
      }
      var stdinPath: String?
      if let stdin = invocation.stdin {
        let url = directory.appendingPathComponent("prompt-\(runID).txt")
        try Self.writePrivate(Data(stdin.utf8), to: url)
        runFiles.append(url)
        stdinPath = url.path
      }
      environment.merge(invocation.environment) { _, new in new }

      do {
        return try await runOnce(
          executable: executable,
          invocation: invocation,
          environment: environment,
          directory: directory.path,
          stdinPath: stdinPath,
          resumed: resumeID != nil,
          session: session
        )
      } catch AgentProviderError.failed(let message) where resumeID != nil && session.changeCount == 0 {
        // The CLI lost the conversation (pruned, other machine, new version): start over
        // with a summary of the earlier turns instead of failing the prompt.
        DiagnosticLogger.shared.log(.info, surface.logCategory, "AI agent CLI could not resume; starting fresh", context: ["error": message])
        resumeID = nil
        session.providerSessionID = nil
      }
    }
  }

  private func runOnce(
    executable: String,
    invocation: AnnotateAgentCLIInvocation,
    environment: [String: String],
    directory: String,
    stdinPath: String?,
    resumed: Bool,
    session: AgentSession
  ) async throws -> String {
    let process: AnnotateAgentCLIProcess
    do {
      process = try AnnotateAgentCLIProcess(
        executable: executable,
        arguments: invocation.arguments,
        environment: environment,
        directory: directory,
        stdinPath: stdinPath
      )
    } catch AnnotateAgentCLIProcess.LaunchError.spawnFailed(let code) {
      if code == ENOENT || code == EACCES || code == ENOEXEC {
        throw AgentProviderError.needsSetup(L10n.AnnotateAI.cliNotInstalled(kind.displayName))
      }
      throw AgentProviderError.failed(L10n.AnnotateAI.cliFailed(kind.displayName, String(cString: strerror(code))))
    }
    defer { process.terminate() }
    DiagnosticLogger.shared.log(.info, session.surface.logCategory, "AI agent CLI started", context: [
      "cli": kind.rawValue,
      "resume": resumed ? "yes" : "no",
    ])
    session.report(L10n.AnnotateAI.statusThinking)

    let outcome = try await Self.collect(process: process, kind: kind, timeout: timeout)
    if let sessionID = outcome.sessionID {
      session.providerSessionID = sessionID
    }
    if let failure = outcome.failure {
      throw AgentProviderError.failed(L10n.AnnotateAI.cliFailed(kind.displayName, Self.shorten(failure)))
    }
    if outcome.exit.status != 0, outcome.reply == nil {
      let detail = Self.shorten(outcome.exit.stderrTail)
      throw AgentProviderError.failed(L10n.AnnotateAI.cliFailed(
        kind.displayName,
        detail.isEmpty ? "exit \(outcome.exit.status)" : detail
      ))
    }
    return AgentReplyFormatter.oneLine(outcome.reply ?? "")
  }

  // MARK: - Process output

  nonisolated struct Outcome {
    var sessionID: String?
    var reply: String?
    /// Last error not followed by a message: CLIs report retries ("Reconnecting… 2/5")
    /// as errors and then carry on.
    var failure: String?
    var exit = AnnotateAgentCLIProcess.Exit(status: 0, stderrTail: "")

    mutating func apply(_ event: AnnotateAgentCLIEvent) {
      switch event {
      case .session(let id): sessionID = id
      case .message(let text):
        reply = text
        failure = nil
      case .failure(let message): failure = message
      }
    }
  }

  nonisolated private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
  }

  /// Seconds to keep reading after the CLI exits, before ending children that still
  /// hold its stdout (an MCP server, a worker) so the read can finish.
  nonisolated static let drainAfterExit: TimeInterval = 1

  nonisolated private static func collect(
    process: AnnotateAgentCLIProcess,
    kind: AnnotateAgentCLIKind,
    timeout: TimeInterval
  ) async throws -> Outcome {
    let exited = Flag()
    let exitTask = Task.detached(priority: .userInitiated) { () -> AnnotateAgentCLIProcess.Exit in
      let exit = await process.waitForExit()
      exited.set()
      try? await Task.sleep(nanoseconds: UInt64(drainAfterExit * 1_000_000_000))
      process.terminate()
      return exit
    }
    let reader = Task.detached(priority: .userInitiated) { () -> Outcome in
      var outcome = Outcome()
      for await line in process.lines {
        for event in AnnotateAgentCLIAdapter.events(in: line, kind: kind) {
          outcome.apply(event)
        }
      }
      return outcome
    }
    let timedOut = Flag()
    let watchdog = Task.detached {
      try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
      guard !exited.isSet else { return }
      timedOut.set()
      process.terminate()
    }
    defer { watchdog.cancel() }

    var outcome = await withTaskCancellationHandler {
      await reader.value
    } onCancel: {
      process.terminate()
    }
    outcome.exit = await exitTask.value
    try Task.checkCancellation()
    if timedOut.isSet {
      throw AgentProviderError.failed(L10n.AnnotateAI.cliTimedOut(kind.displayName))
    }
    return outcome
  }

  // MARK: - Prompt

  static func instructions(for surface: AgentSurface) -> String {
    surface.instructions + """

    You are running inside Snapzy with one MCP server, "snapzy". \(surface.cliModeNote) \
    When done, answer with one short sentence in the user's language saying what you changed.
    """
  }

  static func prompt(for request: AgentRequest, surface: AgentSurface, hasImage: Bool, attachesImage: Bool) -> String {
    var parts: [String] = []
    // A CLI that cannot resume never saw earlier turns: summarize them.
    if request.resumeSessionID == nil, !request.history.isEmpty {
      let history = request.history.suffix(6)
        .map { "- User: \($0.prompt)\n  You: \($0.reply)" }
        .joined(separator: "\n")
      parts.append("Earlier in this conversation:\n\(history)")
    }
    if attachesImage {
      parts.append(surface.imageAttachedNote)
    } else if hasImage {
      parts.append(surface.imageOnRequestNote)
    }
    parts.append("Scene (JSON):\n\(request.sceneJSON)")
    parts.append("Request: \(request.prompt)")
    return parts.joined(separator: "\n\n")
  }

  // MARK: - Helpers

  /// The CLI's working directory: private (0700), empty of user files, and stable per
  /// CLI so conversations saved by working directory can be resumed.
  static func workingDirectory(for kind: AnnotateAgentCLIKind) throws -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let url = base.appendingPathComponent("Snapzy/AgentWork/\(kind.rawValue)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    return url
  }

  /// Written readable by the user only (configs carry the session token).
  static func writePrivate(_ data: Data, to url: URL) throws {
    FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
    try data.write(to: url)
  }

  /// One readable line of an error: last non-empty line, no ANSI codes, capped.
  static func shorten(_ text: String) -> String {
    let stripped = text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
    let line = stripped
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .last { !$0.isEmpty } ?? ""
    return line.count > 140 ? String(line.prefix(139)) + "…" : line
  }
}
