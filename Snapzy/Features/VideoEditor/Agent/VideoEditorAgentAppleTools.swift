//
//  VideoEditorAgentAppleTools.swift
//  Snapzy
//
//  Video Editor AI prompt answered by the on-device Apple Intelligence model
//  (FoundationModels, macOS 26). Its 4K-token context holds instructions, tool
//  schemas, scene, transcript and answer, so it gets a short text scene and five
//  coarse tools (cut / zoom / speed / style / auto) that map onto the shared
//  `VideoEditorAgentToolbox` instead of the full 19-tool catalog.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Availability lives with Annotate (`AnnotateAgentAppleIntelligence`); this adds the video provider.
@MainActor
enum VideoEditorAgentAppleIntelligence {
  static var isAvailable: Bool { AnnotateAgentAppleIntelligence.isAvailable }

  /// Loads model assets ahead of the first prompt. Cheap to call repeatedly.
  static func prewarm() {
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *), isAvailable, Date().timeIntervalSince(lastPrewarm) > 60 {
      lastPrewarm = Date()
      LanguageModelSession(
        model: .default,
        instructions: VideoEditorAgentAppleIntelligenceProvider.instructions
      ).prewarm()
    }
    #endif
  }

  private static var lastPrewarm = Date.distantPast

  static func makeProviderIfAvailable() -> AgentProvider? {
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *), isAvailable {
      return VideoEditorAgentAppleIntelligenceProvider()
    }
    #endif
    return nil
  }
}

// MARK: - Compact scene

extension VideoEditorAgentScene {
  /// A few short lines instead of JSON, for the on-device model's 4K context. Lists keep
  /// their first `maximumItems` entries and say how many were left out.
  func compactDescription(maximumItems: Int) -> String {
    func list<T>(_ title: String, _ items: [T], _ line: (T) -> String) -> String? {
      guard !items.isEmpty else { return nil }
      var text = "\(title): " + items.prefix(maximumItems).map(line).joined(separator: "; ")
      if items.count > maximumItems { text += "; +\(items.count - maximumItems) more" }
      return text
    }
    let s = Self.seconds
    var lines = [
      "Video: \(s(duration))s long, exports \(s(outputDuration))s, playhead at \(s(playhead))s."
        + " Audio: \(audio.tracks.isEmpty ? "none" : (audio.muted ? "muted" : "on"))."
        + " Recorded cursor: \(hasMouseData ? "yes" : "no").",
    ]
    lines += [
      list("Clips", clips) { clip in
        var text = "\(clip.id) \(s(clip.start))–\(s(clip.end))"
        if clip.playsFrom > clip.start + 0.01 || clip.playsTo < clip.end - 0.01 {
          text += " (plays \(s(clip.playsFrom))–\(s(clip.playsTo)))"
        }
        return text
      },
      list("Zooms", zooms) { zoom in
        "\(zoom.id) \(s(zoom.start))–\(s(zoom.end)) \(s(zoom.level))x\(zoom.followMouse ? " follows mouse" : "")\(zoom.enabled ? "" : " off")"
      },
      list("Speeds", speeds) { speed in
        "\(speed.id) \(s(speed.start))–\(s(speed.end)) \(s(speed.rate))x\(speed.enabled ? "" : " off")"
      },
    ].compactMap { $0 }
    lines.append(
      "Frame: background \(background.style), padding \(background.padding), corners \(background.cornerRadius), shadow \(s(background.shadow))."
    )
    return lines.joined(separator: "\n")
  }

  /// 12, 12.5, 12.25 — no trailing zeros.
  private static func seconds(_ value: Double) -> String {
    let rounded = (value * 100).rounded() / 100
    if rounded == rounded.rounded() { return String(Int(rounded)) }
    return String(format: "%g", rounded)
  }
}

// MARK: - Argument helpers (any macOS, testable without a model)

