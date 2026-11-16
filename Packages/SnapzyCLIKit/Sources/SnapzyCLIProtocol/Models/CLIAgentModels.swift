//
//  CLIAgentModels.swift
//  SnapzyCLIProtocol
//
//  Wire models for `snapzy mcp`: the bridge an agent CLI (Claude Code, Codex,
//  OpenCode) uses to call Annotate's AI tools. Snapzy spawns the agent itself and
//  hands `snapzy mcp` a one-run session token; the token, not the per-app
//  approval, authorizes these methods, and it dies when the run ends.
//
//  | Method       | Params           | Result            |
//  | ------------ | ---------------- | ----------------- |
//  | agent.tools  | AgentToolsParams | AgentToolList     |
//  | agent.call   | AgentCallParams  | AgentCallResult   |
//

import Foundation

public enum AgentSessionEnvironment {
  /// Environment variable carrying the session token to `snapzy mcp`, so the helper's
  /// own argv never shows it. (Codex receives it in a `-c` override, visible to the same
  /// user in `ps`; the socket only accepts that user and the token dies with the run.)
  public static let tokenKey = "SNAPZY_AGENT_SESSION"
}

public struct AgentToolsParams: Codable, Sendable, Equatable {
  public let session: String

  public init(session: String) {
    self.session = session
  }
}

public struct AgentToolDescriptor: Codable, Sendable, Equatable {
  public let name: String
  public let description: String
  /// JSON Schema of the arguments, as a JSON document. Kept as text so the wire
  /// models stay plain `Codable`.
  public let inputSchema: String

  public init(name: String, description: String, inputSchema: String) {
    self.name = name
    self.description = description
    self.inputSchema = inputSchema
  }
}

public struct AgentToolList: Codable, Sendable, Equatable {
  public let tools: [AgentToolDescriptor]

  public init(tools: [AgentToolDescriptor]) {
    self.tools = tools
  }
}

public struct AgentCallParams: Codable, Sendable, Equatable {
  public let session: String
  public let name: String
  /// The tool arguments as a JSON object document.
  public let arguments: String

  public init(session: String, name: String, arguments: String) {
    self.session = session
    self.name = name
    self.arguments = arguments
  }
}

public struct AgentImage: Codable, Sendable, Equatable {
  public let mimeType: String
  public let base64: String

  public init(mimeType: String, base64: String) {
    self.mimeType = mimeType
    self.base64 = base64
  }
}

public struct AgentCallResult: Codable, Sendable, Equatable {
  public let text: String
  public let isError: Bool
  public let image: AgentImage?

  public init(text: String, isError: Bool, image: AgentImage? = nil) {
    self.text = text
    self.isError = isError
    self.image = image
  }
}
