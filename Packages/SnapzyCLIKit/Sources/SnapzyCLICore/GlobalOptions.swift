//
//  GlobalOptions.swift
//  SnapzyCLICore
//
//  Options every command accepts, plus the shared run loop: open a session,
//  run the command body, and turn any failure into a rendered error and a
//  documented exit code.
//

import ArgumentParser
import Foundation
import SnapzyCLIClient
import SnapzyCLIProtocol

struct GlobalOptions: ParsableArguments {
  @Flag(help: "Print JSON even when stdout is a terminal.")
  var json = false

  @Option(help: "Seconds to wait for each Snapzy request.")
  var timeout: Double = 30

  @Option(name: .customLong("launch-timeout"), help: "Seconds to wait for Snapzy to start.")
  var launchTimeout: Double = 15

  @Flag(name: .customLong("no-launch"), help: "Fail instead of starting Snapzy when it is not running.")
  var noLaunch = false

  mutating func validate() throws {
    guard timeout > 0 else { throw ValidationError("--timeout must be greater than 0.") }
    guard launchTimeout > 0 else { throw ValidationError("--launch-timeout must be greater than 0.") }
  }

  var sessionOptions: CLISession.Options {
    CLISession.Options(
      requestTimeout: timeout,
      launchTimeout: launchTimeout,
      allowsLaunch: !noLaunch,
      cliVersion: CLIVersion.current
    )
  }

  var renderer: OutputRenderer {
    OutputRenderer(mode: OutputRenderer.mode(jsonFlag: json, stdoutIsTerminal: StandardStreams.stdoutIsTerminal))
  }
}

enum CommandRunner {
  /// Opens a session, runs `body`, and converts failures into exit codes.
  static func run(
    _ options: GlobalOptions,
    _ body: (CLIClient, OutputRenderer) throws -> Void
  ) async throws {
    let renderer = options.renderer
    try await reportingErrors(renderer) {
      let client = try await CLISession.open(options.sessionOptions)
      defer { client.close() }
      try body(client, renderer)
    }
  }

  static func reportingErrors(_ renderer: OutputRenderer, _ body: () async throws -> Void) async throws {
    do {
      try await body()
    } catch let error as CLIError {
      StandardStreams.writeError(renderer.render(error: error))
      throw ExitCode(error.code.exitCode)
    } catch let exitCode as ExitCode {
      throw exitCode
    } catch {
      let wrapped = CLIError(.internal, String(describing: error))
      StandardStreams.writeError(renderer.render(error: wrapped))
      throw ExitCode(wrapped.code.exitCode)
    }
  }
}

enum StandardStreams {
  static var stdoutIsTerminal: Bool {
    isatty(STDOUT_FILENO) == 1
  }

  /// `write(contentsOf:)` throws on a closed pipe instead of raising an
  /// Objective-C exception; SIGPIPE is ignored in `SnapzyCommand.execute`.
  static func write(_ string: String) {
    try? FileHandle.standardOutput.write(contentsOf: Data(string.utf8))
  }

  static func writeError(_ string: String) {
    try? FileHandle.standardError.write(contentsOf: Data(string.utf8))
  }
}
