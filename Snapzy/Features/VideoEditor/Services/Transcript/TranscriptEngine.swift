//
//  TranscriptEngine.swift
//  Snapzy
//
//  One way of turning a recording's audio into timed words. The service picks the
//  first engine that is available for the locale (SpeechAnalyzer → SFSpeech
//  on-device → remote, only when the caller opted in).
//

import AVFoundation
import Foundation

nonisolated protocol TranscriptEngine: Sendable {
  var id: TranscriptEngineID { get }
  /// Whether this engine can handle `locale` on this Mac right now.
  func availability(for locale: Locale) async -> TranscriptEngineAvailability
  /// Words of `tracks` in source time. `contextualStrings` are terms likely to be said
  /// (on-screen text); engines that cannot use them ignore them.
  func transcribe(
    asset: AVAsset,
    tracks: [AVAssetTrack],
    locale: Locale,
    contextualStrings: [String],
    progress: (@Sendable (TranscriptProgress) -> Void)?
  ) async throws -> TranscriptResult
  /// Stops a running `transcribe` (it then throws `CancellationError`).
  func cancel()
}
