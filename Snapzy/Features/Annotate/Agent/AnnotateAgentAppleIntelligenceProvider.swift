//
//  AnnotateAgentAppleIntelligenceProvider.swift
//  Snapzy
//
//  Annotate AI prompt answered by the on-device Apple Intelligence model
//  (FoundationModels, macOS 26). The model has a 4K-token context shared by
//  instructions, tool schemas, scene, transcript and answer, so it gets a compact
//  scene and four coarse tools (draw / edit / canvas / find_text) that map onto the
//  shared toolbox instead of the full 17-tool catalog.
//

import AppKit
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Availability checks callable from any macOS version.
@MainActor
enum AnnotateAgentAppleIntelligence {
  static var isAvailable: Bool {
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
      return SystemLanguageModel.default.availability == .available
    }
    #endif
    return false
  }

  /// Why the on-device model can or can't answer, for Settings.
  enum Status: Equatable {
    case available
    /// macOS older than 26 (or an SDK without FoundationModels).
    case unsupportedOS
    case deviceNotEligible
    case notEnabled
    /// Downloading or otherwise not ready yet.
    case modelNotReady
  }

  static var status: Status {
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
      switch SystemLanguageModel.default.availability {
      case .available:
        return .available
      case .unavailable(.deviceNotEligible):
        return .deviceNotEligible
      case .unavailable(.appleIntelligenceNotEnabled):
        return .notEnabled
      case .unavailable:
        return .modelNotReady
      }
    }
    #endif
    return .unsupportedOS
  }

  /// System Settings › Apple Intelligence & Siri.
  static func openSystemSettings() {
    let candidates = [
      "x-apple.systempreferences:com.apple.Siri-Settings.extension",
      "x-apple.systempreferences:com.apple.preference.speech",
    ]
    for candidate in candidates {
      if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
    }
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
  }

  /// Loads model assets ahead of the first prompt. Cheap to call repeatedly.
  static func prewarm() {
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *), isAvailable, Date().timeIntervalSince(lastPrewarm) > 60 {
      lastPrewarm = Date()
      LanguageModelSession(
        model: .default,
        instructions: AnnotateAgentAppleIntelligenceProvider.instructions
      ).prewarm()
    }
    #endif
  }

  private static var lastPrewarm = Date.distantPast

  static func makeProviderIfAvailable() -> AnnotateAgentProvider? {
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *), isAvailable {
      return AnnotateAgentAppleIntelligenceProvider()
    }
    #endif
    return nil
  }
}

#if canImport(FoundationModels)

@available(macOS 26.0, *)
@MainActor
final class AnnotateAgentAppleIntelligenceProvider: AnnotateAgentProvider {
  let displayName = "Apple Intelligence"
  let symbolName = "apple.intelligence"

  /// Scene budgets: first try, then the retry after `exceededContextWindowSize`.
  static let sceneBudgets: [(texts: Int, length: Int)] = [(40, 60), (20, 40)]
  /// Earlier turns sent along as a reminder (each one line).
  static let historyLimit = 3

  static let instructions = """
  You edit a screenshot in Snapzy by calling tools. Do what the user asks right away; never ask questions.
  The scene lists text blocks (t1, t2…), UI elements (e1…) and existing annotations (a1…). \
  Rects are [x, y, width, height] in image units, origin top-left.
  For a target, prefer an id from the scene, or the exact visible text. Call draw once per item.
  "it"/"that" usually means the annotations made in the previous turn or the selection.
  When done, reply with one short sentence in the user's language saying what you changed.
  """

