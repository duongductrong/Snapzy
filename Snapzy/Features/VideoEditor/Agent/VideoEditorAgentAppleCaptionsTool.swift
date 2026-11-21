//
//  VideoEditorAgentAppleCaptionsTool.swift
//  Snapzy
//
//  Apple Intelligence compact tool for captions: create from speech, translate, fix a
//  word everywhere, show, hide or clear. Maps onto the shared toolbox caption tools.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
nonisolated struct VideoAppleCaptionsTool: Tool {
  let bridge: VideoAppleToolBridge

  let name = "captions"
  let description = """
  Subtitles: add creates them from the speech (replacing old ones); translate rewrites them in another language; \
  fix replaces a word in all of them; show, hide or clear them.
  """

  @Generable
  struct Arguments {
    @Guide(description: "What to do", .anyOf(["add", "translate", "fix", "show", "hide", "clear"]))
    var action: String
    @Guide(description: "add: spoken language like en-US; translate: target language like vi, en, ja; empty when unsure")
    var language: String?
    @Guide(description: "fix: the wrong word or words")
    var find: String?
    @Guide(description: "fix: the right word or words")
    var replace: String?
  }

  func call(arguments: Arguments) async throws -> String {
    let language = VideoEditorAgentAppleArguments.value(arguments.language)
    switch arguments.action.lowercased() {
    case "add", "create", "generate":
      var payload: [String: Any] = [:]
      if let language { payload["language"] = language }
      return try await bridge.call(.generateCaptions, payload).text
    case "translate":
      guard let language else { return VideoAppleToolBridge.error("translate needs a language, like vi or en.") }
      return try await bridge.call(.translateCaptions, ["language": language]).text
    case "fix", "replace":
      guard let find = VideoEditorAgentAppleArguments.value(arguments.find) else {
        return VideoAppleToolBridge.error("fix needs find (the wrong words) and replace.")
      }
      return try await bridge.call(.replaceInCaptions, ["find": find, "replace": arguments.replace ?? ""]).text
    case "show":
      return try await bridge.call(.editCaption, ["show_on_video": true]).text
    case "hide":
      return try await bridge.call(.editCaption, ["show_on_video": false]).text
    case "clear", "remove", "delete":
      return try await bridge.call(.removeCaptions, ["ids": ["all"]]).text
    default:
      return VideoAppleToolBridge.error("Unknown action. Use add, translate, fix, show, hide or clear.")
    }
  }
}
#endif
