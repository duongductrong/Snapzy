//
//  AgentEndpointProvider.swift
//  Snapzy
//
//  A Snapzy AI prompt (any surface) answered by a user-configured OpenAI-compatible
//  endpoint (the shared custom endpoint list used by OCR and Translate).
//
//  - Tools mode: the surface's tool catalog goes out as `tools`; the model calls them,
//    results go back as `tool` messages, until it answers without tool calls.
//  - Plan mode: for endpoints without function calling. The model answers with
//    `{"ops": [{"tool", "args"}], "reply"}`; ops run in order, with one repair round.
//  - Vision: a downscaled screenshot rides along with the first message when the
//    endpoint accepts images.
//
//  What an endpoint can do is learned on the fly: an error that names tools or
//  images switches mode once and is remembered per endpoint.
//

import AppKit
import Foundation

/// What a custom endpoint turned out to support. `nil` = not known yet (try it).
nonisolated struct AgentEndpointCapabilities: Equatable {
  var supportsTools: Bool?
  var supportsVision: Bool?
}

/// Remembers endpoint capabilities per endpoint (UserDefaults, small dictionary). An entry
/// is tied to the endpoint's URL and model, so editing either forgets what was learned.
nonisolated struct AgentEndpointCapabilityStore {
  static let defaultsKey = "annotateAgent.endpointCapabilities"

  let defaults: UserDefaults

  static func fingerprint(of model: CustomOCRModel) -> String {
    model.baseURL.trimmingCharacters(in: .whitespacesAndNewlines) + "|" + model.modelIdentifier
  }

  func capabilities(for model: CustomOCRModel) -> AgentEndpointCapabilities {
    guard let entry = defaults.dictionary(forKey: Self.defaultsKey)?[model.id.uuidString] as? [String: Any],
          entry["fingerprint"] as? String == Self.fingerprint(of: model) else {
      return AgentEndpointCapabilities()
    }
    return AgentEndpointCapabilities(supportsTools: entry["tools"] as? Bool, supportsVision: entry["vision"] as? Bool)
  }

  func save(_ capabilities: AgentEndpointCapabilities, for model: CustomOCRModel) {
    var all = defaults.dictionary(forKey: Self.defaultsKey) ?? [:]
    var entry: [String: Any] = ["fingerprint": Self.fingerprint(of: model)]
    entry["tools"] = capabilities.supportsTools
    entry["vision"] = capabilities.supportsVision
    all[model.id.uuidString] = entry
    defaults.set(all, forKey: Self.defaultsKey)
  }
}

@MainActor
final class AgentEndpointProvider: AgentProvider {
  /// Defaults key: send the screenshot image along (scene text is always sent). Default on.
  static let sendImageDefaultsKey = PreferencesKeys.annotateAgentSendImage
  /// Model rounds per prompt in tools mode.
  static let maximumRounds = 12
  /// Earlier turns resent as chat history.
  static let historyLimit = 6
  /// Longest edge of the screenshot sent to vision models.
  nonisolated static let maximumImageEdge: CGFloat = 1568

  let model: CustomOCRModel
  var displayName: String { model.name }
  let symbolName = "network"

  /// Consent is tied to where the data goes: pointing the endpoint at another server asks again.
  var remoteDestination: AgentRemoteDestination? {
    let url = OpenAICompatibleChatClient.endpointURL(forBaseURL: model.baseURL)
    let host = url?.host ?? model.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let origin = [url?.scheme, host, url?.port.map(String.init)].compactMap { $0 }.joined(separator: ":")
    return AgentRemoteDestination(id: "endpoint:\(model.id.uuidString)@\(origin)", name: model.name, host: host)
  }

  private let keychainStore: OCRKeychainStoring
  private let urlSession: URLSessionProtocol
  private let defaults: UserDefaults
  private let timeout: TimeInterval
  private var capabilityStore: AgentEndpointCapabilityStore { .init(defaults: defaults) }

  init(
    model: CustomOCRModel,
    keychainStore: OCRKeychainStoring = OCRKeychainStore(),
    session: URLSessionProtocol = URLSession.shared,
    defaults: UserDefaults = .standard,
    timeout: TimeInterval = 90
  ) {
    self.model = model
    self.keychainStore = keychainStore
    self.urlSession = session
    self.defaults = defaults
    self.timeout = timeout
  }

  var capabilities: AgentEndpointCapabilities {
    capabilityStore.capabilities(for: model)
  }

