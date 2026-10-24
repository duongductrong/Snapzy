//
//  StatusCommand.swift
//  SnapzyCLICore
//

import ArgumentParser
import SnapzyCLIProtocol

struct StatusCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: "Show whether Snapzy can capture for this app."
  )

  @OptionGroup var global: GlobalOptions

  func run() async throws {
    try await CommandRunner.run(global) { client, renderer in
      let status = try client.call(.systemStatus, as: CLIStatus.self)
      try StandardStreams.write(renderer.render(status))
    }
  }
}
