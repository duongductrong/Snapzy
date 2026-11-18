//
//  VideoEditorAgentMockProvider.swift
//  Snapzy
//
//  Provider choice for the Video Editor, and a debug-only stand-in for a real model
//  so the dock, pacing, status line and undo can be exercised without an endpoint or
//  a CLI. The mock splits the prompt into clauses ("speed 4x from 0:10 to 0:30, zoom
//  2x at 0:05") and maps keywords (English and Vietnamese) to tool calls.
//

import Foundation

// MARK: - Provider choice

/// The shared provider choice (Settings › AI), with Apple Intelligence's coarse video
/// tools (`VideoEditorAgentAppleTools.swift`) as the on-device provider.
@MainActor
enum VideoEditorAgentProviderResolver {
  static func resolve(
    defaults: UserDefaults = .standard,
    endpoints: [CustomOCRModel]? = nil
  ) -> AgentProvider? {
    AgentProviderResolver.resolve(
      defaults: defaults,
      endpoints: endpoints,
      onDevice: { VideoEditorAgentAppleIntelligence.makeProviderIfAvailable() },
      mock: {
        #if DEBUG
        VideoEditorAgentMockProvider()
        #else
        nil
        #endif
      }
    )
  }

  /// The AI orb shows only when a provider could answer on this Mac.
  static var isFeatureAvailable: Bool {
    #if DEBUG
    return true
    #else
    return VideoEditorAgentAppleIntelligence.isAvailable || AgentProviderResolver.hasOffDeviceProvider
    #endif
  }
}

// MARK: - Mock

#if DEBUG
@MainActor
final class VideoEditorAgentMockProvider: AgentProvider {
  let displayName = "Mock agent"
  let symbolName = "hammer"

  /// Pretend thinking time before the first change.
  var thinkingDelay: TimeInterval = 0.7

  func run(_ request: AgentRequest, session: AgentSession) async throws -> String {
    session.report("Thinking…")
    try await Task.sleep(nanoseconds: UInt64(thinkingDelay * 1_000_000_000))

    var changes = 0
    var lastTime: Double?
    for call in Self.plan(for: request.prompt) {
      let result = try await session.callTool(call.name, arguments: call.arguments)
      if !result.isError {
        changes += 1
        lastTime = call.time ?? lastTime
      }
    }
    if let lastTime {
      _ = try await session.callTool(VideoEditorAgentToolName.seek.rawValue, arguments: Self.json(["time": lastTime]))
    }
    return changes == 0 ? "Nothing to change." : "Mock agent made \(changes) change\(changes == 1 ? "" : "s")."
  }

  // MARK: Planning

  struct Call: Equatable {
    let name: String
    let arguments: String
    /// Where the change happens, so the run can leave the playhead there.
    var time: Double? = nil
  }

  static func plan(for prompt: String) -> [Call] {
    let clauses = prompt
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      .replacingOccurrences(of: "đ", with: "d")
      .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
      .flatMap { $0.components(separatedBy: " and ") }
      .flatMap { $0.components(separatedBy: " va ") }
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }

