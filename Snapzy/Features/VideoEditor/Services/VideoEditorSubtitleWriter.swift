//
//  VideoEditorSubtitleWriter.swift
//  Snapzy
//
//  SRT and WebVTT text from cues in OUTPUT time (the caller maps source → output time).
//

import Foundation

nonisolated struct VideoEditorSubtitleCue: Equatable, Sendable {
  var start: TimeInterval
  var end: TimeInterval
  var text: String
}

nonisolated enum VideoEditorSubtitleWriter {
  /// Cues in source time, unchanged (no cuts or speed).
  static func cues(from segments: [CaptionSegment]) -> [VideoEditorSubtitleCue] {
    segments.map { VideoEditorSubtitleCue(start: $0.start, end: $0.end, text: $0.text) }
  }

  static func srt(_ cues: [VideoEditorSubtitleCue], maxCharsPerLine: Int = 42) -> String {
    let body = usable(cues).enumerated().map { index, cue in
      "\(index + 1)\n\(timestamp(cue.start, separator: ",")) --> \(timestamp(cue.end, separator: ","))\n"
        + text(cue, maxCharsPerLine: maxCharsPerLine, escape: false)
    }
    return body.joined(separator: "\n\n") + (body.isEmpty ? "" : "\n")
  }

  static func vtt(_ cues: [VideoEditorSubtitleCue], maxCharsPerLine: Int = 42) -> String {
    let body = usable(cues).map { cue in
      "\(timestamp(cue.start, separator: ".")) --> \(timestamp(cue.end, separator: "."))\n"
        + text(cue, maxCharsPerLine: maxCharsPerLine, escape: true)
    }
    return "WEBVTT\n\n" + body.joined(separator: "\n\n") + (body.isEmpty ? "" : "\n")
  }

  /// `HH:MM:SS<separator>mmm`, rounded to the millisecond.
  static func timestamp(_ seconds: TimeInterval, separator: String) -> String {
    let total = max(Int((max(seconds, 0) * 1000).rounded()), 0)
    return String(format: "%02d:%02d:%02d%@%03d", total / 3_600_000, total / 60_000 % 60, total / 1000 % 60, separator, total % 1000)
  }

  private static func usable(_ cues: [VideoEditorSubtitleCue]) -> [VideoEditorSubtitleCue] {
    cues
      .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.end > $0.start }
      .sorted { $0.start < $1.start }
  }

  /// A blank line would end the cue, so lines are re-broken and empty ones dropped.
  private static func text(_ cue: VideoEditorSubtitleCue, maxCharsPerLine: Int, escape: Bool) -> String {
    let lines = cue.text.split(whereSeparator: \.isNewline).flatMap {
      VideoEditorCaptionLineBreaker.lines(String($0), maxCharsPerLine: maxCharsPerLine)
    }
    let joined = lines.joined(separator: "\n")
    guard escape else { return joined }
    return joined.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
  }
}