  private var sendsImage: Bool {
    AnnotateAgentAISettings.sendsImage(defaults: defaults)
  }

  // MARK: - Run

  func run(_ request: AgentRequest, session: AgentSession) async throws -> String {
    session.report(L10n.AnnotateAI.statusContacting(model.name))

    var image: AgentEndpointImage?
    if sendsImage, capabilities.supportsVision != false, let source = request.image {
      image = await AgentEndpointImage.make(from: source, sceneSize: request.scene?.imageUnitSize)
      try Task.checkCancellation()
    }

    var conversation = Conversation(request: request, image: image)
    // Tools may hand back pictures too (a video frame); same rules as the opening image.
    conversation.sendsToolImages = sendsImage && capabilities.supportsVision != false
    let counter = ChangeCounter()
    do {
      if capabilities.supportsTools != false {
        do {
          return try await runWithTools(&conversation, session: session, counter: counter)
        } catch EndpointFallback.toolsUnsupported where counter.value == 0 {
          remember { $0.supportsTools = false }
          DiagnosticLogger.shared.log(.info, session.surface.logCategory, "AI endpoint has no tool calling; using plan mode")
        }
      }
      return try await runPlan(&conversation, session: session, counter: counter)
    } catch {
      throw Self.map(error)
    }
  }

  // MARK: - Tools mode

  private func runWithTools(
    _ conversation: inout Conversation,
    session: AgentSession,
    counter: ChangeCounter
  ) async throws -> String {
    var messages = conversation.openingMessages(system: Self.toolsInstructions(for: session.surface))
    let tools = Self.toolDefinitions(session.toolSpecs)
    var lastText = ""

    for round in 0..<Self.maximumRounds {
      try Task.checkCancellation()
      if round > 0 { session.report(L10n.AnnotateAI.statusThinking) }
      // Only the first request can tell "no tool calling": later errors are about the conversation.
      let message = try await complete(
        messages: &messages,
        conversation: &conversation,
        extra: ["tools": tools, "tool_choice": "auto"],
        mayRejectTools: round == 0,
        logCategory: session.surface.logCategory
      )
      if let text = message.text, !text.isEmpty { lastText = text }
      guard !message.toolCalls.isEmpty else {
        // Small local models often write the calls as JSON text instead of using `tools`.
        if round == 0, counter.value == 0, let text = message.text,
           let plan = AgentEndpointPlan.parse(text), !plan.ops.isEmpty {
          _ = try await apply(plan, session: session, counter: counter)
          return Self.cleanReply(plan.reply ?? "")
        }
        return Self.cleanReply(lastText)
      }

      messages.append(message.assistantMessage)
      var pictures: [(tool: String, image: AgentToolImage)] = []
      for call in message.toolCalls {
        let result = try await session.callTool(call.name, arguments: call.arguments)
        if !result.isError, !session.isReadOnly(call.name) {
          counter.increment()
        }
        messages.append([
          "role": "tool",
          "tool_call_id": call.id,
          "name": call.name,
          "content": result.text,
        ])
        if conversation.sendsToolImages, let image = result.image {
          pictures.append((call.name, image))
        }
      }
      // Tool messages are text only in the chat-completions API: pictures follow as a user turn.
      if let message = Conversation.toolImagesMessage(pictures) {
        messages = Conversation.keepingRecentToolImages(messages, limit: Conversation.toolImageHistory - pictures.count)
        messages.append(message)
      }
    }
    return Self.cleanReply(lastText)
  }

  // MARK: - Plan mode

  private func runPlan(
    _ conversation: inout Conversation,
    session: AgentSession,
    counter: ChangeCounter
  ) async throws -> String {
    var messages = conversation.openingMessages(system: Self.planInstructions(for: session.surface, tools: session.toolSpecs.filter {
      !session.isReadOnly($0.name)
    }))
    var reply = ""
    var parseRetried = false
    var repaired = false

    while true {
      try Task.checkCancellation()
      let message = try await complete(
        messages: &messages,
        conversation: &conversation,
        extra: [:],
        mayRejectTools: false,
        logCategory: session.surface.logCategory
      )
      let text = message.text ?? ""
      messages.append(["role": "assistant", "content": text])

      guard let plan = AgentEndpointPlan.parse(text) else {
        // A model that answers in prose may simply have nothing to do; ask once for JSON.
        if parseRetried {
          if counter.value > 0 || !text.isEmpty { return Self.cleanReply(text) }
          throw AgentProviderError.failed(L10n.AnnotateAI.invalidReply)
        }
        parseRetried = true
        messages.append(["role": "user", "content": Self.planFormatReminder])
        continue
      }
      if let planReply = plan.reply, !planReply.isEmpty { reply = planReply }

      let failures = try await apply(plan, session: session, counter: counter)
      guard !failures.isEmpty, !repaired else { return Self.cleanReply(reply) }
      repaired = true
      session.report(L10n.AnnotateAI.statusThinking)
      messages.append([
        "role": "user",
        "content": "These ops failed:\n" + failures.joined(separator: "\n")
          + "\nThe other ops were applied. Reply with the same JSON format containing only corrected ops (or an empty ops list) and an updated reply.",
      ])
    }
  }

