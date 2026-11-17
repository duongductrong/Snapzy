//
//  SpeechAnalyzerRun.swift
//  Snapzy
//
//  One `SpeechAnalyzer` pass over an asset's audio: model install, audio feed, results.
//

import AVFoundation
import Foundation
import Speech

@available(macOS 26.0, *)
extension SpeechAnalyzerEngine {
  nonisolated struct Run {
    let asset: AVAsset
    let tracks: [AVAssetTrack]
    let duration: TimeInterval
    let contextualStrings: [String]
    let progress: (@Sendable (TranscriptProgress) -> Void)?
    let cancel: TranscriptCancelFlag

    func execute<M: SpeechModule>(
      _ module: M,
      text: @escaping @Sendable (M.Result) -> AttributedString
    ) async throws -> TranscriptResult {
      try await installModelIfNeeded(module)
      guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
        throw VideoEditorTranscriptError.failed("no compatible audio format")
      }
      let analyzer = SpeechAnalyzer(modules: [module])
      if !contextualStrings.isEmpty {
        let context = AnalysisContext()
        context.contextualStrings = [.general: Array(contextualStrings.prefix(100))]
        try await analyzer.setContext(context)
      }
      let collector = Task { () -> [VideoEditorTranscriptWord] in
        var words: [VideoEditorTranscriptWord] = []
        for try await result in module.results where result.isFinal {
          words += SpeechAnalyzerEngine.words(from: text(result))
        }
        return words
      }
      let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
      do {
        try await withTaskCancellationHandler {
          try await analyzer.start(inputSequence: stream)
          try await TranscriptAudioReader.read(asset: asset, tracks: tracks, format: format) { buffer, delivered in
            try cancel.check()
            continuation.yield(AnalyzerInput(buffer: buffer))
            if duration > 0 { progress?(.transcribing(fraction: min(delivered / duration, 1))) }
          }
          continuation.finish()
          try await analyzer.finalizeAndFinishThroughEndOfInput()
        } onCancel: {
          continuation.finish()
          Task { await analyzer.cancelAndFinishNow() }
        }
      } catch {
        continuation.finish()
        collector.cancel()
        await analyzer.cancelAndFinishNow()
        throw error
      }
      let words = try await collector.value
      progress?(.transcribing(fraction: 1))
      return TranscriptResult(words: words)
    }

    private func installModelIfNeeded<M: SpeechModule>(_ module: M) async throws {
      guard await AssetInventory.status(forModules: [module]) < .installed else { return }
      guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { return }
      let progress = self.progress
      let observer = Task {
        while !Task.isCancelled {
          progress?(.downloadingModel(fraction: request.progress.fractionCompleted))
          try? await Task.sleep(nanoseconds: 250_000_000)
        }
      }
      defer { observer.cancel() }
      try await request.downloadAndInstall()
      progress?(.downloadingModel(fraction: 1))
    }
  }
}
