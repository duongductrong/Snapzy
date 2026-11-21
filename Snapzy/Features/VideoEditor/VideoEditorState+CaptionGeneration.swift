//
//  VideoEditorState+CaptionGeneration.swift
//  Snapzy
//
//  Generating captions from speech: transcript service → segmenter, with progress and
//  cancel in the editor's progress overlay. Shared with the agent's generate_captions.
//

import AVFoundation
import Foundation

extension VideoEditorState {
  // MARK: - Generate

  /// Transcribes the primary recording and replaces the captions (one undo step).
  /// Progress and cancel go through the editor's progress overlay.
  func generateCaptions() {
    guard canGenerateCaptions, captionTask == nil, !isExporting else { return }
    pause()
    captionNotice = nil
    setCaptionProgress(.transcribing(fraction: 0))
    isExporting = true

    let asset = asset
    let roles = audioTrackRoles
    let locale = captionLocale
    let options = captions.settings.segmenterOptions
    captionTask = Task { @MainActor [weak self] in
      do {
        let result = try await Self.transcribeCaptions(asset: asset, roles: roles, locale: locale, options: options) { progress in
          Task { @MainActor [weak self] in self?.setCaptionProgress(progress) }
        }
        try Task.checkCancellation()
        self?.finishCaptionGeneration(result: result)
      } catch is CancellationError {
        self?.endCaptionGeneration()
      } catch {
        self?.captionNotice = Self.captionErrorMessage(error, locale: locale)
        self?.endCaptionGeneration()
      }
    }
  }

  func cancelCaptionGeneration() {
    guard let task = captionTask else { return }
    task.cancel()
    endCaptionGeneration()
  }

  /// Speech → caption segments (source time) plus how many stretches failed.
  nonisolated static func transcribeCaptions(
    asset: AVAsset,
    roles: [VideoEditorAudioTrackRole],
    locale: Locale,
    options: VideoEditorCaptionSegmenterOptions,
    progress: (@Sendable (TranscriptProgress) -> Void)? = nil
  ) async throws -> (segments: [CaptionSegment], unrecognized: Int) {
    let result = try await VideoEditorTranscriptService.shared.transcribe(
      asset: asset, roles: roles, locale: locale, progress: progress
    )
    return (VideoEditorCaptionSegmenter.segment(result.words, options: options), result.unrecognizedSpans.count)
  }

  /// Replaces the captions with generated ones (one undo step) and shows them.
  func applyGeneratedCaptions(_ segments: [CaptionSegment], showOnVideo: Bool = true) {
    var value = captions
    value.segments = segments
    value.settings.isEnabled = showOnVideo
    setCaptions(value)
  }

  private func finishCaptionGeneration(result: (segments: [CaptionSegment], unrecognized: Int)) {
    guard captionTask != nil else { return }
    let segments = result.segments
    if segments.isEmpty {
      captionNotice = L10n.VideoEditor.captionsNoSpeech
    } else {
      applyGeneratedCaptions(segments)
      if result.unrecognized > 0 {
        captionNotice = L10n.VideoEditor.captionsPartial(result.unrecognized)
      }
    }
    endCaptionGeneration()
  }

  private func endCaptionGeneration() {
    captionTask = nil
    if progressOperation.isCaptionWork { isExporting = false }
  }

  private func setCaptionProgress(_ progress: TranscriptProgress) {
    guard captionTask != nil || !isExporting else { return }
    let operation: VideoEditorProgressOperation
    let fraction: Double
    switch progress {
    case .downloadingModel(let value):
      operation = .downloadSpeechModel
      fraction = value
    case .transcribing(let value):
      operation = .generateCaptions
      fraction = value
    }
    if progressOperation != operation {
      progressOperation = operation
      exportStatusMessage = operation.initialStatusMessage
    }
    // The recognizer reports per audio buffer (thousands per run). Each write re-renders
    // every view observing the editor, so publish only visible 0.5% steps.
    let quantized = Float((min(max(fraction, 0), 1) * 200).rounded(.down) / 200)
    if exportProgress != quantized { exportProgress = quantized }
  }

  nonisolated static func captionErrorMessage(_ error: Error, locale: Locale) -> String {
    switch error as? VideoEditorTranscriptError {
    case .noAudio:
      return L10n.VideoEditor.captionsErrorNoAudio
    case .denied:
      return L10n.VideoEditor.captionsErrorDenied
    case .unsupported:
      let name = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
      return L10n.VideoEditor.captionsErrorUnsupported(name)
    default:
      return L10n.VideoEditor.captionsErrorFailed
    }
  }
}
