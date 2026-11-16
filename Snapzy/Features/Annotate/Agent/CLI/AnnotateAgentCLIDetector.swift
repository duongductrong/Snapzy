//
//  AnnotateAgentCLIDetector.swift
//  Snapzy
//
//  Which agent CLIs (Claude Code, Codex, OpenCode) are on this Mac, and the
//  environment to run them in. A GUI app gets a bare PATH, while these tools
//  live in ~/.local/bin, Homebrew, nvm… and often need `node` from the user's
//  PATH; so the PATH comes from the user's login shell, read once and cached.
//

import Combine
import Foundation

nonisolated enum AnnotateAgentCLIKind: String, CaseIterable, Identifiable, Sendable {
  case claudeCode = "claude"
  case codex
  case openCode = "opencode"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .claudeCode: "Claude Code"
    case .codex: "Codex"
    case .openCode: "OpenCode"
    }
  }

  var executableName: String { rawValue }

  /// UserDefaults key for a path the user picked by hand (Phase 6 Settings).
  var pathDefaultsKey: String { "annotateAgent.cli.\(rawValue).path" }
  /// UserDefaults key for the model override ("provider/model" for OpenCode). Empty = the CLI's default.
  var modelDefaultsKey: String { "annotateAgent.cli.\(rawValue).model" }
}

nonisolated enum AnnotateAgentCLIEnvironment {
  /// Install locations the login shell's PATH may miss (non-interactive shells skip .zshrc).
  static func commonDirectories(home: String = NSHomeDirectory()) -> [String] {
    [
      "\(home)/.local/bin",
      "\(home)/.opencode/bin",
      "\(home)/.claude/local",
      "\(home)/.bun/bin",
      "\(home)/.npm-global/bin",
      "\(home)/.volta/bin",
      "\(home)/Library/pnpm",
      "/opt/homebrew/bin",
      "/usr/local/bin",
    ]
  }

  private static let lock = NSLock()
  nonisolated(unsafe) private static var cachedLoginPath: String?

  /// PATH of the user's login shell (blocking, up to ~5 s the first time; call off the main thread).
  static func loginPath() -> String {
    lock.lock()
    if let cachedLoginPath {
      lock.unlock()
      return cachedLoginPath
    }
    lock.unlock()

    let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
    let marker = "__SNAPZY_PATH__"
    // -i too: many users set PATH (nvm, bun) in .zshrc only. Output is fenced by markers
    // because interactive startup files may print banners.
    let output = run(shell, ["-l", "-i", "-c", "printf '\(marker)%s\(marker)' \"$PATH\""], timeout: 5) ?? ""
    var path = ""
    if let start = output.range(of: marker), let end = output.range(of: marker, range: start.upperBound ..< output.endIndex) {
      path = String(output[start.upperBound ..< end.lowerBound])
    }
    if path.isEmpty {
      path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    }
    lock.lock()
    cachedLoginPath = path
    lock.unlock()
    return path
  }

  /// Forget the cached PATH (Settings › Refresh).
  static func resetCache() {
    lock.lock()
    cachedLoginPath = nil
    lock.unlock()
  }

  static func searchDirectories(loginPath: String, home: String = NSHomeDirectory()) -> [String] {
    var seen = Set<String>()
    return (loginPath.split(separator: ":").map(String.init) + commonDirectories(home: home))
      .filter { !$0.isEmpty && seen.insert($0).inserted }
  }

  /// First executable named `kind.executableName`, or the user's own path when set and runnable.
  static func locate(
    _ kind: AnnotateAgentCLIKind,
    defaults: UserDefaults = .standard,
    loginPath: String? = nil,
    fileManager: FileManager = .default
  ) -> String? {
    if let custom = defaults.string(forKey: kind.pathDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
       !custom.isEmpty {
      let expanded = (custom as NSString).expandingTildeInPath
      return fileManager.isExecutableFile(atPath: expanded) ? expanded : nil
    }
    for directory in searchDirectories(loginPath: loginPath ?? Self.loginPath()) {
      let candidate = (directory as NSString).appendingPathComponent(kind.executableName)
      var isDirectory: ObjCBool = false
      if fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory), !isDirectory.boolValue,
         fileManager.isExecutableFile(atPath: candidate) {
        return candidate
      }
    }
    return nil
  }

  /// The app's environment with the login PATH (and the CLI's own directory first).
  static func environment(forExecutable executable: String, loginPath: String? = nil) -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    let directory = (executable as NSString).deletingLastPathComponent
    environment["PATH"] = ([directory] + searchDirectories(loginPath: loginPath ?? Self.loginPath()))
      .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
      .joined(separator: ":")
    // Never inherit a socket or session meant for someone else.
    environment.removeValue(forKey: "SNAPZY_AGENT_SESSION")
    // Plain output: no colors or TTY tricks in JSON streams.
    environment["NO_COLOR"] = "1"
    environment["TERM"] = "dumb"
    return environment
  }

  /// Runs a short command and returns stdout, or nil on failure/timeout.
  static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return nil
    }
    let deadline = DispatchTime.now() + timeout
    let group = DispatchGroup()
    group.enter()
    var data = Data()
    DispatchQueue.global().async {
      data = output.fileHandleForReading.readDataToEndOfFile()
      group.leave()
    }
    if group.wait(timeout: deadline) == .timedOut {
      // Interactive shells may ignore SIGTERM.
      process.terminate()
      let pid = process.processIdentifier
      DispatchQueue.global().asyncAfter(deadline: .now() + 1) { kill(pid, SIGKILL) }
      return nil
    }
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
  }
}

/// The agent CLIs found on this Mac, refreshed in the background. Drives the
/// provider menu in the prompt.
@MainActor
final class AnnotateAgentCLIDetector: ObservableObject {
  static let shared = AnnotateAgentCLIDetector()

  @Published private(set) var installed: [AnnotateAgentCLIKind: String] = [:]
  @Published private(set) var hasScanned = false
  private var scanTask: Task<Void, Never>?
  private var lastScan: Date?

  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  /// Rescans at most once a minute unless forced.
  func refresh(force: Bool = false) {
    guard scanTask == nil else { return }
    if !force, let lastScan, Date().timeIntervalSince(lastScan) < 60 { return }
    if force { AnnotateAgentCLIEnvironment.resetCache() }
    scanTask = Task { [weak self] in
      let found = await Task.detached(priority: .utility) { () -> [AnnotateAgentCLIKind: String] in
        let path = AnnotateAgentCLIEnvironment.loginPath()
        var found: [AnnotateAgentCLIKind: String] = [:]
        for kind in AnnotateAgentCLIKind.allCases {
          found[kind] = AnnotateAgentCLIEnvironment.locate(kind, loginPath: path)
        }
        return found
      }.value
      guard let self else { return }
      self.installed = found
      self.hasScanned = true
      self.lastScan = Date()
      self.scanTask = nil
    }
  }
}
