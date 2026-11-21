//
//  VideoEditorTranscriptService.swift
//  Snapzy
//
//  The one place that turns a recording into words. Picks the first engine that handles
//  the locale (SpeechAnalyzer → SFSpeech on-device → remote, only with `allowRemote`),
//  prefers the microphone track, and caches per file + modification date + engine + locale.
//

import AVFoundation
import Foundation

actor VideoEditorTranscriptService {
  static let shared = VideoEditorTranscriptService()

  struct CacheKey: Equatable {
    let url: URL
    let modified: Date?
    let engine: TranscriptEngineID
    let locale: String
  }

  private let engines: [any TranscriptEngine]
  private var remote: (any TranscriptEngine)?
  private var cache: [(key: CacheKey, result: TranscriptResult)] = []
  private var running: (any TranscriptEngine)?

  /// `engines` in order of preference, on-device ones.
  init(engines: [any TranscriptEngine]? = nil, remote: (any TranscriptEngine)? = nil) {
    self.engines = engines ?? Self.defaultEngines()
    self.remote = remote
  }

  nonisolated static func defaultEngines() -> [any TranscriptEngine] {
    var engines: [any TranscriptEngine] = []
    if #available(macOS 26.0, *) { engines.append(SpeechAnalyzerEngine()) }
    engines.append(SFSpeechChunkedEngine())
    return engines
  }

  /// Sets the engine used for opt-in remote transcription (from Settings → AI).
  func setRemote(_ engine: (any TranscriptEngine)?) {
    remote = engine
  }

  /// The engine `transcribe` would use, and whether it first needs a model download.
  func plan(locale: Locale, allowRemote: Bool = false) async -> (engine: any TranscriptEngine, availability: TranscriptEngineAvailability)? {
    for engine in engines {
      let availability = await engine.availability(for: locale)
      if availability != .unsupported { return (engine, availability) }
    }
    if allowRemote, let remote, await remote.availability(for: locale) != .unsupported {
      return (remote, .available)
    }
    return nil
  }

  func transcribe(
    asset: AVAsset,
    roles: [VideoEditorAudioTrackRole],
    locale: Locale,
    contextualStrings: [String] = [],
    allowRemote: Bool = false,
    progress: (@Sendable (TranscriptProgress) -> Void)? = nil
  ) async throws -> TranscriptResult {
    let all = try await asset.loadTracks(withMediaType: .audio)
    guard !all.isEmpty else { throw VideoEditorTranscriptError.noAudio }
    let microphone = zip(all, roles).filter { $0.1 == .microphone }.map(\.0)
    let tracks = microphone.isEmpty ? all : microphone

    guard let (engine, _) = await plan(locale: locale, allowRemote: allowRemote) else {
      throw VideoEditorTranscriptError.unsupported(locale.identifier)
    }
    let key = Self.key(asset: asset, engine: engine.id, locale: locale)
    if let key, let hit = cache.first(where: { $0.key == key }) { return hit.result }

    running = engine
    defer { running = nil }
    let result = try await withTaskCancellationHandler {
      try await engine.transcribe(
        asset: asset, tracks: tracks, locale: locale, contextualStrings: contextualStrings, progress: progress
      )
    } onCancel: {
      engine.cancel()
    }
    if let key {
      cache.append((key, result))
      if cache.count > 4 { cache.removeFirst() }
    }
    return result
  }

  /// Stops the transcription in flight, if any.
  func cancel() {
    running?.cancel()
  }

  nonisolated static func key(asset: AVAsset, engine: TranscriptEngineID, locale: Locale) -> CacheKey? {
    guard let url = (asset as? AVURLAsset)?.url else { return nil }
    let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    return CacheKey(url: url, modified: modified, engine: engine, locale: locale.identifier)
  }

  /// Adapter for the video-editor agent: words only, on-device engines only.
  nonisolated static func agentWords(
    asset: AVAsset,
    roles: [VideoEditorAudioTrackRole],
    locale: Locale
  ) async throws -> [VideoEditorTranscriptWord] {
    try await shared.transcribe(asset: asset, roles: roles, locale: locale).words
  }
}
