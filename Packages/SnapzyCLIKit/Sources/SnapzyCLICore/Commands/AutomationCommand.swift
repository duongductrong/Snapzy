//
//  AutomationCommand.swift
//  SnapzyCLICore
//
//  `automation list|run`. Runs an automation exactly as its shortcut would
//  (capture, then its steps) and waits for the result, or runs its steps on
//  files passed with `--file`. Only automations with "Allow URL scheme, command
//  line and Shortcuts" turned on can be run.
//

import ArgumentParser
import Foundation
import SnapzyCLIClient
import SnapzyCLIProtocol

struct AutomationCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "automation",
    abstract: "List and run Snapzy automations.",
    subcommands: [List.self, Run.self]
  )

  /// An area selection waits for the user, so `run` waits longer than other requests.
  static let defaultRunTimeout: TimeInterval = 300

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "list",
      abstract: "List automations; the ones `automation run` can start come first."
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
      try await CommandRunner.run(global) { client, renderer in
        let list = try AutomationCommand.call(
          client,
          .automationList,
          params: CLIEmpty(),
          as: CLIAutomationList.self,
          timeout: client.requestTimeout
        )
        try StandardStreams.write(renderer.render(list))
      }
    }
  }

  struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "run",
      abstract: "Run an automation and wait for it to finish.",
      discussion: """
      Without --file the automation's capture starts (an area automation waits for \
      your selection) and its steps run on the result. With --file the capture is \
      skipped and the steps run on those files; the files are never modified.

      The automation must have "Allow URL scheme, command line and Shortcuts" turned \
      on in Settings → Automations. --timeout defaults to 300 seconds here.

      Exits 0 when the steps ran, 1 when a step failed (for example the upload), and \
      6 when the capture was cancelled.
      """
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Automation id, or its name (case-insensitive).")
    var automation: String

    @Option(name: .customLong("file"), help: "Run on this image or video instead of capturing. Repeatable.")
    var files: [String] = []

    mutating func validate() throws {
      guard !automation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ValidationError("Pass an automation id or name.")
      }
      if files.contains(where: { $0.isEmpty }) {
        throw ValidationError("--file needs a path.")
      }
    }

    var requestTimeout: TimeInterval {
      global.timeoutOverride ?? AutomationCommand.defaultRunTimeout
    }

    func run() async throws {
      let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
      var paths: [String] = []
      // Before connecting, so a typo never launches Snapzy or shows the approval prompt.
      try await CommandRunner.reportingErrors(global.renderer) {
        paths = try AutomationCommand.resolveFiles(files, currentDirectory: currentDirectory)
      }
      let params = CLIAutomationRunParams(ref: automation, files: paths.isEmpty ? nil : paths)

      try await CommandRunner.run(global) { client, renderer in
        let result = try AutomationCommand.call(
          client,
          .automationRun,
          params: params,
          as: CLIAutomationRunResult.self,
          timeout: requestTimeout
        )
        try StandardStreams.write(renderer.render(result))
        let code = AutomationCommand.exitCode(for: result)
        if code != 0 {
          throw ExitCode(code)
        }
      }
    }
  }

  // MARK: - Helpers

  /// Calls an `automation.*` method, turning an older Snapzy's answer into an update hint.
  static func call<Result: Codable & Sendable>(
    _ client: CLIClient,
    _ method: CLIMethod,
    params: some Codable & Sendable,
    as resultType: Result.Type,
    timeout: TimeInterval
  ) throws -> Result {
    if client.hello.protocolVersion < .automations {
      throw updateRequired(appVersion: client.hello.appVersion)
    }
    do {
      return try client.call(method, params: params, as: resultType, timeout: timeout)
    } catch let error as CLIError {
      throw translate(error, appVersion: client.hello.appVersion)
    }
  }

  static func translate(_ error: CLIError, appVersion: String) -> CLIError {
    error.code == .unknownMethod ? updateRequired(appVersion: appVersion) : error
  }

  static func updateRequired(appVersion: String) -> CLIError {
    let running = appVersion.isEmpty ? "The running Snapzy" : "Snapzy \(appVersion)"
    return CLIError(
      .unknownMethod,
      "Update Snapzy to use automations",
      hint: "\(running) does not support `snapzy automation`; use Check for Updates in Snapzy"
    )
  }

  /// Absolute, standardized paths of existing regular files.
  static func resolveFiles(
    _ paths: [String],
    currentDirectory: URL,
    fileManager: FileManager = .default
  ) throws -> [String] {
    try paths.map { raw in
      let expanded = (raw as NSString).expandingTildeInPath
      let url = expanded.hasPrefix("/")
        ? URL(fileURLWithPath: expanded)
        : currentDirectory.appendingPathComponent(expanded)
      let path = url.standardizedFileURL.path

      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
        throw CLIError(.targetNotFound, "No file at \(path)")
      }
      guard !isDirectory.boolValue else {
        throw CLIError(.invalidArguments, "\(path) is a directory", hint: "Pass image or video files to --file")
      }
      return path
    }
  }

  /// 0 when the steps ran, 1 when one failed, 6 when the capture was cancelled.
  static func exitCode(for result: CLIAutomationRunResult) -> Int32 {
    switch result.state {
    case .cancelled: cancelledExitCode
    case .finished: result.isError ? CLIErrorCode.internal.exitCode : 0
    }
  }

  /// Reserved in CLIError's table for "user cancelled an interactive flow".
  static let cancelledExitCode: Int32 = 6
}