  /// Runs the ops in order; returns one line per failed op for the repair round.
  private func apply(
    _ plan: AgentEndpointPlan,
    session: AgentSession,
    counter: ChangeCounter
  ) async throws -> [String] {
    var failures: [String] = []
    for (index, op) in plan.ops.enumerated() {
      let result = try await session.callTool(op.tool, arguments: op.arguments)
      if result.isError {
        failures.append("op \(index + 1) \(op.tool): \(result.text)")
      } else if !session.isReadOnly(op.tool) {
        counter.increment()
      }
    }
    return failures
  }

  // MARK: - Transport

  /// One chat-completions call. Retries once without the image or without `temperature`
  /// when the endpoint rejects them; reports `toolsUnsupported` when it rejects tools.
  private func complete(
    messages: inout [[String: Any]],
    conversation: inout Conversation,
    extra: [String: Any],
    mayRejectTools: Bool,
    logCategory: DiagnosticLogCategory
  ) async throws -> AgentEndpointMessage {
    while true {
      var body: [String: Any] = [
        "model": model.modelIdentifier,
        "messages": messages,
      ]
      if conversation.sendsTemperature { body["temperature"] = 0.2 }
      for (key, value) in extra { body[key] = value }
      let data = try JSONSerialization.data(withJSONObject: body)
      let client = OpenAICompatibleChatClient(model: model, keychainStore: keychainStore, session: urlSession, timeout: timeout)
      do {
        let response = try await client.send(jsonBody: data)
        try Task.checkCancellation()
        if conversation.hasImages(in: messages) { remember { $0.supportsVision = true } }
        guard let message = AgentEndpointMessage.parse(response) else {
          throw AgentProviderError.failed(L10n.AnnotateAI.invalidReply)
        }
        if !message.toolCalls.isEmpty { remember { $0.supportsTools = true } }
        return message
      } catch RemoteOCRError.httpStatus(let status, let snippet) {
        try Task.checkCancellation()
        switch Self.rejection(status: status, body: snippet) {
        case .tools? where extra["tools"] != nil && mayRejectTools:
          throw EndpointFallback.toolsUnsupported
        case .images? where conversation.hasImages(in: messages):
          remember { $0.supportsVision = false }
          conversation.image = nil
          conversation.sendsToolImages = false
          messages = Conversation.removingImages(from: messages)
          DiagnosticLogger.shared.log(.info, logCategory, "AI endpoint rejected the image; retrying with text only")
          continue
        case .temperature? where conversation.sendsTemperature:
          conversation.sendsTemperature = false
          continue
        default:
          throw RemoteOCRError.httpStatus(status, snippet)
        }
      }
    }
  }

  enum Rejection: Equatable { case tools, images, temperature }

  /// Reads a 4xx/5xx body for "this model can't do tools / images / a custom temperature".
  /// Servers word it differently (Ollama "does not support tools", OpenAI "image_url is only
  /// supported by…", "Unsupported value: 'temperature'"). Tools are checked first: a model
  /// named "…-vision" that lacks tools must not lose its image instead.
  nonisolated static func rejection(status: Int, body: String) -> Rejection? {
    guard [400, 404, 415, 422, 500, 501].contains(status) else { return nil }
    let text = body.lowercased()
    let refusal = ["not support", "unsupported", "not supported", "only supported", "not allowed",
                   "unknown", "unrecognized", "invalid", "not implemented", "doesn't support", "does not accept"]
    guard refusal.contains(where: text.contains) else { return nil }
    if ["tools", "tool_choice", "tool calling", "tool use", "function calling", "functions"].contains(where: text.contains) {
      return .tools
    }
    if ["image", "vision", "multimodal", "multi-modal"].contains(where: text.contains) { return .images }
    if text.contains("temperature") { return .temperature }
    return nil
  }

