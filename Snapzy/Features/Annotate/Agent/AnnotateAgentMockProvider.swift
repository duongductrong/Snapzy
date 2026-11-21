//
//  AnnotateAgentMockProvider.swift
//  Snapzy
//
//  Debug-only stand-in for a real model, so the prompt UI, pacing, overlay and undo
//  can be exercised without Apple Intelligence, an endpoint or a CLI. It reads the
//  scene like a real agent would and maps a few keywords (English and Vietnamese)
//  to tool calls. Quoted text in the prompt picks the target.
//

#if DEBUG
import Foundation

@MainActor
final class AnnotateAgentMockProvider: AnnotateAgentProvider {
  let displayName = "Mock agent"
  let symbolName = "hammer"

  /// Pretend thinking time before the first change.
  var thinkingDelay: TimeInterval = 0.7

  func run(_ request: AnnotateAgentRequest, session: AnnotateAgentSession) async throws -> String {
    session.report("Thinking…")
    try await Task.sleep(nanoseconds: UInt64(thinkingDelay * 1_000_000_000))

    let scene = Self.parseScene(try await session.callTool("get_scene", arguments: "{}").text)
    let calls = Self.plan(for: request.prompt, texts: scene.texts, annotationIDs: scene.annotationIDs)
    var changes = 0
    for call in calls {
      let result = try await session.callTool(call.name, arguments: call.arguments)
      if !result.isError { changes += 1 }
    }
    return changes == 0 ? "Nothing to change." : "Mock agent made \(changes) change\(changes == 1 ? "" : "s")."
  }

  // MARK: - Planning

  struct Call: Equatable {
    let name: String
    let arguments: String
  }

  struct SceneText: Equatable {
    let id: String
    let text: String
  }

  static func plan(for prompt: String, texts: [SceneText], annotationIDs: [String]) -> [Call] {
    let quoted = quotedPhrases(in: prompt)
    // Keywords come from the instruction, not from the quoted targets ("Email" is not "blur email").
    var instruction = prompt
    for phrase in quoted { instruction = instruction.replacingOccurrences(of: phrase, with: " ") }
    let key = AnnotateAgentTextMatcher.normalized(instruction)
    func has(_ words: String...) -> Bool { words.contains { key.contains($0) } }

    let targets: [String] = quoted.isEmpty
      ? Array(texts.prefix(3).map(\.id))
      : quoted.map { phrase in
        AnnotateAgentTextMatcher.matches(phrase, in: texts.map(\.text)).first.map { texts[$0].id } ?? phrase
      }
    let first = targets.first ?? "t1"
    var calls: [Call] = []

    if has("delete", "remove", "clear", "xoa") {
      return [Call(name: "delete_annotations", arguments: json(["ids": ["all"]]))]
    }
    if has("email", "@", "blur", "che ", "an email", "redact") {
      let sensitive = texts.filter { $0.text.contains("@") }.map(\.id)
      for id in sensitive.isEmpty ? [first] : sensitive {
        calls.append(Call(name: "add_blur", arguments: json(["target": id])))
      }
    }
    if has("number", "step", "buoc", "danh so") {
      for id in targets.prefix(5) {
        calls.append(Call(name: "add_counter", arguments: json(["target": id])))
      }
    }
    if has("highlight", "danh dau", "to vang") {
      calls.append(Call(name: "add_highlight", arguments: json(["target": first])))
    }
    if has("arrow", "mui ten", "chi vao", "point") {
      calls.append(Call(name: "add_arrow", arguments: json(["to": first, "color": "red"])))
    }
    if has("circle", "oval", "tron") {
      calls.append(Call(name: "add_oval", arguments: json(["target": first, "color": "red"])))
    }
    if has("background", "gradient", "nen", "padding") {
      calls.append(Call(name: "set_canvas", arguments: json(["background": "bluePurple", "shadow": 0.5, "corner_radius": 12])))
    }
    if has("blue", "xanh"), !annotationIDs.isEmpty {
      for id in annotationIDs.prefix(6) {
        calls.append(Call(name: "update_annotation", arguments: json(["id": id, "color": "blue"])))
      }
    }
    if calls.isEmpty {
      calls.append(Call(name: "add_box", arguments: json(["target": first, "color": "red"])))
      calls.append(Call(name: "add_text", arguments: json(["text": "Look here", "target": first, "color": "red"])))
    }
    return calls
  }

  static func quotedPhrases(in prompt: String) -> [String] {
    let pattern = #"["“”«»']([^"“”«»']{1,60})["“”«»']"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(prompt.startIndex..., in: prompt)
    return regex.matches(in: prompt, range: range).compactMap { match in
      Range(match.range(at: 1), in: prompt).map { String(prompt[$0]).trimmingCharacters(in: .whitespaces) }
    }.filter { !$0.isEmpty }
  }

  private static func parseScene(_ json: String) -> (texts: [SceneText], annotationIDs: [String]) {
    guard let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else {
      return ([], [])
    }
    let texts = (object["texts"] as? [[String: Any]] ?? []).compactMap { entry -> SceneText? in
      guard let id = entry["id"] as? String, let text = entry["text"] as? String else { return nil }
      return SceneText(id: id, text: text)
    }
    let annotations = (object["annotations"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    return (texts, annotations)
  }

  private static func json(_ object: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
    return String(decoding: data, as: UTF8.self)
  }
}
#endif
