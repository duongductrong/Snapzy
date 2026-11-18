//
//  VideoEditorAgentAppleCaptionsTool.swift
//  Snapzy
//
//  Apple Intelligence compact tool for captions: create from speech, show or hide.
//  Maps onto generate_captions / edit_caption in the shared toolbox.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
nonisolated struct VideoAppleCaptionsTool: Tool {
  let bridge: VideoAppleToolBridge

  let name = "captions"
  let description = "Subtitles: add creates them from the speech (replacing old ones); show or hide them on the video."

  @Generable
  struct Arguments {
    @Guide(description: "What to do", .anyOf(["add", "show", "hide"]))
    var action: String
    @Guide(description: "add: spoken language like en-US or vi-VN; leave empty when unsure")
    var language: String?
  }

  func call(arguments: Arguments) async throws -> String {
    switch arguments.action.lowercased() {
    case "add", "create", "generate":
      var payload: [String: Any] = [:]
      if let language = VideoEditorAgentAppleArguments.value(arguments.language) { payload["language"] = language }
      return try await bridge.call(.generateCaptions, payload).text
    case "show":
      return try await bridge.call(.editCaption, ["show_on_video": true]).text
    case "hide":
      return try await bridge.call(.editCaption, ["show_on_video": false]).text
    default:
      return VideoAppleToolBridge.error("Unknown action. Use add, show or hide.")
    }
  }
}
#endif
