//
//  VideoEditorAgentAppleCaptionsTool.swift
//  Snapzy
//
//  Apple Intelligence compact tool for captions: create from speech, translate, fix a
//  word everywhere, style typography/fonts, show, hide, or clear (with explicit id).
//

import Foundation

#if canImport(FoundationModels)
  import FoundationModels

  @available(macOS 26.0, *)
  nonisolated struct VideoAppleCaptionsTool: Tool {
    let bridge: VideoAppleToolBridge

    let name = "captions"
    let description = """
    Subtitles: add creates them from speech; translate rewrites them in another language; \
    fix replaces a word in all of them; style updates font, bold, italic, or position; \
    show, hide, or clear (requires id like t1 or all).
    """

    @Generable
    struct Arguments {
      @Guide(description: "What to do", .anyOf(["add", "translate", "fix", "style", "show", "hide", "clear"]))
      var action: String
      @Guide(description: "clear/remove: caption id like t1, or all")
      var id: String?
      @Guide(
        description: "add: spoken language like en-US; translate: target language like vi, en, ja; empty when unsure"
      )
      var language: String?
      @Guide(description: "fix: the wrong word or words")
      var find: String?
      @Guide(description: "fix: the right word or words")
      var replace: String?
      @Guide(description: "style: installed local font family or system")
      var font: String?
      @Guide(description: "style: bold subtitles")
      var bold: Bool?
      @Guide(description: "style: italic subtitles")
      var italic: Bool?
      @Guide(description: "style: position", .anyOf(["bottom", "top"]))
      var position: String?
    }

    func call(arguments: Arguments) async throws -> String {
      let language = VideoEditorAgentAppleArguments.value(arguments.language)
      switch arguments.action.lowercased() {
      case "add", "create", "generate":
        var payload: [String: Any] = [:]
        if let language {
          payload["language"] = language
        }
        return try await bridge.call(.generateCaptions, payload).text
      case "translate":
        guard let language else { return VideoAppleToolBridge.error("translate needs a language, like vi or en.") }
        return try await bridge.call(.translateCaptions, ["language": language]).text
      case "fix", "replace":
        guard let find = VideoEditorAgentAppleArguments.value(arguments.find) else {
          return VideoAppleToolBridge.error("fix needs find (the wrong words) and replace.")
        }
        return try await bridge.call(.replaceInCaptions, ["find": find, "replace": arguments.replace ?? ""]).text
      case "style", "edit":
        var payload: [String: Any] = [:]
        if let font = VideoEditorAgentAppleArguments.value(arguments.font) {
          payload["font"] = font
        }
        if let bold = arguments.bold {
          payload["bold"] = bold
        }
        if let italic = arguments.italic {
          payload["italic"] = italic
        }
        if let position = VideoEditorAgentAppleArguments.value(arguments.position) {
          payload["position"] = position
        }
        guard !payload.isEmpty else {
          return VideoAppleToolBridge.error("style needs font, bold, italic or position.")
        }
        return try await bridge.call(.editCaption, payload).text
      case "show":
        return try await bridge.call(.editCaption, ["show_on_video": true]).text
      case "hide":
        return try await bridge.call(.editCaption, ["show_on_video": false]).text
      case "clear", "remove", "delete":
        guard let target = VideoEditorAgentAppleArguments.value(arguments.id) else {
          return VideoAppleToolBridge.error("clear needs id (like t1, or \"all\").")
        }
        return try await bridge.call(.removeCaptions, ["ids": [target]]).text
      default:
        return VideoAppleToolBridge.error("Unknown action. Use add, translate, fix, style, show, hide or clear.")
      }
    }
  }
#endif
