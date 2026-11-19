//
//  VideoEditorCaptionLineBreaker.swift
//  Snapzy
//
//  Greedy line breaks for caption text: by words for spaced languages, by characters for CJK.
//

import Foundation

nonisolated enum VideoEditorCaptionLineBreaker {
  static func lines(_ text: String, maxCharsPerLine: Int) -> [String] {
    let limit = max(maxCharsPerLine, 1)
    var lines: [String] = []
    var line = ""
    for token in tokens(text) {
      let candidate = line.isEmpty ? token : VideoEditorCaptionSegmenter.join([line, token])
      if candidate.count > limit, !line.isEmpty {
        lines.append(line)
        line = token
      } else {
        line = candidate
      }
    }
    if !line.isEmpty { lines.append(line) }
    return lines
  }

  /// Words for spaced text, single characters for CJK runs.
  private static func tokens(_ text: String) -> [String] {
    var tokens: [String] = []
    for word in text.split(whereSeparator: \.isWhitespace) {
      var latin = ""
      for character in word {
        if VideoEditorCaptionSegmenter.isCJK(character) {
          if !latin.isEmpty { tokens.append(latin); latin = "" }
          tokens.append(String(character))
        } else {
          latin.append(character)
        }
      }
      if !latin.isEmpty { tokens.append(latin) }
    }
    return tokens
  }
}