  private func remember(_ change: (inout AgentEndpointCapabilities) -> Void) {
    var updated = capabilities
    change(&updated)
    guard updated != capabilities else { return }
    capabilityStore.save(updated, for: model)
  }

  private enum EndpointFallback: Error { case toolsUnsupported }

  /// Transport and HTTP errors → what the pill shows.
  static func map(_ error: Error) -> Error {
    if error is CancellationError || Task.isCancelled { return CancellationError() }
    if let error = error as? AgentProviderError { return error }
    if let remote = error as? RemoteOCRError {
      if case .unreachable(let urlError) = remote, urlError.code == .cancelled { return CancellationError() }
      return AgentProviderError.failed(remote.errorDescription ?? L10n.AnnotateAI.failed)
    }
    return AgentProviderError.failed(L10n.AnnotateAI.failed)
  }

  static func cleanReply(_ text: String) -> String {
    AgentReplyFormatter.oneLine(text)
  }

  // MARK: - Conversation

  /// The opening messages of a run: system, earlier turns, then scene + request (+ image).
  struct Conversation {
    let request: AgentRequest
    var image: AgentEndpointImage?
    /// Some models (OpenAI reasoning models) accept only the default temperature.
    var sendsTemperature = true
    /// Pass on pictures tools return. Off when the user keeps images on the Mac or the model can't see.
    var sendsToolImages = false

    func hasImages(in messages: [[String: Any]]) -> Bool {
      image != nil || messages.contains { message in
        (message["content"] as? [[String: Any]])?.contains { $0["type"] as? String == "image_url" } ?? false
      }
    }

    /// Earlier tool pictures resent each round add up (each up to ~900 KB): keep the newest ones.
    static let toolImageHistory = 2
    static let toolImagesMarker = "Image returned by "

    /// Older tool-image messages lose their pictures (text kept), so at most `limit` remain.
    static func keepingRecentToolImages(_ messages: [[String: Any]], limit: Int) -> [[String: Any]] {
      var remaining = max(0, limit)
      var result = messages
      for index in result.indices.reversed() {
        guard let parts = result[index]["content"] as? [[String: Any]],
              (parts.first?["text"] as? String)?.hasPrefix(toolImagesMarker) == true else { continue }
        var kept: [[String: Any]] = []
        for part in parts {
          if part["type"] as? String == "image_url" {
            if remaining > 0 { remaining -= 1; kept.append(part) }
          } else {
            kept.append(part)
          }
        }
        if kept.contains(where: { $0["type"] as? String == "image_url" }) {
          result[index]["content"] = kept
        } else {
          result[index]["content"] = kept.compactMap { $0["text"] as? String }.joined(separator: " ") + " (no longer attached)"
        }
      }
      return result
    }

    /// One user message carrying the pictures the last tool calls returned, or nil when there are none.
    static func toolImagesMessage(_ pictures: [(tool: String, image: AgentToolImage)]) -> [String: Any]? {
      guard !pictures.isEmpty else { return nil }
      var parts: [[String: Any]] = []
      for picture in pictures {
        let size = "\(Int(picture.image.pixelSize.width))×\(Int(picture.image.pixelSize.height))"
        parts.append(["type": "text", "text": "\(toolImagesMarker)\(picture.tool) (\(size) pixels):"])
        parts.append(["type": "image_url", "image_url": ["url": picture.image.dataURL]])
      }
      return ["role": "user", "content": parts]
    }

    func openingMessages(system: String) -> [[String: Any]] {
      var messages: [[String: Any]] = [["role": "system", "content": system]]
      for turn in request.history.suffix(AgentEndpointProvider.historyLimit) {
        messages.append(["role": "user", "content": String(turn.prompt.prefix(500))])
        messages.append(["role": "assistant", "content": String(turn.reply.prefix(500))])
      }
      var text = "Scene: \(request.sceneJSON)"
      if let image {
        text += "\n\nThe attached screenshot is \(image.pixelSize.width)×\(image.pixelSize.height) pixels."
        if image.scale != 1 {
          text += " Scene coordinates are in image units: divide screenshot pixels by \(Self.format(image.scale)) to get them."
        }
      }
      text += "\n\nRequest: \(request.prompt)"
      if let image {
        messages.append(["role": "user", "content": [
          ["type": "text", "text": text],
          ["type": "image_url", "image_url": ["url": image.dataURL]],
        ]])
      } else {
        messages.append(["role": "user", "content": text])
      }
      return messages
    }

