//
//  AgentBridge.swift
//  Snapzy
//
//  Lets `snapzy mcp` (started by an agent CLI Snapzy spawned) reach the one
//  AI run that spawned it (Annotate, Video Editor). Each run gets a random token;
//  the socket's `agent.tools` / `agent.call` only work with a live token, and the
//  token dies when the run ends or is stopped. No token, no tools on the socket.
//

import CoreGraphics
import Foundation
import Security
import SnapzyCLIProtocol

@MainActor
final class AgentBridge {
  static let shared = AgentBridge()

  /// MCP-only tool: the surface's picture as an image, for agents that look at pixels.
  static let snapshotToolName = "get_snapshot"
  /// Socket frames are capped at 1 MiB; leave room for the JSON around the image.
  nonisolated static let maximumSnapshotBase64Bytes = 900_000

  private struct Entry {
    weak var session: AgentSession?
    let image: CGImage?
    let sceneSize: CGSize?
    /// Pictures tools return (a video frame) are passed on only when the user lets images go.
    let allowsToolImages: Bool
    var snapshot: AgentImage?
  }

  private var entries: [String: Entry] = [:]

  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  /// Opens a bridge for one run. Close it with `close(_:)` when the run ends.
  /// - Parameter allowsToolImages: pass on images tools return (Settings › AI › send image).
  func open(session: AgentSession, image: CGImage?, sceneSize: CGSize?, allowsToolImages: Bool = false) -> String {
    let token = Self.makeToken()
    entries[token] = Entry(session: session, image: image, sceneSize: sceneSize, allowsToolImages: allowsToolImages)
    return token
  }

  func close(_ token: String) {
    entries[token] = nil
  }

  var openCount: Int { entries.count }

  func tools(token: String) throws -> [AgentToolDescriptor] {
    let entry = try liveEntry(token)
    guard let session = entry.session else { throw Self.expired }
    var tools = session.toolSpecs.map {
      AgentToolDescriptor(name: $0.name, description: $0.description, inputSchema: $0.parametersJSON)
    }
    if entry.image != nil {
      tools.append(AgentToolDescriptor(
        name: Self.snapshotToolName,
        description: session.surface.snapshotToolDescription,
        inputSchema: #"{"properties":{},"type":"object"}"#
      ))
    }
    return tools
  }

  func call(token: String, name: String, arguments: String) async throws -> AgentCallResult {
    var entry = try liveEntry(token)
    guard let session = entry.session else { throw Self.expired }

    if name == Self.snapshotToolName {
      if entry.snapshot == nil, let image = entry.image {
        entry.snapshot = await Self.snapshot(of: image, sceneSize: entry.sceneSize)
        // The run may have ended while the image was encoded.
        guard entries[token] != nil else { throw Self.expired }
        entries[token]?.snapshot = entry.snapshot
      }
      guard let snapshot = entry.snapshot else {
        return AgentCallResult(text: #"{"error":"No screenshot is available.","ok":false}"#, isError: true)
      }
      return AgentCallResult(text: #"{"ok":true}"#, isError: false, image: snapshot)
    }

    do {
      let result = try await session.callTool(name, arguments: arguments)
      let image = entry.allowsToolImages ? result.image.map { AgentImage(mimeType: $0.mimeType, base64: $0.base64) } : nil
      return AgentCallResult(text: result.text, isError: result.isError, image: image)
    } catch is CancellationError {
      throw Self.expired
    }
  }

  private func liveEntry(_ token: String) throws -> Entry {
    guard let entry = entries[token], let session = entry.session, session.isActive else {
      entries[token] = nil
      throw Self.expired
    }
    return entry
  }

  private static let expired = CLIError(.notAuthorized, "This Snapzy AI session has ended")

  private static func makeToken() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
      // Never expected; UUIDs are still unguessable enough for a per-run, same-user token.
      return UUID().uuidString + UUID().uuidString
    }
    return bytes.map { String(format: "%02x", $0) }.joined()
  }

  static func snapshot(of image: CGImage, sceneSize: CGSize?) async -> AgentImage? {
    guard let encoded = await AgentEndpointImage.make(from: image, sceneSize: sceneSize),
          let comma = encoded.dataURL.firstIndex(of: ",") else { return nil }
    let base64 = String(encoded.dataURL[encoded.dataURL.index(after: comma)...])
    guard base64.utf8.count <= maximumSnapshotBase64Bytes else { return nil }
    return AgentImage(mimeType: "image/jpeg", base64: base64)
  }
}