    var calls: [Call] = []
    var cuts: [Call] = []
    for clause in clauses {
      var text = clause
      func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
      let rate = take(#"(\d+(?:\.\d+)?)\s*x\b"#, from: &text)
      let padding = take(#"padding\s*(\d+(?:\.\d+)?)"#, from: &text)
      let times = Self.times(in: text)

      let hide = has("hide", "an ", "tat ") || text.hasPrefix("an")
      if has("cursor", "con tro") {
        // "hide the cursor", "cursor 1.5x" / "phong to cursor 1.5x".
        var args: [String: Any] = [:]
        if let rate { args["scale"] = rate } else { args["visible"] = !hide }
        calls.append(Call(name: "set_cursor", arguments: json(args)))
      } else if has("camera", "webcam") {
        calls.append(Call(name: "set_camera", arguments: json(["visible": !hide])))
      } else if has("caption", "subtitle", "phu de") {
        if hide {
          calls.append(Call(name: "edit_caption", arguments: json(["show_on_video": false])))
        } else {
          let language = has("tieng viet", "vietnamese") ? "vi-VN" : (has("english", "tieng anh") ? "en-US" : nil)
          calls.append(Call(name: "generate_captions", arguments: language.map { json(["language": $0]) } ?? "{}"))
        }
      } else if has("silence", "im lang", "pause", "khoang lang"), !has("mute", "tat tieng") {
        calls.append(Call(name: "remove_silences", arguments: "{}"))
      } else if has("idle", "waiting", "cho doi", "dung yen") {
        calls.append(Call(name: "speed_up_idle", arguments: rate.map { json(["rate": $0]) } ?? "{}"))
      } else if has("zoom", "phong"), has("activity", "hoat dong", "auto", "tu dong"), times.isEmpty {
        calls.append(Call(name: "auto_zoom_activity", arguments: rate.map { json(["level": $0]) } ?? "{}"))
      } else if has("zoom", "phong"), let words = quoted(in: text) {
        // "zoom on "Deploy"": the toolbox finds the words on screen.
        var args: [String: Any] = ["text": words]
        if let start = times.first { args["start"] = start }
        if let rate { args["level"] = rate }
        calls.append(Call(name: "add_zoom", arguments: json(args)))
      } else if has("cut", "cat", "remove", "xoa", "bo "), times.count >= 2 {
        // Latest cut first, so earlier times stay valid.
        cuts.append(Call(name: "cut_range", arguments: json(["start": times[0], "end": times[1]]), time: times[0]))
      } else if has("zoom", "phong"), let start = times.first {
        var args: [String: Any] = ["start": start]
        if times.count >= 2, times[1] > start { args["duration"] = times[1] - start }
        if let rate { args["level"] = rate }
        calls.append(Call(name: "add_zoom", arguments: json(args), time: start))
      } else if has("speed", "tua", "nhanh", "slow", "cham", "fast"), times.count >= 2 {
        let fallback = has("slow", "cham") ? 0.5 : 2.0
        calls.append(Call(
          name: "add_speed",
          arguments: json(["start": times[0], "end": times[1], "rate": rate ?? fallback]),
          time: times[0]
        ))
      } else if has("split", "tach"), let at = times.first {
        calls.append(Call(name: "split", arguments: json(["time": at]), time: at))
      } else if has("background", "gradient", "nen", "padding") {
        var args: [String: Any] = ["style": "bluePurple", "corner_radius": 12, "shadow": 0.5]
        args["padding"] = padding ?? 40
        calls.append(Call(name: "set_background", arguments: json(args)))
      } else if has("unmute", "bat tieng") {
        calls.append(Call(name: "set_audio", arguments: json(["muted": false])))
      } else if has("mute", "tat tieng") {
        calls.append(Call(name: "set_audio", arguments: json(["muted": true])))
      }
    }
    let orderedCuts = cuts.sorted { ($0.time ?? 0) > ($1.time ?? 0) }
    return orderedCuts + calls
  }

  /// Text inside quotes ("…", “…”, '…'), so times written inside it aren't read as times.
  static func quoted(in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: #"["“'‘]([^"”'’]+)["”'’]"#),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text) else { return nil }
    let words = text[range].trimmingCharacters(in: .whitespaces)
    return words.isEmpty ? nil : words
  }

  /// Times in a clause: "1:05.5", "0:10", "12s", "12". Rates and paddings are taken out first.
  static func times(in text: String) -> [Double] {
    let pattern = #"(\d+:\d{1,2}(?:\.\d+)?|\d+(?:\.\d+)?)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).compactMap { match in
      Range(match.range(at: 1), in: text).flatMap { VideoEditorAgentTime.parse(String(text[$0])) }
    }
  }

  /// First capture of `pattern` as a number, removed from `text`.
  private static func take(_ pattern: String, from text: inout String) -> Double? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let whole = Range(match.range, in: text),
          let value = Range(match.range(at: 1), in: text).flatMap({ Double(text[$0]) })
    else { return nil }
    text.replaceSubrange(whole, with: " ")
    return value
  }

  private static func json(_ object: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
    return String(decoding: data, as: UTF8.self)
  }
}
#endif