    /// Same messages with image parts dropped (text parts flattened back to a string).
    static func removingImages(from messages: [[String: Any]]) -> [[String: Any]] {
      messages.map { message in
        guard let parts = message["content"] as? [[String: Any]] else { return message }
        var copy = message
        copy["content"] = parts.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
          .joined(separator: "\n\n")
        return copy
      }
    }

    private static func format(_ value: Double) -> String {
      String(format: "%.3g", value)
    }
  }

  final class ChangeCounter {
    private(set) var value = 0
    func increment() { value += 1 }
  }

  // MARK: - Instructions

  static func toolsInstructions(for surface: AgentSurface) -> String {
    surface.instructions + """

    \(surface.toolsModeNote) \
    You may call several tools at once. When done, answer with one short sentence in the user's language saying what you changed.
    """
  }

  /// `tools`: the changing tools only; reading happens through the scene in the request.
  static func planInstructions(for surface: AgentSurface, tools: [AgentToolSpec]) -> String {
    let list = tools
      .map { "- \($0.name): \($0.description) Arguments schema: \($0.parametersJSON)" }
      .joined(separator: "\n")
    return surface.instructions + """

    You can't call tools directly. Answer with only a JSON object, no prose and no code fence:
    {"ops": [{"tool": "<tool name>", "args": {…}}], "reply": "<one short sentence in the user's language saying what you changed>"}
    Ops run in order. Every change the user asks for needs an op: \(surface.planModeHint) \
    Use an empty ops list only when nothing should change.
    Tools:
    \(list)
    """
  }

  static let planFormatReminder = """
  Answer with only the JSON object {"ops": [{"tool": "…", "args": {…}}], "reply": "…"}. Use an empty ops list if nothing should change.
  """

  /// OpenAI `tools` array.
  static func toolDefinitions(_ specs: [AgentToolSpec]) -> [[String: Any]] {
    specs.map { spec in
      let parameters = (try? JSONSerialization.jsonObject(with: Data(spec.parametersJSON.utf8))) ?? [:]
      return [
        "type": "function",
        "function": [
          "name": spec.name,
          "description": spec.description,
          "parameters": parameters,
        ] as [String: Any],
      ]
    }
  }
}

// MARK: - Response parsing

/// The assistant message of a chat-completions answer.
nonisolated struct AgentEndpointMessage {
  struct ToolCall: Equatable {
    let id: String
    let name: String
    /// JSON object text.
    let arguments: String
  }

  let text: String?
  let toolCalls: [ToolCall]
  /// The message as sent back in the next request (tool calls normalized).
  let assistantMessage: [String: Any]

  static func parse(_ data: Data) -> AgentEndpointMessage? {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let choices = object["choices"] as? [[String: Any]],
          let message = choices.first?["message"] as? [String: Any] else {
      return nil
    }
    let text = Self.text(from: message["content"])?.trimmingCharacters(in: .whitespacesAndNewlines)
    var calls: [ToolCall] = []
    var rawCalls: [[String: Any]] = []
    for (index, raw) in ((message["tool_calls"] as? [[String: Any]]) ?? []).enumerated() {
      guard let function = raw["function"] as? [String: Any], let name = function["name"] as? String else { continue }
      let id = (raw["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "call_\(index + 1)"
      let arguments = Self.argumentsText(function["arguments"])
      calls.append(ToolCall(id: id, name: name, arguments: arguments))
      rawCalls.append([
        "id": id,
        "type": "function",
        "function": ["name": name, "arguments": arguments],
      ])
    }
    var assistant: [String: Any] = ["role": "assistant", "content": text ?? ""]
    if !rawCalls.isEmpty { assistant["tool_calls"] = rawCalls }
    return AgentEndpointMessage(text: text, toolCalls: calls, assistantMessage: assistant)
  }

  /// `content` is a string, an array of parts, or null.
  private static func text(from content: Any?) -> String? {
    if let string = content as? String { return string }
    if let parts = content as? [[String: Any]] {
      return parts.compactMap { $0["text"] as? String }.joined()
    }
    return nil
  }

  /// OpenAI sends arguments as a JSON string; some servers (Ollama) send an object.
  private static func argumentsText(_ value: Any?) -> String {
    if let string = value as? String {
      return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}" : string
    }
    if let value, JSONSerialization.isValidJSONObject(value),
       let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
      return String(decoding: data, as: UTF8.self)
    }
    return "{}"
  }
}

