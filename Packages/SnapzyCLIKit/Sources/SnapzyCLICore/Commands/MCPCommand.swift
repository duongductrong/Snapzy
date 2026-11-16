//
//  MCPCommand.swift
//  SnapzyCLICore
//
//  `snapzy mcp` — the stdio MCP server Snapzy hands to an agent CLI it spawns
//  for Annotate's AI prompt. Not meant to be configured by hand: the session
//  token exists only while that prompt runs.
//

import ArgumentParser
import Foundation
import SnapzyCLIClient
import SnapzyCLIProtocol

struct MCPCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "mcp",
    abstract: "Serve Annotate's AI tools over MCP (stdio) for an agent Snapzy started.",
    discussion: """
    Snapzy starts this itself when an Annotate AI prompt runs through Claude Code,
    Codex or OpenCode. The session token comes from \(AgentSessionEnvironment.tokenKey)
    (or --session) and stops working when that prompt finishes.
    """,
    shouldDisplay: false
  )

  @Option(help: "Session token; defaults to $\(AgentSessionEnvironment.tokenKey).")
  var session: String?

  @Option(help: "Seconds to wait for each tool call.")
  var timeout: Double = 90

  func validate() throws {
    guard timeout > 0 else { throw ValidationError("--timeout must be greater than 0.") }
  }

  func run() async throws {
    let token = session ?? ProcessInfo.processInfo.environment[AgentSessionEnvironment.tokenKey]
    guard let token, !token.isEmpty else {
      StandardStreams.writeError("snapzy mcp: no session token. Snapzy starts this command itself for Annotate's AI prompt.\n")
      throw ExitCode(CLIErrorCode.invalidArguments.exitCode)
    }

    let handler = MCPMessageHandler(
      backend: SocketToolBackend(
        session: token,
        // Never launch Snapzy: the agent was started by a running Snapzy.
        options: CLISession.Options(
          requestTimeout: timeout,
          launchTimeout: 1,
          allowsLaunch: false,
          cliVersion: CLIVersion.current
        )
      ),
      serverVersion: CLIVersion.current
    )

    // One message per line; stdout carries protocol messages only.
    while let line = readLine(strippingNewline: true) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }
      guard let response = await handler.handle(Data(trimmed.utf8)) else { continue }
      StandardStreams.write(String(decoding: response, as: UTF8.self) + "\n")
    }
  }
}