nonisolated enum VideoEditorAgentAppleArguments {
  /// Model output for optional strings is sometimes "" or "none".
  static func value(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    switch trimmed.lowercased() {
    case "", "none", "null", "nil", "default": return nil
    default: return trimmed
    }
  }

  /// Seconds when the text reads as a time ("12", "1:05", "12s", "12 seconds"), else the
  /// text itself so the toolbox can say what is wrong.
  static func time(_ raw: String?) -> Any? {
    guard let text = value(raw) else { return nil }
    let cleaned = text
      .replacingOccurrences(of: "seconds", with: "")
      .replacingOccurrences(of: "second", with: "")
      .replacingOccurrences(of: "sec", with: "")
      .trimmingCharacters(in: .whitespaces)
    return VideoEditorAgentTime.parse(cleaned) ?? text
  }

  /// Fixed zoom centers by name, [x, y] 0…1 from the top left.
  static func center(_ raw: String?) -> [Double]? {
    guard let name = value(raw)?.lowercased().replacingOccurrences(of: "-", with: " ") else { return nil }
    let vertical: Double = name.contains("top") ? 0.25 : (name.contains("bottom") ? 0.75 : 0.5)
    let horizontal: Double = name.contains("left") ? 0.25 : (name.contains("right") ? 0.75 : 0.5)
    switch name {
    case "center", "middle", "top", "bottom", "left", "right",
         "top left", "top right", "bottom left", "bottom right":
      return [horizontal, vertical]
    default:
      return nil
    }
  }

  /// Ids the model listed, "all" kept as is; blanks dropped.
  static func ids(_ raw: [String]?) -> [String] {
    (raw ?? []).compactMap { value($0) }
  }

  static func json(_ object: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
    return String(decoding: data, as: UTF8.self)
  }

  static func joined(_ results: [AgentToolResult]) -> String {
    results.count == 1 ? results[0].text : "[" + results.map(\.text).joined(separator: ",") + "]"
  }

  /// `get_activity` cut to the longest spans, without areas, so the answer fits the context.
  static func compactActivity(_ text: String, maximumSpans: Int) -> String {
    guard var object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
          let spans = object["spans"] as? [[String: Any]]
    else { return text }
    func length(_ span: [String: Any]) -> Double {
      ((span["end"] as? Double) ?? 0) - ((span["start"] as? Double) ?? 0)
    }
    var kept = spans
    if spans.count > maximumSpans {
      kept = Array(spans.sorted { length($0) > length($1) }.prefix(maximumSpans))
      object["omitted_short_spans"] = ((object["omitted_short_spans"] as? Int) ?? 0) + spans.count - maximumSpans
    }
    object["spans"] = kept
      .sorted { (($0["start"] as? Double) ?? 0) < (($1["start"] as? Double) ?? 0) }
      .map { span in span.filter { $0.key != "area" } }
    return json(object)
  }
}

#if canImport(FoundationModels)

@available(macOS 26.0, *)
@MainActor
final class VideoEditorAgentAppleIntelligenceProvider: AgentProvider {
  let displayName = "Apple Intelligence"
  let symbolName = "apple.intelligence"

  /// Clips, zooms and speeds listed per kind: first try, then the retry after `exceededContextWindowSize`.
  static let sceneBudgets = [24, 8]
  /// Earlier turns sent along as a reminder (each one line).
  static let historyLimit = 3

  static let instructions = """
  You edit a screen recording in Snapzy's video editor by calling tools. Do what the user asks right away; never ask questions.
  Times are seconds on the timeline (12.5) or m:ss (1:05). The scene lists clips (c1…), zooms (z1…) and speed blocks (s1…).
  cut removes footage. To delete zooms or speed blocks use zoom or speed with action remove; that never cuts the video.
  Cut first, then add zooms and speeds. Put every part to remove in one cut call.
  For silences, pauses (im lặng), waiting or "zoom where I work", use the auto tool: it finds those parts itself.
  "It"/"that" usually means what you changed in the previous turn. You cannot export, save or share.
  When done, reply with one short sentence in the user's language saying what you changed.
  """