  func run(_ request: AnnotateAgentRequest, session: AnnotateAgentSession) async throws -> String {
    session.report(L10n.AnnotateAI.statusThinking)
    let counter = AnnotateAgentChangeCounter()
    var lastError: Error?

    for (index, budget) in Self.sceneBudgets.enumerated() {
      try Task.checkCancellation()
      let prompt = Self.prompt(for: request, budget: budget)
      let model = LanguageModelSession(
        model: .default,
        tools: Self.tools(session: session, counter: counter),
        instructions: Self.instructions
      )
      do {
        let response = try await model.respond(
          to: prompt,
          options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 300)
        )
        try Task.checkCancellation()
        return Self.cleanReply(response.content)
      } catch {
        try Task.checkCancellation()
        let mapped = Self.map(error)
        if mapped is CancellationError { throw mapped }
        // Retry with a smaller scene only when nothing changed yet, so nothing is drawn twice.
        if Self.isContextOverflow(error) {
          if counter.value > 0 { return "" }
          if index < Self.sceneBudgets.count - 1 {
            lastError = mapped
            continue
          }
        }
        throw mapped
      }
    }
    throw lastError ?? AnnotateAgentProviderError.failed(L10n.AnnotateAI.failed)
  }

  // MARK: - Prompt

  static func prompt(for request: AnnotateAgentRequest, budget: (texts: Int, length: Int)) -> String {
    var parts: [String] = []
    let sceneJSON = request.scene
      .map { AnnotateAgentToolResult.encoded($0.compacted(maximumTexts: budget.texts, maximumTextLength: budget.length)).text }
      ?? request.sceneJSON
    parts.append("Scene: \(sceneJSON)")
    let history = request.history.suffix(historyLimit)
    if !history.isEmpty {
      let lines = history.map { "- User: \(String($0.prompt.prefix(120))) → You: \(String($0.reply.prefix(120)))" }
      parts.append("Earlier turns:\n" + lines.joined(separator: "\n"))
    }
    parts.append("Request: \(request.prompt)")
    return parts.joined(separator: "\n\n")
  }

  static func cleanReply(_ text: String) -> String {
    AnnotateAgentReplyFormatter.oneLine(text)
  }

  // MARK: - Errors

  static func isContextOverflow(_ error: Error) -> Bool {
    if case LanguageModelSession.GenerationError.exceededContextWindowSize = error { return true }
    return false
  }

  /// Turns FoundationModels errors into what the controller understands.
  static func map(_ error: Error) -> Error {
    if error is CancellationError { return error }
    if let toolError = error as? LanguageModelSession.ToolCallError {
      return map(toolError.underlyingError)
    }
    guard let generation = error as? LanguageModelSession.GenerationError else {
      return AnnotateAgentProviderError.failed(L10n.AnnotateAI.failed)
    }
    switch generation {
    case .guardrailViolation, .refusal:
      return AnnotateAgentProviderError.failed(L10n.AnnotateAI.appleRefused)
    case .unsupportedLanguageOrLocale:
      return AnnotateAgentProviderError.failed(L10n.AnnotateAI.appleUnsupportedLanguage)
    case .assetsUnavailable:
      return AnnotateAgentProviderError.needsSetup(L10n.AnnotateAI.appleUnavailable)
    case .rateLimited, .concurrentRequests:
      return AnnotateAgentProviderError.failed(L10n.AnnotateAI.appleBusy)
    case .exceededContextWindowSize:
      return AnnotateAgentProviderError.failed(L10n.AnnotateAI.appleTooLong)
    default:
      return AnnotateAgentProviderError.failed(L10n.AnnotateAI.failed)
    }
  }

  // MARK: - Tools

  static func tools(session: AnnotateAgentSession, counter: AnnotateAgentChangeCounter) -> [any Tool] {
    let bridge = AppleToolBridge(session: session, counter: counter)
    return [
      AppleDrawTool(bridge: bridge),
      AppleBlurSensitiveTool(bridge: bridge),
      AppleEditTool(bridge: bridge),
      AppleCanvasTool(bridge: bridge),
      AppleFindTextTool(bridge: bridge),
    ]
  }
}

/// Counts successful canvas changes across retries (a retry must not redraw).
nonisolated final class AnnotateAgentChangeCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int {
    lock.lock(); defer { lock.unlock() }
    return count
  }

  func increment() {
    lock.lock(); count += 1; lock.unlock()
  }
}

// MARK: - Tool bridge

