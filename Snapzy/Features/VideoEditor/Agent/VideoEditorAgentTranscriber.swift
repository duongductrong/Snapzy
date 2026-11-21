//
//  VideoEditorAgentTranscriber.swift
//  Snapzy
//
//  What is said in the recording, for `get_transcript`. A thin adapter over
//  `VideoEditorTranscriptService` (on-device engines only): the audio never leaves
//  the Mac; only the text the agent reads does, like the rest of the timeline.
//  The Speech Recognition permission is asked the first time the SFSpeech engine runs.
//
//  The microphone track is preferred (the narrator), else every track mixed.
//  Results are words in SOURCE time of the primary recording, grouped into
//  phrases and cached per file and language; the toolbox maps them onto the
//  timeline through the current clips.
//

import AVFoundation
import Foundation

// MARK: - Transcriber

@MainActor
final class VideoEditorAgentTranscriber {
  /// `@concurrent`: a nonsending async closure type stored as a value pulls in
  /// swift_getExtendedFunctionTypeMetadata (macOS 15+ only), which crashes Release builds on 13/14 (#725).
  typealias Engine = @concurrent @Sendable (_ asset: AVAsset, _ roles: [VideoEditorAudioTrackRole], _ locale: Locale) async throws -> [VideoEditorTranscriptWord]

  private struct Key: Equatable {
    let url: URL
    let modified: Date?
    let language: String
  }

  private let engine: Engine
  private var cached: [(key: Key, phrases: [VideoEditorTranscriptPhrase])] = []
  private var inFlight: (key: Key, task: Task<[VideoEditorTranscriptPhrase], Error>)?

  init(engine: @escaping Engine = VideoEditorTranscriptService.agentWords) {
    self.engine = engine
  }

  /// Phrases of the primary recording in source time, from cache when it is current.
  func phrases(for state: VideoEditorState, locale: Locale) async throws -> [VideoEditorTranscriptPhrase] {
    guard !state.audioTrackRoles.isEmpty else { throw VideoEditorTranscriptError.noAudio }
    let url = state.editingSourceURL
    let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    let key = Key(url: url, modified: modified, language: locale.identifier)
    if let hit = cached.first(where: { $0.key == key }) { return hit.phrases }
    if let inFlight, inFlight.key == key { return try await inFlight.task.value }

    let engine = self.engine
    let asset = state.asset
    let roles = state.audioTrackRoles
    let task = Task.detached(priority: .userInitiated) {
      Self.phrases(try await engine(asset, roles, locale))
    }
    inFlight = (key, task)
    defer { if inFlight?.key == key { inFlight = nil } }
    let phrases = try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
    cached.append((key, phrases))
    if cached.count > 3 { cached.removeFirst() }
    return phrases
  }

  /// Words → phrases: a new phrase after a pause, at the end of a sentence, or past `maxLength` seconds.
  nonisolated static func phrases(
    _ words: [VideoEditorTranscriptWord],
    maxGap: TimeInterval = 0.7,
    maxLength: TimeInterval = 12
  ) -> [VideoEditorTranscriptPhrase] {
    var phrases: [VideoEditorTranscriptPhrase] = []
    var current: (start: TimeInterval, end: TimeInterval, words: [String])?
    for word in words.sorted(by: { $0.start < $1.start }) {
      let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      let end = word.start + max(word.duration, 0)
      if var open = current,
         word.start - open.end <= maxGap,
         end - open.start <= maxLength,
         !(open.words.last.map(endsSentence) ?? false) {
        open.end = max(open.end, end)
        open.words.append(text)
        current = open
      } else {
        if let open = current {
          phrases.append(.init(range: open.start ... open.end, text: open.words.joined(separator: " ")))
        }
        current = (word.start, end, [text])
      }
    }
    if let open = current {
      phrases.append(.init(range: open.start ... open.end, text: open.words.joined(separator: " ")))
    }
    return phrases
  }

  nonisolated private static func endsSentence(_ word: String) -> Bool {
    guard let last = word.last else { return false }
    return ".?!。？！".contains(last)
  }
}