/// Plan-mode answer: `{"ops": [{"tool", "args"}], "reply"}`.
nonisolated struct AgentEndpointPlan: Equatable {
  struct Op: Equatable {
    let tool: String
    /// JSON object text.
    let arguments: String
  }

  let ops: [Op]
  let reply: String?

  /// Tolerates code fences and prose around the object; accepts `name`/`arguments`
  /// spellings and a bare array of ops.
  static func parse(_ text: String) -> AgentEndpointPlan? {
    for candidate in Self.jsonCandidates(in: text) {
      if let object = try? JSONSerialization.jsonObject(with: Data(candidate.utf8)), let plan = Self.plan(from: object) {
        return plan
      }
    }
    return nil
  }

  private static func plan(from object: Any) -> AgentEndpointPlan? {
    let rawOps: [[String: Any]]
    var reply: String?
    if let dictionary = object as? [String: Any] {
      guard let ops = dictionary["ops"] as? [[String: Any]] ?? dictionary["operations"] as? [[String: Any]] else {
        return nil
      }
      rawOps = ops
      reply = dictionary["reply"] as? String ?? dictionary["summary"] as? String
    } else if let ops = object as? [[String: Any]] {
      rawOps = ops
    } else {
      return nil
    }
    let ops = rawOps.compactMap { raw -> Op? in
      guard let tool = raw["tool"] as? String ?? raw["name"] as? String else { return nil }
      let args = raw["args"] ?? raw["arguments"] ?? [String: Any]()
      if let string = args as? String { return Op(tool: tool, arguments: string) }
      guard JSONSerialization.isValidJSONObject(args),
            let data = try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys]) else {
        return Op(tool: tool, arguments: "{}")
      }
      return Op(tool: tool, arguments: String(decoding: data, as: UTF8.self))
    }
    return AgentEndpointPlan(ops: ops, reply: reply)
  }

  /// The outermost `{…}` and `[…]` spans of the text, earliest-opening first.
  private static func jsonCandidates(in text: String) -> [String] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    var spans: [(start: String.Index, text: String)] = []
    for (open, close) in [("{", "}"), ("[", "]")] {
      if let start = trimmed.range(of: open), let end = trimmed.range(of: close, options: .backwards),
         start.lowerBound < end.lowerBound {
        spans.append((start.lowerBound, String(trimmed[start.lowerBound..<end.upperBound])))
      }
    }
    return spans.sorted { $0.start < $1.start }.map(\.text)
  }
}

// MARK: - Image

/// The screenshot as a JPEG data URL, at most `maximumImageEdge` on its long side.
nonisolated struct AgentEndpointImage: Equatable {
  let dataURL: String
  let pixelSize: (width: Int, height: Int)
  /// Screenshot pixels per scene unit.
  let scale: Double

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.dataURL == rhs.dataURL && lhs.pixelSize == rhs.pixelSize && lhs.scale == rhs.scale
  }

  static func make(from image: CGImage, sceneSize: CGSize?) async -> AgentEndpointImage? {
    await Task.detached(priority: .userInitiated) {
      encode(image, sceneSize: sceneSize)
    }.value
  }

  static func encode(_ image: CGImage, sceneSize: CGSize?) -> AgentEndpointImage? {
    let units = sceneSize.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
      ?? CGSize(width: image.width, height: image.height)
    // Prefer one pixel per scene unit so the model can read coordinates straight off the image.
    let longEdge = max(units.width, units.height)
    let scale = longEdge > AgentEndpointProvider.maximumImageEdge
      ? AgentEndpointProvider.maximumImageEdge / longEdge
      : 1
    let width = max(Int((units.width * scale).rounded()), 1)
    let height = max(Int((units.height * scale).rounded()), 1)

    return autoreleasepool {
      guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      ) else { return nil }
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      guard let scaled = context.makeImage() else { return nil }
      let bitmap = NSBitmapImageRep(cgImage: scaled)
      guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return nil }
      return AgentEndpointImage(
        dataURL: "data:image/jpeg;base64,\(jpeg.base64EncodedString())",
        pixelSize: (width, height),
        scale: Double(scale)
      )
    }
  }
}
