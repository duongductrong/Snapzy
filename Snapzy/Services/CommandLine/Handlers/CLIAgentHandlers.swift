//
//  CLIAgentHandlers.swift
//  Snapzy
//
//  `agent.tools` / `agent.call` for `snapzy mcp`. Authorized by the run's session
//  token (AgentBridge), not by the per-app approval: Snapzy spawned the
//  agent itself, and the token only reaches the window (Annotate, Video Editor)
//  whose run started it.
//

import Foundation
import SnapzyCLIProtocol

nonisolated struct CLIAgentToolsHandler: CLIRequestHandling {
  func handle(_ params: AgentToolsParams, context _: CLIRequestContext) async throws -> AgentToolList {
    try await MainActor.run {
      try AgentToolList(tools: AgentBridge.shared.tools(token: params.session))
    }
  }
}

nonisolated struct CLIAgentCallHandler: CLIRequestHandling {
  func handle(_ params: AgentCallParams, context _: CLIRequestContext) async throws -> AgentCallResult {
    try await AgentBridge.shared.call(token: params.session, name: params.name, arguments: params.arguments)
  }
}
