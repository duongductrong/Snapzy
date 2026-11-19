//
//  VideoEditorCaptionSegmenter.swift
//  Snapzy
//
//  Words → caption segments: break at sentence ends, pauses, the character budget
//  (lines × chars per line) and the maximum duration. CJK text has no spaces and is
//  counted, joined and split by characters.
//

import Foundation

nonisolated enum VideoEditorCaptionSegmenter {
  typealias Options = VideoEditorCaptionSegmenterOptions

  static func segment(_ input: [VideoEditorTranscriptWord], options: Options = .init()) -> [CaptionSegment] {
    let words = input
      .map { VideoEditorTranscriptWord(start: $0.start, duration: $0.duration, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
      .filter { !$0.text.isEmpty }
      .sorted { $0.start < $1.start }
      .flatMap { split($0, limit: options.maxCharacters) }

    var segments: [CaptionSegment] = []
    var current: [VideoEditorTranscriptWord] = []
    func flush() {
      guard let first = current.first, let last = current.last else { return }
      segments.append(CaptionSegment(
        sourceRange: first.start ... max(last.end, first.start),
        text: join(current.map(\.text)),
        words: current
      ))
      current = []
    }

    for word in words {
      if let first = current.first, let last = current.last {
        let text = join(current.map(\.text) + [word.text])
        let sentenceEnded = endsSentence(last.text) && last.end - first.start >= options.minDuration
        let clauseEnded = endsClause(last.text) && join(current.map(\.text)).count >= options.maxCharsPerLine
        if word.start - last.end > options.pauseBreak
          || text.count > options.maxCharacters
          || word.end - first.start > options.maxDuration
          || sentenceEnded || clauseEnded {
          flush()
        }
      }
      current.append(word)
    }
    flush()
    return extendShortSegments(segments, minDuration: options.minDuration)
  }

  /// Latin words are joined with spaces, CJK with nothing.
  static func join(_ parts: [String]) -> String {
    var result = ""
    for part in parts {
      if let last = result.last, let first = part.first, !isCJK(last), !isCJK(first) { result += " " }
      result += part
    }
    return result
  }

  static func isCJK(_ character: Character) -> Bool {
    character.unicodeScalars.contains { scalar in
      switch scalar.value {
      case 0x3040 ... 0x30FF, 0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF, 0xAC00 ... 0xD7AF, 0xF900 ... 0xFAFF, 0xFF66 ... 0xFF9F, 0x20000 ... 0x2FA1F:
        return true
      default:
        return false
      }
    }
  }

  /// A token longer than the budget (a whole CJK segment, a remote "segment as word") is cut by
  /// characters, its time shared in proportion.
  private static func split(_ word: VideoEditorTranscriptWord, limit: Int) -> [VideoEditorTranscriptWord] {
    let characters = Array(word.text)
    guard characters.count > limit else { return [word] }
    let pieces = stride(from: 0, to: characters.count, by: limit).map { String(characters[$0 ..< min($0 + limit, characters.count)]) }
    var offset = 0.0
    return pieces.map { piece in
      let share = word.duration * Double(piece.count) / Double(characters.count)
      defer { offset += share }
      return VideoEditorTranscriptWord(start: word.start + offset, duration: share, text: piece)
    }
  }

  private static func endsSentence(_ text: String) -> Bool {
    text.last.map { ".?!。？！…".contains($0) } ?? false
  }

  private static func endsClause(_ text: String) -> Bool {
    text.last.map { ",;:，、；：".contains($0) } ?? false
  }

  /// Short captions stay up for at least `minDuration`, never into the next caption.
  private static func extendShortSegments(_ segments: [CaptionSegment], minDuration: TimeInterval) -> [CaptionSegment] {
    var result = segments
    for index in result.indices {
      let nextStart = index + 1 < result.count ? result[index + 1].start : .infinity
      let wanted = min(result[index].start + minDuration, nextStart)
      if result[index].end < wanted { result[index].sourceRange = result[index].start ... wanted }
    }
    return result
  }
}
