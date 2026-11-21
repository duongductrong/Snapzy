//
//  AnnotateAgentEndpointProbe.swift
//  Snapzy
//
//  Settings › AI › Test: asks a custom endpoint two tiny questions to learn whether
//  it calls tools and accepts images, and remembers the answers the same way a real
//  prompt would (AgentEndpointCapabilityStore).
//

import AppKit
import Foundation

@MainActor
enum AnnotateAgentEndpointProbe {
  enum Outcome: Equatable {
    case finished(AgentEndpointCapabilities)
    case failed(String)
  }

  static func run(
    _ model: CustomOCRModel,
    keychainStore: OCRKeychainStoring = OCRKeychainStore(),
    session: URLSessionProtocol = URLSession.shared,
    defaults: UserDefaults = .standard,
    timeout: TimeInterval = 45
  ) async -> Outcome {
    let client = OpenAICompatibleChatClient(model: model, keychainStore: keychainStore, session: session, timeout: timeout)
    let store = AgentEndpointCapabilityStore(defaults: defaults)
    var capabilities = store.capabilities(for: model)

    do {
      // A text answer proves nothing either way: keep what real prompts already learned.
      if let tools = try await probeTools(client: client, model: model) {
        capabilities.supportsTools = tools
      }
      capabilities.supportsVision = try await probeVision(client: client, model: model)
    } catch {
      if error is CancellationError { return .failed(L10n.AnnotateAI.failed) }
      if case AgentProviderError.failed(let message) = AgentEndpointProvider.map(error) {
        return .failed(message)
      }
      return .failed(L10n.AnnotateAI.failed)
    }
    store.save(capabilities, for: model)
    return .finished(capabilities)
  }

  /// `true` when the model called the tool, `false` when the endpoint rejects tools,
  /// `nil` when it answered in text instead (a real prompt will find out).
  static func probeTools(client: OpenAICompatibleChatClient, model: CustomOCRModel) async throws -> Bool? {
    let body: [String: Any] = [
      "model": model.modelIdentifier,
      "messages": [
        ["role": "user", "content": "Call the ping tool once. Do not answer in text."],
      ],
      "tools": [[
        "type": "function",
        "function": [
          "name": "ping",
          "description": "Connectivity check. Call it when asked.",
          "parameters": ["type": "object", "properties": [String: Any]()],
        ] as [String: Any],
      ]],
      "tool_choice": "auto",
    ]
    do {
      let data = try await client.send(jsonBody: JSONSerialization.data(withJSONObject: body))
      guard let message = AgentEndpointMessage.parse(data) else {
        throw AgentProviderError.failed(L10n.AnnotateAI.invalidReply)
      }
      return message.toolCalls.isEmpty ? nil : true
    } catch RemoteOCRError.httpStatus(let status, let snippet) {
      if AgentEndpointProvider.rejection(status: status, body: snippet) == .tools { return false }
      throw RemoteOCRError.httpStatus(status, snippet)
    }
  }

  /// `true` when a tiny image goes through, `false` when the endpoint rejects images.
  static func probeVision(client: OpenAICompatibleChatClient, model: CustomOCRModel) async throws -> Bool {
    let body: [String: Any] = [
      "model": model.modelIdentifier,
      "messages": [[
        "role": "user",
        "content": [
          ["type": "text", "text": "What color is this image? Answer with one word."],
          ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(probeImageBase64)"]],
        ] as [[String: Any]],
      ]],
    ]
    do {
      _ = try await client.send(jsonBody: JSONSerialization.data(withJSONObject: body))
      return true
    } catch RemoteOCRError.httpStatus(let status, let snippet) {
      if AgentEndpointProvider.rejection(status: status, body: snippet) == .images { return false }
      throw RemoteOCRError.httpStatus(status, snippet)
    }
  }

  /// A 16×16 solid red PNG, drawn on demand (some servers reject images under a few pixels).
  static let probeImageBase64: String = {
    let size = 16
    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0
    ) else { return "" }
    for x in 0..<size {
      for y in 0..<size {
        rep.setColor(NSColor(deviceRed: 0.9, green: 0.1, blue: 0.1, alpha: 1), atX: x, y: y)
      }
    }
    return rep.representation(using: .png, properties: [:])?.base64EncodedString() ?? ""
  }()
}
