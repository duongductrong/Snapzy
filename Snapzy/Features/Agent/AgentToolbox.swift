//
//  AgentToolbox.swift
//  Snapzy
//
//  Shared vocabulary of Snapzy's AI agents. A "surface" is where an agent works
//  (the Annotate canvas, later the Video Editor timeline): it brings its own tools
//  (`AgentToolbox`) and words (`AgentSurface`). Providers, the session and the
//  `snapzy mcp` bridge only see these types, never a surface's state.
//

import CoreGraphics
import Foundation

// MARK: - Tool results

/// What a tool returns to the model. `text` is JSON so every provider can pass it through.
nonisolated struct AgentToolResult: Equatable {
  let isError: Bool
  let text: String
  /// A picture for providers that can look (a video frame). Providers that can't, or may not
  /// send images, use `text` alone, so it must stand on its own.
  var image: AgentToolImage? = nil

  func with(image: AgentToolImage?) -> AgentToolResult {
    var copy = self
    copy.image = image
    return copy
  }

  static func success(_ payload: [String: Any]) -> AgentToolResult {
    var body = payload
    body["ok"] = true
    return AgentToolResult(isError: false, text: Self.json(body))
  }

  static func encoded<T: Encodable>(_ value: T) -> AgentToolResult {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
    return AgentToolResult(isError: false, text: String(decoding: data, as: UTF8.self))
  }

  /// An error written for the model: it should say what to do instead.
  static func failure(message: String) -> AgentToolResult {
    AgentToolResult(isError: true, text: Self.json(["ok": false, "error": message]))
  }

  private static func json(_ object: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else {
      return "{}"
    }
    return String(decoding: data, as: UTF8.self)
  }
}

/// A JPEG a tool hands back, already sized for a model (long edge ≤ `AgentEndpointProvider.maximumImageEdge`).
nonisolated struct AgentToolImage: Equatable {
  let mimeType: String
  let base64: String
  let pixelSize: CGSize

  var dataURL: String { "data:\(mimeType);base64,\(base64)" }

  /// Encodes off the main actor; nil when the image can't be encoded or is too large for the socket.
  static func jpeg(from image: CGImage) async -> AgentToolImage? {
    guard let encoded = await AgentEndpointImage.make(from: image, sceneSize: nil),
          let comma = encoded.dataURL.firstIndex(of: ",") else { return nil }
    let base64 = String(encoded.dataURL[encoded.dataURL.index(after: comma)...])
    guard base64.utf8.count <= AgentBridge.maximumSnapshotBase64Bytes else { return nil }
    return AgentToolImage(mimeType: "image/jpeg", base64: base64, pixelSize: CGSize(width: encoded.pixelSize.width, height: encoded.pixelSize.height))
  }
}

// MARK: - Tool specs

/// One tool as every provider sees it: OpenAI `tools`, plan-mode text, MCP `tools/list`.
nonisolated struct AgentToolSpec: Equatable {
  let name: String
  let description: String
  /// JSON Schema (object) for the arguments, serialized.
  let parametersJSON: String
}

// MARK: - Toolbox

/// The tools of one surface. Never throws: failures come back as error results the model can read.
@MainActor
protocol AgentToolbox: AnyObject {
  /// Words providers use when talking to the model about this surface.
  var surface: AgentSurface { get }
  var toolSpecs: [AgentToolSpec] { get }
  /// Read-only tools are not paced and don't count as changes.
  func isReadOnly(_ name: String) -> Bool
  /// Async so a surface may analyse media before answering (video); annotate answers synchronously.
  func execute(name: String, argumentsJSON: String) async -> AgentToolResult
}

// MARK: - Surface

/// What a provider needs to know about where it runs. Mode notes are appended to
/// `instructions` by each provider, so the words stay with the surface.
nonisolated struct AgentSurface {
  /// `annotate`, `video`.
  let id: String
  let logCategory: DiagnosticLogCategory
  /// Shared by every provider: what the app is, how targets are named, what not to do.
  let instructions: String
  /// Endpoint tools mode: the scene is already in the request.
  let toolsModeNote: String
  /// Endpoint plan mode: examples of how many ops a request needs.
  let planModeHint: String
  /// Agent CLI: tools are the only way to act, the scene is in the message.
  let cliModeNote: String
  /// MCP-only tool that returns the surface's picture, when the run has one.
  let snapshotToolDescription: String
  /// CLI prompt line when the picture is attached as a file.
  let imageAttachedNote: String
  /// CLI prompt line when the picture is available through the snapshot tool.
  let imageOnRequestNote: String
}

/// The scene value a surface sends with a request, for providers that need more than JSON.
nonisolated protocol AgentScene {
  /// Size of the coordinate space the scene uses for images, when it has one.
  var imageUnitSize: CGSize? { get }
}
