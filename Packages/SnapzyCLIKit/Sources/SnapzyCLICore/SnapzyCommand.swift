//
//  SnapzyCommand.swift
//  SnapzyCLICore
//
//  Root `snapzy` command. Executables call `execute()` instead of `main()`:
//  it maps ArgumentParser's usage-error exit code (64) onto the documented
//  `2`, and its distinct name avoids resolving to the synchronous
//  `ParsableCommand.main()` from top-level code.
//

import ArgumentParser
import Foundation
import SnapzyCLIProtocol

public struct SnapzyCommand: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "snapzy",
    abstract: "Capture the screen with Snapzy from the command line.",
    discussion: """
    Output is JSON when stdout is not a terminal, or with --json.

    Exit codes:
      0  success
      1  internal error
      2  invalid arguments
      3  Screen Recording permission or Snapzy onboarding missing
      4  display, window or area not found
      5  Snapzy unavailable, busy, disabled, or version mismatch
      7  this app is not allowed to use Snapzy
    """,
    subcommands: [
      StatusCommand.self,
      DoctorCommand.self,
      VersionCommand.self,
      ListCommand.self,
      CaptureCommand.self,
    ]
  )

  public init() {}

  public static func execute(_ arguments: [String]? = nil) async {
    // A reader closing the pipe early (`| head`) should end the write with an
    // error, not kill the process before staged files are cleaned up.
    signal(SIGPIPE, SIG_IGN)
    do {
      var command = try parseAsRoot(arguments)
      if var asyncCommand = command as? AsyncParsableCommand {
        try await asyncCommand.run()
      } else {
        try command.run()
      }
    } catch {
      if exitCode(for: error) == .validationFailure {
        reportUsageError(error, arguments: arguments ?? Array(CommandLine.arguments.dropFirst()))
        Foundation.exit(CLIErrorCode.invalidArguments.exitCode)
      }
      exit(withError: error)
    }
  }

  /// Usage errors follow the same output mode as every other error, so an
  /// agent reading JSON from stderr never gets ArgumentParser's text instead.
  private static func reportUsageError(_ error: Error, arguments: [String]) {
    let mode = OutputRenderer.mode(
      jsonFlag: arguments.contains("--json"),
      stdoutIsTerminal: StandardStreams.stdoutIsTerminal
    )
    guard mode != .human else {
      StandardStreams.writeError(fullMessage(for: error) + "\n")
      return
    }
    let subcommandPath = arguments.prefix { !$0.hasPrefix("-") }
    let helpCommand = (["snapzy", "help"] + subcommandPath).joined(separator: " ")
    let usageError = CLIError(.invalidArguments, message(for: error), hint: "Run `\(helpCommand)`")
    StandardStreams.writeError(OutputRenderer(mode: mode).render(error: usageError))
  }
}

public enum CLIVersion {
  /// From the Info.plist embedded in the shipped binary; "dev" under `swift run`.
  public static var current: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
  }
}