  func run(_ request: AgentRequest, session: AgentSession) async throws -> String {
    session.report(L10n.AnnotateAI.statusThinking)
    var lastError: Error?

    for (index, budget) in Self.sceneBudgets.enumerated() {
      try Task.checkCancellation()
      let model = LanguageModelSession(
        model: .default,
        tools: Self.tools(session: session),
        instructions: Self.instructions
      )
      do {
        let response = try await model.respond(
          to: Self.prompt(for: request, maximumItems: budget),
          options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 300)
        )
        try Task.checkCancellation()
        return AgentReplyFormatter.full(response.content)
      } catch {
        try Task.checkCancellation()
        let mapped = AnnotateAgentAppleIntelligenceProvider.map(error)
        if mapped is CancellationError { throw mapped }
        // Retry with a smaller scene only when nothing changed yet, so nothing is cut twice.
        if AnnotateAgentAppleIntelligenceProvider.isContextOverflow(error) {
          if session.changeCount > 0 { return "" }
          if index < Self.sceneBudgets.count - 1 {
            lastError = mapped
            continue
          }
        }
        throw mapped
      }
    }
    throw lastError ?? AgentProviderError.failed(L10n.AnnotateAI.failed)
  }

  // MARK: Prompt

  static func prompt(for request: AgentRequest, maximumItems: Int) -> String {
    var parts: [String] = []
    let scene = (request.scene as? VideoEditorAgentScene)?.compactDescription(maximumItems: maximumItems)
      ?? request.sceneJSON
    parts.append("Scene:\n\(scene)")
    let history = request.history.suffix(historyLimit)
    if !history.isEmpty {
      let lines = history.map { "- User: \(String($0.prompt.prefix(120))) → You: \(String($0.reply.prefix(120)))" }
      parts.append("Earlier turns:\n" + lines.joined(separator: "\n"))
    }
    parts.append("Request: \(request.prompt)")
    return parts.joined(separator: "\n\n")
  }

  // MARK: Tools

  static func tools(session: AgentSession) -> [any Tool] {
    let bridge = VideoAppleToolBridge(session: session)
    return [
      VideoAppleCutTool(bridge: bridge),
      VideoAppleZoomTool(bridge: bridge),
      VideoAppleSpeedTool(bridge: bridge),
      VideoAppleStyleTool(bridge: bridge),
      VideoAppleAutoTool(bridge: bridge),
    ]
  }
}

// MARK: - Tool bridge

