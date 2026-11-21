//
//  MCPServer.swift
//  SnapzyCLICore
//
//  A minimal Model Context Protocol server over stdio (newline-delimited
//  JSON-RPC 2.0) that forwards `tools/list` and `tools/call` to Snapzy. Only the
//  tools capability is offered: no resources, prompts, or sampling.
//

import Foundation
import SnapzyCLIClient
import SnapzyCLIProtocol

/// Where tool calls go. The real one talks to Snapzy over the socket; tests fake it.
protocol MCPToolBackend {
  func listTools() async throws -> [AgentToolDescriptor]
  func callTool(name: String, arguments: String) async throws -> AgentCallResult
}

struct MCPMessageHandler {
  /// Newest first; the client's version is echoed when we know it.
  static let supportedProtocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
  static let serverName = "snapzy"

  let backend: MCPToolBackend
  let serverVersion: String

  /// Handles one line. Returns the response line, or `nil` for notifications.
  func handle(_ line: Data) async -> Data? {
    guard
      let object = try? JSONSerialization.jsonObject(with: line),
      let message = object as? [String: Any]
    else {
      return Self.encode(error: (-32700, "Parse error"), id: NSNull())
    }
    guard let method = message["method"] as? String else {
      // A response to something we never send (sampling, elicitation): ignore.
      return nil
    }
    // Notifications have no id and never get an answer.
    guard let id = message["id"], !(id is NSNull) else { return nil }
    let params = message["params"] as? [String: Any] ?? [:]

    switch method {
    case "initialize":
      let requested = params["protocolVersion"] as? String
      let version = requested.flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil }
        ?? Self.supportedProtocolVersions[1]
      return Self.encode(result: [
        "protocolVersion": version,
        "capabilities": ["tools": ["listChanged": false]],
        "serverInfo": ["name": Self.serverName, "version": serverVersion],
        "instructions": "Tools that annotate the screenshot open in Snapzy's Annotate window. Call get_scene first unless the prompt already includes the scene.",
      ], id: id)
    case "ping":
      return Self.encode(result: [:], id: id)
    case "tools/list":
      do {
        let tools = try await backend.listTools().map { tool -> [String: Any] in
          let schema = (try? JSONSerialization.jsonObject(with: Data(tool.inputSchema.utf8))) as? [String: Any]
          return [
            "name": tool.name,
            "description": tool.description,
            "inputSchema": schema ?? ["type": "object"],
          ]
        }
        return Self.encode(result: ["tools": tools], id: id)
      } catch {
        return Self.encode(error: (-32603, Self.describe(error)), id: id)
      }
    case "tools/call":
      guard let name = params["name"] as? String else {
        return Self.encode(error: (-32602, "tools/call needs a tool name"), id: id)
      }
      let arguments = params["arguments"] as? [String: Any] ?? [:]
      let argumentsJSON = (try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]))
        .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
      do {
        let result = try await backend.callTool(name: name, arguments: argumentsJSON)
        var content: [[String: Any]] = [["type": "text", "text": result.text]]
        if let image = result.image {
          content.append(["type": "image", "data": image.base64, "mimeType": image.mimeType])
        }
        return Self.encode(result: ["content": content, "isError": result.isError], id: id)
      } catch {
        // A tool error the model can read beats a protocol error it cannot.
        return Self.encode(result: [
          "content": [["type": "text", "text": Self.describe(error)]],
          "isError": true,
        ], id: id)
      }
    default:
      return Self.encode(error: (-32601, "Method not found: \(method)"), id: id)
    }
  }

  private static func describe(_ error: Error) -> String {
    guard let error = error as? CLIError else { return String(describing: error) }
    switch error.code {
    case .notAuthorized:
      return "This Snapzy session has ended. Stop and reply to the user."
    default:
      return error.hint.map { "\(error.message) (\($0))" } ?? error.message
    }
  }

  private static func encode(result: [String: Any], id: Any) -> Data {
    serialize(["jsonrpc": "2.0", "id": id, "result": result])
  }

  private static func encode(error: (code: Int, message: String), id: Any) -> Data {
    serialize(["jsonrpc": "2.0", "id": id, "error": ["code": error.code, "message": error.message]])
  }

  private static func serialize(_ object: [String: Any]) -> Data {
    (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]))
      ?? Data(#"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Could not encode response"}}"#.utf8)
  }
}

/// Talks to Snapzy with a fresh connection per request: an agent can think for
/// longer than the socket's idle timeout, and a local connect is cheap.
struct SocketToolBackend: MCPToolBackend {
  let session: String
  let options: CLISession.Options

  func listTools() async throws -> [AgentToolDescriptor] {
    let client = try await CLISession.open(options)
    defer { client.close() }
    return try client.call(.agentTools, params: AgentToolsParams(session: session), as: AgentToolList.self).tools
  }

  func callTool(name: String, arguments: String) async throws -> AgentCallResult {
    let client = try await CLISession.open(options)
    defer { client.close() }
    return try client.call(
      .agentCall,
      params: AgentCallParams(session: session, name: name, arguments: arguments),
      as: AgentCallResult.self
    )
  }
}
