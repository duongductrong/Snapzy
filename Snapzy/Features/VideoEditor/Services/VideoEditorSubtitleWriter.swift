//
//  VideoEditorSubtitleWriter.swift
//  Snapzy
//
//  SRT and WebVTT text from cues in OUTPUT time (the caller maps source -> output time).
//

import Foundation

nonisolated struct VideoEditorSubtitleCue: Equatable, Sendable {
  var start: TimeInterval
  var end: TimeInterval
  var text: String
}

nonisolated enum VideoEditorSubtitleWriter {
  /// Sane upper bound for subtitle timestamps (240 hours = 864,000s) preventing integer overflow.
  static let maxTimestampSeconds: TimeInterval = 864_000
  static let maxParsedSegments: Int = 5_000

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

  /// `HH:MM:SS<separator>mmm`, rounded to the millisecond and clamped to `[0, maxTimestampSeconds]`.
  static func timestamp(_ seconds: TimeInterval, separator: String) -> String {
    let clamped = seconds.isFinite ? min(max(seconds, 0), maxTimestampSeconds) : 0
    let total = max(Int((clamped * 1000).rounded()), 0)
    return String(
      format: "%02d:%02d:%02d%@%03d",
      total / 3_600_000,
      total / 60_000 % 60,
      total / 1000 % 60,
      separator,
      total % 1000
    )
  }

  private static func usable(_ cues: [VideoEditorSubtitleCue]) -> [VideoEditorSubtitleCue] {
    cues
      .compactMap { cue -> VideoEditorSubtitleCue? in
        guard cue.start.isFinite,
              cue.end.isFinite,
              !cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        let clampedStart = min(max(cue.start, 0), maxTimestampSeconds)
        let clampedEnd = min(max(cue.end, 0), maxTimestampSeconds)
        guard clampedEnd > clampedStart else { return nil }
        return VideoEditorSubtitleCue(start: clampedStart, end: clampedEnd, text: cue.text)
      }
      .sorted { $0.start < $1.start }
  }

  /// A blank line would end the cue, so lines are re-broken and empty ones dropped.
  private static func text(_ cue: VideoEditorSubtitleCue, maxCharsPerLine: Int, escape: Bool) -> String {
    let safeMaxChars = min(max(maxCharsPerLine, 8), 120)
    let lines = cue.text.split(whereSeparator: \.isNewline).flatMap {
      VideoEditorCaptionLineBreaker.lines(String($0), maxCharsPerLine: safeMaxChars)
    }
    let joined = lines.joined(separator: "\n")
    guard escape else { return joined }
    return joined.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
  }

  /// Parse `.srt` or `.vtt` subtitle text into sorted source-time `CaptionSegment`s.
  static func parse(_ raw: String) -> [CaptionSegment] {
    let normalized = raw
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let blocks = normalized.components(separatedBy: "\n\n")
    var segments: [CaptionSegment] = []

    for block in blocks {
      guard segments.count < maxParsedSegments else { break }
      let lines = block
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { String($0).trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
      guard !lines.isEmpty else { continue }
      if lines[0].uppercased().hasPrefix("WEBVTT") || lines[0].uppercased().hasPrefix("NOTE") {
        continue
      }

      guard let arrowIdx = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
      let timingParts = lines[arrowIdx].components(separatedBy: "-->")
      guard timingParts.count >= 2,
            let start = parseTimestamp(timingParts[0]),
            let end = parseTimestamp(timingParts[1].split(whereSeparator: \.isWhitespace).first
              .map(String.init) ?? timingParts[1]),
            end > start + 0.05
      else { continue }

      let textLines = lines[(arrowIdx + 1)...]
      let joined = textLines.joined(separator: "\n")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&amp;", with: "&")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !joined.isEmpty else { continue }

      segments.append(CaptionSegment(sourceRange: start ... end, text: joined))
    }

    return segments.sorted { $0.start < $1.start }
  }

  private static func parseTimestamp(_ raw: String) -> TimeInterval? {
    let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: ",", with: ".")
    let cols = token.split(separator: ":")
    guard cols.count == 2 || cols.count == 3 else { return nil }
    let total: Double
    if cols.count == 3 {
      guard let h = Double(cols[0]),
            let m = Double(cols[1]),
            let s = Double(cols[2]),
            h.isFinite, m.isFinite, s.isFinite,
            h >= 0, m >= 0, m < 60, s >= 0, s < 60
      else { return nil }
      total = h * 3600 + m * 60 + s
    } else {
      guard let m = Double(cols[0]),
            let s = Double(cols[1]),
            m.isFinite, s.isFinite,
            m >= 0, s >= 0, s < 60
      else { return nil }
      total = m * 60 + s
    }
    guard total.isFinite, total >= 0, total <= maxTimestampSeconds else { return nil }
    return total
  }
}
