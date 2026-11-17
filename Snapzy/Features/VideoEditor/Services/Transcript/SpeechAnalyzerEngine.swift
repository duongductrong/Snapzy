//
//  SpeechAnalyzerEngine.swift
//  Snapzy
//
//  macOS 26+: `SpeechAnalyzer` with `SpeechTranscriber` (long-form, per-word audio time
//  ranges). `DictationTranscriber` stands in when the locale or device has no
//  SpeechTranscriber. Speech models install through `AssetInventory`, with progress.
//

import AVFoundation
import Foundation
import Speech

@available(macOS 26.0, *)
nonisolated final class SpeechAnalyzerEngine: TranscriptEngine {
  let id = TranscriptEngineID.speechAnalyzer
  private let cancelFlag = TranscriptCancelFlag()

  func availability(for locale: Locale) async -> TranscriptEngineAvailability {
    if SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
      let installed = await SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47) == supported.identifier(.bcp47) }
      return installed ? .available : .needsModelDownload
    }
    if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
      let installed = await DictationTranscriber.installedLocales.contains { $0.identifier(.bcp47) == supported.identifier(.bcp47) }
      return installed ? .available : .needsModelDownload
    }
    return .unsupported
  }

  func transcribe(
    asset: AVAsset,
    tracks: [AVAssetTrack],
    locale: Locale,
    contextualStrings: [String],
    progress: (@Sendable (TranscriptProgress) -> Void)?
  ) async throws -> TranscriptResult {
    cancelFlag.reset()
    let duration = try await CMTimeGetSeconds(asset.load(.duration))
    let run = Run(asset: asset, tracks: tracks, duration: duration, contextualStrings: contextualStrings, progress: progress, cancel: cancelFlag)
    if SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
      let module = SpeechTranscriber(
        locale: supported,
        transcriptionOptions: [],
        reportingOptions: [],
        attributeOptions: [.audioTimeRange]
      )
      return try await run.execute(module) { $0.text }
    }
    guard let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) else {
      throw VideoEditorTranscriptError.unsupported(locale.identifier)
    }
    let module = DictationTranscriber(
      locale: supported,
      contentHints: [],
      transcriptionOptions: [.punctuation],
      reportingOptions: [],
      attributeOptions: [.audioTimeRange]
    )
    return try await run.execute(module) { $0.text }
  }

  func cancel() {
    cancelFlag.cancel()
  }

  /// Per-word time ranges (`audioTimeRange` runs) of one result's text.
  static func words(from text: AttributedString) -> [VideoEditorTranscriptWord] {
    var words: [VideoEditorTranscriptWord] = []
    for run in text.runs {
      let piece = String(text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !piece.isEmpty, let range = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] else { continue }
      let start = CMTimeGetSeconds(range.start)
      let length = CMTimeGetSeconds(range.duration)
      guard start.isFinite, length.isFinite else { continue }
      words.append(.init(start: start, duration: max(length, 0), text: piece))
    }
    return words
  }
}