/// Turns coarse Apple tool calls into toolbox calls. Errors stay text so the model can fix them.
@available(macOS 26.0, *)
nonisolated struct VideoAppleToolBridge: Sendable {
  let session: AgentSession

  func call(_ tool: VideoEditorAgentToolName, _ arguments: [String: Any]) async throws -> AgentToolResult {
    try await session.callTool(tool.rawValue, arguments: VideoEditorAgentAppleArguments.json(arguments))
  }

  /// Leaves the playhead where the change is, so the user sees it.
  func show(_ time: Any?) async throws {
    guard let time else { return }
    _ = try await call(.seek, ["time": time])
  }

  /// Zoom (`zooms`) or speed (`speeds`) ids from the live timeline, for "all".
  func allIDs(_ key: String) async throws -> [String] {
    let timeline = try await call(.getTimeline, [:])
    guard let object = (try? JSONSerialization.jsonObject(with: Data(timeline.text.utf8))) as? [String: Any] else {
      return []
    }
    return (object[key] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
  }

  static func error(_ message: String) -> String {
    VideoEditorAgentAppleArguments.json(["ok": false, "error": message])
  }
}

@available(macOS 26.0, *)
nonisolated struct VideoAppleCutTool: Tool {
  let bridge: VideoAppleToolBridge

  let name = "cut"
  let description = """
  Remove footage between two times you know; what follows slides left. List every part in one call. \
  Not for zooms or speed blocks (use zoom/speed remove) and not for silences (use auto).
  """

  @Generable
  struct Part {
    @Guide(description: "Start of the part, seconds or m:ss")
    var start: String
    @Guide(description: "End of the part, seconds or m:ss")
    var end: String
  }

  @Generable
  struct Arguments {
    @Guide(description: "Parts to remove")
    var parts: [Part]
  }

  func call(arguments: Arguments) async throws -> String {
    let parts = arguments.parts.prefix(20).compactMap { part -> (start: Any, end: Any, sort: Double)? in
      guard let start = VideoEditorAgentAppleArguments.time(part.start),
            let end = VideoEditorAgentAppleArguments.time(part.end)
      else { return nil }
      return (start, end, (start as? Double) ?? 0)
    }
    guard !parts.isEmpty else { return VideoAppleToolBridge.error("Give each part a start and an end.") }
    // Latest first, so earlier times stay where the model read them.
    let ordered = parts.sorted { $0.sort > $1.sort }
    var results: [AgentToolResult] = []
    for part in ordered {
      results.append(try await bridge.call(.cutRange, ["start": part.start, "end": part.end]))
    }
    if results.contains(where: { !$0.isError }) {
      try await bridge.show(ordered.last?.start)
    }
    return VideoEditorAgentAppleArguments.joined(results)
  }
}

@available(macOS 26.0, *)
nonisolated struct VideoAppleZoomTool: Tool {
  let bridge: VideoAppleToolBridge

  let name = "zoom"
  let description = "Add, change or remove zoom blocks (z#). Remove every zoom: action remove, ids [all]. "
    + "Zoom on a button or words on screen: action add, text."

  @Generable
  struct Arguments {
    @Guide(description: "What to do", .anyOf(["add", "change", "remove"]))
    var action: String
    @Guide(description: "add: when the zoom starts, seconds or m:ss")
    var start: String?
    @Guide(description: "How long it stays zoomed, in seconds", .range(0.5 ... 30))
    var seconds: Double?
    @Guide(description: "Zoom factor", .range(1 ... 4))
    var level: Double?
    @Guide(description: "Where to zoom", .anyOf(["mouse", "center", "top left", "top", "top right", "left", "right", "bottom left", "bottom", "bottom right"]))
    var place: String?
    @Guide(description: "change or remove: zoom ids like z1, or all")
    var ids: [String]?
    @Guide(description: "add: words shown on screen to zoom on, like a button label; found in the video")
    var text: String?
  }

  func call(arguments: Arguments) async throws -> String {
    let place = VideoEditorAgentAppleArguments.value(arguments.place)?.lowercased()
    var look: [String: Any] = [:]
    if let level = arguments.level { look["level"] = level }
    if let center = VideoEditorAgentAppleArguments.center(place) {
      look["center"] = center
    } else if place == "mouse" || place == "cursor" {
      look["follow_mouse"] = true
    }
    var ids = VideoEditorAgentAppleArguments.ids(arguments.ids)
    if ids.contains(where: { $0.lowercased() == "all" }) {
      ids = try await bridge.allIDs("zooms")
    }

    switch arguments.action.lowercased() {
    case "add":
      if let text = VideoEditorAgentAppleArguments.value(arguments.text) {
        // The toolbox finds the words and zooms on them; place and mouse don't apply.
        var payload: [String: Any] = ["text": text]
        if let level = arguments.level { payload["level"] = level }
        if let start = VideoEditorAgentAppleArguments.time(arguments.start) { payload["start"] = start }
        if let seconds = arguments.seconds { payload["duration"] = seconds }
        let result = try await bridge.call(.addZoom, payload)
        if !result.isError,
           let object = try? JSONSerialization.jsonObject(with: Data(result.text.utf8)) as? [String: Any],
           let start = object["start"] as? Double {
          try await bridge.show(start)
        }
        return result.text
      }
      guard let start = VideoEditorAgentAppleArguments.time(arguments.start) else {
        return VideoAppleToolBridge.error("add needs start.")
      }
      var payload = look
      payload["start"] = start
      if let seconds = arguments.seconds { payload["duration"] = seconds }
      let result = try await bridge.call(.addZoom, payload)
      if !result.isError { try await bridge.show(start) }
      return result.text
    case "change", "update", "edit":
      guard !ids.isEmpty else { return VideoAppleToolBridge.error("change needs ids, like [\"z1\"] or [\"all\"].") }
      var payload = look
      if let start = VideoEditorAgentAppleArguments.time(arguments.start) { payload["start"] = start }
      if let seconds = arguments.seconds { payload["duration"] = seconds }
      guard !payload.isEmpty else { return VideoAppleToolBridge.error("Say what to change: start, seconds, level or place.") }
      var results: [AgentToolResult] = []
      for id in ids.prefix(30) {
        payload["id"] = id
        results.append(try await bridge.call(.updateZoom, payload))
      }
      return VideoEditorAgentAppleArguments.joined(results)
    case "remove", "delete":
      guard !ids.isEmpty else { return VideoAppleToolBridge.error("There are no zooms to remove.") }
      return try await bridge.call(.removeZoom, ["ids": ids]).text
    default:
      return VideoAppleToolBridge.error("Unknown action. Use add, change or remove.")
    }
  }
}

@available(macOS 26.0, *)
nonisolated struct VideoAppleSpeedTool: Tool {
  let bridge: VideoAppleToolBridge

  let name = "speed"
  let description = "Play a part faster or slower, or change or remove speed blocks (s#). Remove every block: action remove, ids [all]. Blocks cannot overlap."

  @Generable
  struct Arguments {
    @Guide(description: "What to do", .anyOf(["add", "change", "remove"]))
    var action: String
    @Guide(description: "Start of the part, seconds or m:ss")
    var start: String?
    @Guide(description: "End of the part, seconds or m:ss")
    var end: String?
    @Guide(description: "4 = four times faster, 0.5 = half speed", .range(0.25 ... 8))
    var rate: Double?
    @Guide(description: "change or remove: speed ids like s1, or all")
    var ids: [String]?
  }

  func call(arguments: Arguments) async throws -> String {
    let start = VideoEditorAgentAppleArguments.time(arguments.start)
    let end = VideoEditorAgentAppleArguments.time(arguments.end)
    var ids = VideoEditorAgentAppleArguments.ids(arguments.ids)
    if ids.contains(where: { $0.lowercased() == "all" }) {
      ids = try await bridge.allIDs("speeds")
    }

    switch arguments.action.lowercased() {
    case "add":
      guard let start, let end else { return VideoAppleToolBridge.error("add needs start and end.") }
      let result = try await bridge.call(.addSpeed, ["start": start, "end": end, "rate": arguments.rate ?? 2])
      if !result.isError { try await bridge.show(start) }
      return result.text
    case "change", "update", "edit":
      guard !ids.isEmpty else { return VideoAppleToolBridge.error("change needs ids, like [\"s1\"] or [\"all\"].") }
      var payload: [String: Any] = [:]
      if let start { payload["start"] = start }
      if let end { payload["end"] = end }
      if let rate = arguments.rate { payload["rate"] = rate }
      guard !payload.isEmpty else { return VideoAppleToolBridge.error("Say what to change: start, end or rate.") }
      var results: [AgentToolResult] = []
      for id in ids.prefix(30) {
        payload["id"] = id
        results.append(try await bridge.call(.updateSpeed, payload))
      }
      return VideoEditorAgentAppleArguments.joined(results)
    case "remove", "delete":
      guard !ids.isEmpty else { return VideoAppleToolBridge.error("There are no speed blocks to remove.") }
      return try await bridge.call(.removeSpeed, ["ids": ids]).text
    default:
      return VideoAppleToolBridge.error("Unknown action. Use add, change or remove.")
    }
  }
}

@available(macOS 26.0, *)
nonisolated struct VideoAppleStyleTool: Tool {
  let bridge: VideoAppleToolBridge

  let name = "style"
  let description = "Frame the video (background, padding, corners, shadow, shape) or change its sound. Only set what the user asked for."

  @Generable
  struct Arguments {
    @Guide(description: "none, a gradient (\(GradientPreset.allCases.map(\.rawValue).joined(separator: ", "))) or a color name")
    var background: String?
    @Guide(description: "Space around the video", .range(0 ... 200))
    var padding: Int?
    @Guide(description: "Rounded corners", .range(0 ... 60))
    var cornerRadius: Int?
    @Guide(description: "Shadow strength", .range(0 ... 1))
    var shadow: Double?
    @Guide(description: "Canvas shape", .anyOf(["original", "1:1", "4:3", "16:9"]))
    var shape: String?
    @Guide(description: "true removes all sound, false brings it back")
    var muted: Bool?
    @Guide(description: "Volume percent, 100 = original", .range(0 ... 200))
    var volume: Int?
  }

  func call(arguments: Arguments) async throws -> String {
    var frame: [String: Any] = [:]
    if let raw = arguments.background?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
      // "a gradient" without a name: the first preset, as the editor's own picker starts there.
      frame["style"] = raw.lowercased() == "gradient" ? GradientPreset.allCases[0].rawValue : raw
    }
    if let padding = arguments.padding { frame["padding"] = padding }
    if let radius = arguments.cornerRadius { frame["corner_radius"] = radius }
    if let shadow = arguments.shadow { frame["shadow"] = shadow }
    if let shape = VideoEditorAgentAppleArguments.value(arguments.shape) { frame["aspect_ratio"] = shape }
    var sound: [String: Any] = [:]
    if let muted = arguments.muted { sound["muted"] = muted }
    if let volume = arguments.volume { sound["volume"] = volume }
    guard !frame.isEmpty || !sound.isEmpty else {
      return VideoAppleToolBridge.error("Set at least one of background, padding, cornerRadius, shadow, shape, muted, volume.")
    }
    var results: [AgentToolResult] = []
    if !frame.isEmpty { results.append(try await bridge.call(.setBackground, frame)) }
    if !sound.isEmpty { results.append(try await bridge.call(.setAudio, sound)) }
    return VideoEditorAgentAppleArguments.joined(results)
  }
}