/// Turns coarse Apple tool calls into toolbox calls. Errors stay text so the model can fix them.
@available(macOS 26.0, *)
nonisolated struct AppleToolBridge: Sendable {
  let session: AnnotateAgentSession
  let counter: AnnotateAgentChangeCounter

  func call(_ tool: AnnotateAgentToolName, _ arguments: [String: Any]) async throws -> AnnotateAgentToolResult {
    let json = Self.json(arguments)
    let result = try await session.callTool(tool.rawValue, arguments: json)
    if !result.isError, !tool.isReadOnly, tool != .select {
      counter.increment()
    }
    return result
  }

  /// Annotation ids from the live scene, for "all".
  func allAnnotationIDs() async throws -> [String] {
    let scene = try await call(.getScene, [:])
    guard let object = (try? JSONSerialization.jsonObject(with: Data(scene.text.utf8))) as? [String: Any] else {
      return []
    }
    return (object["annotations"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
  }

  static func json(_ object: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
    return String(decoding: data, as: UTF8.self)
  }

  /// Model output for optional strings is sometimes "" or "none".
  static func value(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    switch trimmed.lowercased() {
    case "", "none", "null", "nil", "default": return nil
    default: return trimmed
    }
  }

  static func joined(_ results: [AnnotateAgentToolResult]) -> String {
    results.count == 1 ? results[0].text : "[" + results.map(\.text).joined(separator: ",") + "]"
  }
}

@available(macOS 26.0, *)
nonisolated struct AppleDrawTool: Tool {
  let bridge: AppleToolBridge

  let name = "draw"
  let description = """
  Add one annotation. Kinds: box or oval = outline around the target; arrow = points at it; \
  text = a note next to it; highlight = yellow marker over text; blur = hide it; \
  spotlight = dim everything else; counter = numbered step badge (1, 2, 3…), one call per step; \
  watermark = text across the image.
  """

  @Generable
  struct Arguments {
    @Guide(description: "What to draw", .anyOf(["box", "oval", "arrow", "text", "highlight", "blur", "spotlight", "counter", "watermark"]))
    var kind: String
    @Guide(description: "Scene id (t3, e2, a5) or exact visible text it is about")
    var target: String
    @Guide(description: "Color name like red, yellow, green, blue, or empty")
    var color: String?
    @Guide(description: "Words to write, only for text and watermark")
    var text: String?
  }

  func call(arguments: Arguments) async throws -> String {
    let target = arguments.target.trimmingCharacters(in: .whitespacesAndNewlines)
    let color = AppleToolBridge.value(arguments.color)
    let text = AppleToolBridge.value(arguments.text)
    var payload: [String: Any] = ["target": target]
    if let color { payload["color"] = color }

    let tool: AnnotateAgentToolName
    switch arguments.kind.lowercased() {
    case "box", "rectangle": tool = .addBox
    case "oval", "circle", "ellipse": tool = .addOval
    case "arrow":
      tool = .addArrow
      payload = ["to": target]
      if let color { payload["color"] = color }
    case "text", "note", "callout", "label":
      tool = .addText
      guard let text else { return #"{"ok":false,"error":"kind text needs the words in 'text'."}"# }
      payload["text"] = text
      if target.isEmpty { payload["target"] = nil }
    case "highlight": tool = .addHighlight
    case "blur", "redact", "hide":
      tool = .addBlur
      payload = ["target": target]
    case "spotlight", "focus":
      tool = .addSpotlight
      payload = ["target": target]
    case "counter", "number", "step": tool = .addCounter
    case "watermark":
      tool = .addWatermark
      payload = ["text": text ?? target]
    default:
      return #"{"ok":false,"error":"Unknown kind. Use box, oval, arrow, text, highlight, blur, spotlight, counter or watermark."}"#
    }
    return try await bridge.call(tool, payload).text
  }
}

@available(macOS 26.0, *)
nonisolated struct AppleEditTool: Tool {
  let bridge: AppleToolBridge

  let name = "edit"
  let description = "Change or remove existing annotations (a#)."

  @Generable
  struct Arguments {
    @Guide(description: "Annotation ids like a1, or all")
    var ids: [String]
    @Guide(description: "What to do", .anyOf(["recolor", "delete", "set_text", "bring_to_front", "send_to_back"]))
    var action: String
    @Guide(description: "New color for recolor, new words for set_text")
    var value: String?
  }

  func call(arguments: Arguments) async throws -> String {
    var ids = arguments.ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    let wantsAll = ids.contains { $0.lowercased() == "all" }
    let value = AppleToolBridge.value(arguments.value)

    switch arguments.action.lowercased() {
    case "delete", "remove":
      return try await bridge.call(.deleteAnnotations, ["ids": wantsAll ? ["all"] : ids]).text
    case "bring_to_front", "front", "send_to_back", "back":
      if wantsAll { ids = try await bridge.allAnnotationIDs() }
      let order = arguments.action.lowercased().contains("front") ? "front" : "back"
      return try await bridge.call(.arrange, ["ids": ids, "order": order]).text
    case "recolor", "color", "set_text", "text":
      let isColor = arguments.action.lowercased().contains("color")
      guard let value else {
        return #"{"ok":false,"error":"Put the new color or text in 'value'."}"#
      }
      if wantsAll { ids = try await bridge.allAnnotationIDs() }
      guard !ids.isEmpty else { return #"{"ok":false,"error":"There are no annotations to change."}"# }
      var results: [AnnotateAgentToolResult] = []
      for id in ids.prefix(30) {
        results.append(try await bridge.call(.updateAnnotation, ["id": id, isColor ? "color" : "text": value]))
      }
      return AppleToolBridge.joined(results)
    default:
      return #"{"ok":false,"error":"Unknown action. Use recolor, delete, set_text, bring_to_front or send_to_back."}"#
    }
  }
}

@available(macOS 26.0, *)
nonisolated struct AppleCanvasTool: Tool {
  let bridge: AppleToolBridge

  let name = "canvas"
  let description = "Style the area around the screenshot. Only set what the user asked for."

  @Generable
  struct Arguments {
    @Guide(description: "none, a gradient (\(GradientPreset.allCases.map(\.rawValue).joined(separator: ", "))) or a color name")
    var background: String?
    @Guide(description: "Space around the image, 0 to 100", .range(0 ... 100))
    var padding: Int?
    @Guide(description: "Rounded image corners, 0 to 32", .range(0 ... 32))
    var cornerRadius: Int?
    @Guide(description: "Shadow strength, 0 to 1", .range(0 ... 1))
    var shadow: Double?
  }

  func call(arguments: Arguments) async throws -> String {
    var payload: [String: Any] = [:]
    if let background = AppleToolBridge.value(arguments.background) ?? (arguments.background?.lowercased() == "none" ? "none" : nil) {
      payload["background"] = background
    }
    if let padding = arguments.padding { payload["padding"] = padding }
    if let radius = arguments.cornerRadius { payload["corner_radius"] = radius }
    if let shadow = arguments.shadow { payload["shadow"] = shadow }
    guard !payload.isEmpty else { return #"{"ok":false,"error":"Set at least one of background, padding, cornerRadius, shadow."}"# }
    return try await bridge.call(.setCanvas, payload).text
  }
}

/// Blurs every text block that looks like personal data. Small models miss items when
/// asked to "blur all emails and phone numbers"; pattern matching does not.
@available(macOS 26.0, *)
nonisolated struct AppleBlurSensitiveTool: Tool {
  let bridge: AppleToolBridge

  let name = "blur_sensitive"
  let description = "Blur all personal data in the image at once: emails, phone numbers, links, card numbers, IP addresses."

  @Generable
  struct Arguments {
    @Guide(description: "Which kinds to hide; empty means all", .element(.anyOf(["email", "phone", "link", "card", "ip", "all"])))
    var kinds: [String]
  }

  func call(arguments: Arguments) async throws -> String {
    let wanted = Set(arguments.kinds.map { $0.lowercased() })
    let kinds = wanted.isEmpty || wanted.contains("all")
      ? AnnotateAgentSensitiveText.Kind.allCases
      : AnnotateAgentSensitiveText.Kind.allCases.filter { wanted.contains($0.rawValue) }
    let scene = try await bridge.call(.getScene, [:])
    guard let object = (try? JSONSerialization.jsonObject(with: Data(scene.text.utf8))) as? [String: Any] else {
      return #"{"ok":false,"error":"No image is open."}"#
    }
    let ids = (object["texts"] as? [[String: Any]] ?? []).compactMap { entry -> String? in
      guard let id = entry["id"] as? String, let text = entry["text"] as? String else { return nil }
      return AnnotateAgentSensitiveText.kinds(in: text).contains(where: kinds.contains) ? id : nil
    }
    guard !ids.isEmpty else { return #"{"ok":true,"blurred":0,"note":"No personal data found."}"# }
    var results: [AnnotateAgentToolResult] = []
    for id in ids.prefix(30) {
      results.append(try await bridge.call(.addBlur, ["target": id]))
    }
    return AppleToolBridge.joined(results)
  }
}

@available(macOS 26.0, *)
nonisolated struct AppleFindTextTool: Tool {
  let bridge: AppleToolBridge

  let name = "find_text"
  let description = "Find text blocks not listed in the scene. Returns ids to use as targets."

  @Generable
  struct Arguments {
    @Guide(description: "Text to look for")
    var query: String
  }

  func call(arguments: Arguments) async throws -> String {
    try await bridge.call(.findText, ["query": arguments.query]).text
  }
}

#endif

/// Pattern detection for `blur_sensitive` (any macOS version, testable without a model).
nonisolated enum AnnotateAgentSensitiveText {
  enum Kind: String, CaseIterable {
    case email, phone, link, card, ip
  }

  private static let patterns: [(Kind, NSRegularExpression)] = [
    (Kind.email, #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#),
    (Kind.link, #"(https?://|www\.)\S+"#),
    (Kind.ip, #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#),
    (Kind.card, #"\b(?:\d[ \-]?){13,19}\b"#),
    (Kind.phone, #"(?:\+\d{1,3}[ .\-]?)?(?:\(\d{2,4}\)[ .\-]?)?\d{2,4}[ .\-]\d{3,4}(?:[ .\-]\d{3,4})?"#),
  ].compactMap { kind, pattern in
    (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])).map { (kind, $0) }
  }

  static func kinds(in text: String) -> Set<Kind> {
    let range = NSRange(text.startIndex..., in: text)
    var found = Set<Kind>()
    for (kind, regex) in patterns where regex.firstMatch(in: text, range: range) != nil {
      found.insert(kind)
    }
    // An IP address or card number is not also a phone number.
    if found.contains(.ip) || found.contains(.card) { found.remove(.phone) }
    return found
  }
}
