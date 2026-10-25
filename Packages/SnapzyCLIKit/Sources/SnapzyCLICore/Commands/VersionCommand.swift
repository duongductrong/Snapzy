//
//  VersionCommand.swift
//  SnapzyCLICore
//
//  Prints the CLI version even when Snapzy is unreachable, then exits with
//  the connection error's code.
//

import ArgumentParser
import SnapzyCLIClient
import SnapzyCLIProtocol

struct VersionInfo: Codable, Equatable, HumanReadable {
  let cliVersion: String
  let protocolVersion: ProtocolVersion
  let appVersion: String?
  let appBuild: String?

  var humanDescription: String {
    guard let appVersion else { return "snapzy \(cliVersion)" }
    return "snapzy \(cliVersion) (Snapzy \(appVersion)\(appBuild.map { " build \($0)" } ?? ""))"
  }
}

struct VersionCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "version",
    abstract: "Show the CLI and Snapzy versions."
  )

  @OptionGroup var global: GlobalOptions

  func run() async throws {
    let renderer = global.renderer
    var hello: HelloResponse?
    var connectionError: CLIError?

    // Never start Snapzy just to print a version.
    var sessionOptions = global.sessionOptions
    sessionOptions.allowsLaunch = false

    do {
      let client = try await CLISession.open(sessionOptions)
      hello = client.hello
      client.close()
    } catch let error as CLIError {
      connectionError = error
    }

    let info = VersionInfo(
      cliVersion: CLIVersion.current,
      protocolVersion: .current,
      appVersion: hello?.appVersion,
      appBuild: hello?.appBuild
    )
    try StandardStreams.write(renderer.render(info))

    if let connectionError {
      try await CommandRunner.reportingErrors(renderer) { throw connectionError }
    }
  }
}