/// The one-step tools: the app finds silences, idle stretches and busy cursor areas itself.
@available(macOS 26.0, *)
nonisolated struct VideoAppleAutoTool: Tool {
  let bridge: VideoAppleToolBridge

  static let maximumActivitySpans = 16

  let name = "auto"
  let description = """
  Edits worked out from the recording: remove_silences cuts pauses in the audio; \
  speed_up_idle speeds up waiting (cursor still, nobody talking); zoom_on_activity zooms where the cursor works; \
  list_activity tells when the user talks, waits or moves the cursor, changing nothing.
  """

  @Generable
  struct Arguments {
    @Guide(description: "What to do", .anyOf(["remove_silences", "speed_up_idle", "zoom_on_activity", "list_activity"]))
    var action: String
    @Guide(description: "speed_up_idle: how much faster; zoom_on_activity: zoom factor", .range(1 ... 8))
    var amount: Double?
    @Guide(description: "Only parts at least this many seconds long", .range(0.3 ... 60))
    var minimumSeconds: Double?
  }

  func call(arguments: Arguments) async throws -> String {
    var payload: [String: Any] = [:]
    if let minimum = arguments.minimumSeconds { payload["min_duration"] = minimum }

    switch arguments.action.lowercased() {
    case "remove_silences", "silences", "remove_silence":
      return try await bridge.call(.removeSilences, payload).text
    case "speed_up_idle", "idle":
      if let amount = arguments.amount { payload["rate"] = amount }
      return try await bridge.call(.speedUpIdle, payload).text
    case "zoom_on_activity", "zoom_activity", "auto_zoom":
      if let amount = arguments.amount { payload["level"] = min(amount, 4) }
      payload["min_duration"] = nil
      return try await bridge.call(.autoZoomActivity, payload).text
    case "list_activity", "activity":
      let result = try await bridge.call(.getActivity, [:])
      return result.isError
        ? result.text
        : VideoEditorAgentAppleArguments.compactActivity(result.text, maximumSpans: Self.maximumActivitySpans)
    default:
      return VideoAppleToolBridge.error("Unknown action. Use remove_silences, speed_up_idle, zoom_on_activity or list_activity.")
    }
  }
}

#endif
