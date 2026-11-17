//
//  SFSpeechChunkedEngine.swift
//  Snapzy
//
//  macOS 13+: on-device `SFSpeechRecognizer` over chunks of at most 50 s, cut at silences
//  (the agent analyzer's silence analysis). Each chunk is retried twice; a chunk that
//  still fails is reported as unrecognized instead of failing the file.
//

import AVFoundation
import Foundation
import Speech

nonisolated final class SFSpeechChunkedEngine: TranscriptEngine {
  /// Words of one chunk, relative to the chunk's start.
  typealias ChunkRecognizer = @Sendable (
    _ asset: AVAsset, _ tracks: [AVAssetTrack], _ range: ClosedRange<TimeInterval>,
    _ locale: Locale, _ contextualStrings: [String]
  ) async throws -> [VideoEditorTranscriptWord]
  typealias SilenceProvider = @Sendable (AVAsset, [AVAssetTrack]) async throws -> [ClosedRange<TimeInterval>]

  static let maximumChunkLength: TimeInterval = 50

  let id = TranscriptEngineID.sfSpeech
  private let recognizer: ChunkRecognizer
  private let silences: SilenceProvider
  private let cancelFlag = TranscriptCancelFlag()

  init(
    recognizer: @escaping ChunkRecognizer = SFSpeechChunkRecognizer.recognize,
    silences: @escaping SilenceProvider = SFSpeechChunkedEngine.analyzerSilences
  ) {
    self.recognizer = recognizer
    self.silences = silences
  }

  func availability(for locale: Locale) async -> TranscriptEngineAvailability {
    guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
      return .unsupported
    }
    return .available
  }

  func transcribe(
    asset: AVAsset,
    tracks: [AVAssetTrack],
    locale: Locale,
    contextualStrings: [String],
    progress: (@Sendable (TranscriptProgress) -> Void)?
  ) async throws -> TranscriptResult {
    cancelFlag.reset()
    try await SFSpeechChunkRecognizer.authorize()
    let duration = try await CMTimeGetSeconds(asset.load(.duration))
    guard duration.isFinite, duration > 0 else { throw VideoEditorTranscriptError.noAudio }
    // Silence analysis is best effort: without it chunks are cut at the limit.
    let quiet = (try? await silences(asset, tracks)) ?? []
    let chunks = TranscriptChunker.plan(duration: duration, silences: quiet, maxLength: Self.maximumChunkLength)
    let recognizer = self.recognizer
    return try await withTaskCancellationHandler {
      try await TranscriptChunker.run(
        chunks: chunks,
        cancel: cancelFlag,
        progress: { progress?(.transcribing(fraction: $0)) }
      ) { range in
        try await recognizer(asset, tracks, range, locale, Array(contextualStrings.prefix(100)))
      }
    } onCancel: {
      self.cancelFlag.cancel()
    }
  }

  func cancel() {
    cancelFlag.cancel()
  }

  static func analyzerSilences(asset: AVAsset, tracks: [AVAssetTrack]) async throws -> [ClosedRange<TimeInterval>] {
    let levels = try await VideoEditorAgentAnalyzer.readLevels(asset: asset, tracks: tracks)
    return VideoEditorAgentAnalyzer.silences(levels: levels, window: VideoEditorAgentAnalyzer.window)
  }
}
