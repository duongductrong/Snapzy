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

  /// Speech language: the panel's choice, else the remembered caption language, else the
  /// app language (with the Mac's region when they match), else the Mac's locale.
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

  static func defaultCaptionLocale(defaults: UserDefaults = .standard) -> Locale {
    if let saved = defaults.string(forKey: PreferencesKeys.videoEditorCaptionLanguage), !saved.isEmpty {
      return Locale(identifier: saved)
    }
    return defaultCaptionLocale(appLanguage: AppLanguageManager.shared.activeEffectiveLanguageIdentifier)
  }

  /// Remembers the language picked in the captions panel for the next video (`nil` = automatic).
  static func rememberCaptionLanguage(_ identifier: String?, defaults: UserDefaults = .standard) {
    if let identifier, !identifier.isEmpty {
      defaults.set(identifier, forKey: PreferencesKeys.videoEditorCaptionLanguage)
    } else {
      defaults.removeObject(forKey: PreferencesKeys.videoEditorCaptionLanguage)
    }
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
    // Sorting always copies the (shared) storage, which also defeats the identity fast
    // path of every `captions` comparison downstream. Slider and drag ticks already
    // arrive in order, so sort only when needed.
    if !value.segments.isSortedByStart {
      value.segments.sort { $0.start < $1.start }
    }
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
    guard !isGIF, captions.settings.isEnabled, !captions.segments.isEmpty,
          let source = cursorSourceTime(atSequence: time)
    else { return nil }
    let resolver = cachedCaptionResolver ?? VideoEditorCaptionResolver(captions: captions)
    cachedCaptionResolver = resolver
    return resolver.segment(atSource: source, rate: Double(previewSourceRate(atSequence: time)))
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
}

private extension Array where Element == CaptionSegment {
  var isSortedByStart: Bool {
    zip(self, dropFirst()).allSatisfy { $0.start <= $1.start }
  }
}
