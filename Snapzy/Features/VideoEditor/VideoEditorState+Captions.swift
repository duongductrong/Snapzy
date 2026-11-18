//
//  VideoEditorState+Captions.swift
//  Snapzy
//
//  Captions: generate from speech (transcript service → segmenter), edit with undo,
//  preview lookup and SRT/VTT text in output time.
//

import AVFoundation
import Foundation

extension VideoEditorState {
  /// Captions need speech: video (not GIF) with at least one audio track.
  var canGenerateCaptions: Bool { !isGIF && !audioTrackRoles.isEmpty }

  var isGeneratingCaptions: Bool { captionTask != nil }

  /// Speech language: the panel's choice, else the app language (with the Mac's region
  /// when they match), else the Mac's locale.
  var captionLocale: Locale {
    if let identifier = captions.settings.languageIdentifier, !identifier.isEmpty {
      return Locale(identifier: identifier)
    }
    return Self.defaultCaptionLocale()
  }

  nonisolated static func defaultCaptionLocale(appLanguage: String? = nil, current: Locale = .current) -> Locale {
    let system = VideoEditorAgentToolbox.speechLocale(nil)
    guard let appLanguage, !appLanguage.isEmpty else { return system }
    let appCode = Locale(identifier: appLanguage).language.languageCode?.identifier
    if appCode == current.language.languageCode?.identifier { return system }
    return Locale(identifier: appLanguage)
  }

  static func defaultCaptionLocale() -> Locale {
    defaultCaptionLocale(appLanguage: AppLanguageManager.shared.activeEffectiveLanguageIdentifier)
  }

  // MARK: - Editing

  func setCaptions(_ new: VideoEditorCaptions, recordUndo: Bool = true) {
    let old = captions
    guard new != old else { return }
    applyCaptions(new)
    if recordUndo { recordAction(.updateCaptions(old: old, new: new)) }
  }

  /// One undo step for a slider drag or a text field edit that changed `captions` live.
  func commitCaptions(from old: VideoEditorCaptions) {
    guard old != captions else { return }
    recordAction(.updateCaptions(old: old, new: captions))
  }

  func applyCaptions(_ value: VideoEditorCaptions) {
    var value = value
    value.segments.sort { $0.start < $1.start }
    captions = value
    updateHasUnsavedChanges()
  }

  func setCaptionSettings(_ settings: VideoEditorCaptionSettings, recordUndo: Bool = true) {
    var value = captions
    value.settings = settings
    setCaptions(value, recordUndo: recordUndo)
  }

  func updateCaptionText(id: UUID, text: String, recordUndo: Bool = true) {
    var value = captions
    guard let index = value.segments.firstIndex(where: { $0.id == id }), value.segments[index].text != text else { return }
    value.segments[index].text = text
    // Word timings no longer match edited text.
    value.segments[index].words = nil
    setCaptions(value, recordUndo: recordUndo)
  }

  /// New source range for a caption, clamped to at least 0.2 s and the recording.
  func updateCaptionRange(id: UUID, range: ClosedRange<TimeInterval>, recordUndo: Bool = true) {
    var value = captions
    guard let index = value.segments.firstIndex(where: { $0.id == id }) else { return }
    let start = max(0, range.lowerBound)
    let total = CMTimeGetSeconds(duration)
    let end = max(start + 0.2, total.isFinite && total > 0 ? min(range.upperBound, max(total, start + 0.2)) : range.upperBound)
    value.segments[index].sourceRange = start ... end
    setCaptions(value, recordUndo: recordUndo)
  }

  func deleteCaption(id: UUID) {
    var value = captions
    value.segments.removeAll { $0.id == id }
    setCaptions(value)
  }

  func clearCaptions() {
    var value = captions
    value.segments = []
    setCaptions(value)
  }

  // MARK: - Lookup

  /// The caption shown at a structural playhead time (preview).
  func captionSegment(atSequence time: TimeInterval) -> CaptionSegment? {
    guard !isGIF, let source = cursorSourceTime(atSequence: time) else { return nil }
    return VideoEditorCaptionResolver(captions: captions)
      .segment(atSource: source, rate: Double(previewSourceRate(atSequence: time)))
  }

  /// SRT or WebVTT text in output time (cuts dropped, speed applied).
  func subtitleText(vtt: Bool) -> String {
    let cues = VideoEditorCaptionResolver.outputCues(
      segments: captions.segments,
      playbackPlacements: playbackPlacements,
      sequenceMap: sequenceMap
    )
    let limit = captions.settings.maxCharsPerLine
    return vtt
      ? VideoEditorSubtitleWriter.vtt(cues, maxCharsPerLine: limit)
      : VideoEditorSubtitleWriter.srt(cues, maxCharsPerLine: limit)
  }

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
        let result = try await VideoEditorTranscriptService.shared.transcribe(
          asset: asset, roles: roles, locale: locale
        ) { progress in
          Task { @MainActor [weak self] in self?.setCaptionProgress(progress) }
        }
        try Task.checkCancellation()
        self?.finishCaptionGeneration(result: result, options: options)
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

  private func finishCaptionGeneration(result: TranscriptResult, options: VideoEditorCaptionSegmenterOptions) {
    guard captionTask != nil else { return }
    let segments = VideoEditorCaptionSegmenter.segment(result.words, options: options)
    if segments.isEmpty {
      captionNotice = L10n.VideoEditor.captionsNoSpeech
    } else {
      var value = captions
      value.segments = segments
      value.settings.isEnabled = true
      setCaptions(value)
      if !result.unrecognizedSpans.isEmpty {
        captionNotice = L10n.VideoEditor.captionsPartial(result.unrecognizedSpans.count)
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
    exportProgress = Float(min(max(fraction, 0), 1))
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
