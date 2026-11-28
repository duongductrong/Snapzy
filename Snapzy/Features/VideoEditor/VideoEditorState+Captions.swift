//
//  VideoEditorState+Captions.swift
//  Snapzy
//
//  Captions: generate from speech (transcript service → segmenter), author manually or
//  import SRT/VTT, apply studio presets, edit with undo, preview lookup and SRT/VTT output.
//

import AVFoundation
import Foundation

extension VideoEditorState {
  /// Captions can be authored manually or imported on any non-GIF video.
  var canEditCaptions: Bool {
    !isGIF
  }

  /// Automatic speech transcription needs at least one audio track.
  var canGenerateCaptions: Bool {
    !isGIF && !audioTrackRoles.isEmpty
  }

  var isGeneratingCaptions: Bool {
    captionTask != nil
  }

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
    if appCode == current.language.languageCode?.identifier {
      return system
    }
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

  // MARK: - Editing & Presets

  func setCaptions(_ new: VideoEditorCaptions, recordUndo: Bool = true) {
    let old = captions
    guard new != old else { return }
    applyCaptions(new)
    if recordUndo {
      recordAction(.updateCaptions(old: old, new: new))
    }
  }

  /// One undo step for a slider drag or a text field edit that changed `captions` live.
  func commitCaptions(from old: VideoEditorCaptions) {
    guard old != captions else { return }
    recordAction(.updateCaptions(old: old, new: captions))
  }

  func applyCaptions(_ value: VideoEditorCaptions) {
    var value = value
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

  func applyCaptionPreset(_ preset: VideoEditorCaptionSettings.EditorialPreset) {
    var settings = captions.settings
    settings.isEnabled = true
    settings.apply(preset: preset)
    setCaptionSettings(settings)
  }

  /// Insert a manual subtitle segment at the current playhead on the primary recording
  /// (one Undo step), upgrading untouched legacy settings to `studioGlass` on first creation.
  @discardableResult
  func addManualCaptionAtPlayhead(text: String? = nil) -> CaptionSegment? {
    guard canEditCaptions else { return nil }
    let seqTime = max(0, CMTimeGetSeconds(currentTime))
    let totalSource = max(0.5, CMTimeGetSeconds(duration))

    let sourceStart: TimeInterval
    if let mapped = cursorSourceTime(atSequence: seqTime) {
      sourceStart = max(0, min(mapped, totalSource - 0.25))
    } else if let primaryPlacement = placements.first(where: { $0.clip.isPrimary }) {
      sourceStart = primaryPlacement.clip.sourceStart
    } else {
      return nil
    }

    // Avoid overlapping the next caption when possible; default to 2.4s duration.
    let nextStart = captions.segments
      .filter { $0.start > sourceStart + 0.22 }
      .map(\.start)
      .min()
    let maxEnd = min(totalSource, nextStart ?? (sourceStart + 2.4))
    let resolvedEnd = max(sourceStart + 0.3, min(totalSource, maxEnd))

    let resolvedText = (text?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
      ?? L10n.VideoEditor.captionsDefaultSampleText

    let segment = CaptionSegment(
      sourceRange: sourceStart ... resolvedEnd,
      text: resolvedText
    )

    var next = captions
    if next.segments.isEmpty, next.settings == .default {
      next.settings.apply(preset: .kineticPulse)
    }
    next.settings.isEnabled = true
    next.segments.append(segment)
    setCaptions(next)

    if let placement = placements.first(where: {
      $0.clip.isPrimary && sourceStart >= $0.clip.sourceStart && sourceStart < $0.clip.sourceEnd
    }) {
      let land = placement.sequenceTime(atSource: sourceStart) + 0.005
      seek(to: CMTime(seconds: land, preferredTimescale: 600))
    }
    captionNotice = nil
    return segment
  }

  /// Import `.srt` or `.vtt` subtitle cues into `captions.segments` as one Undo step.
  @discardableResult
  func importSubtitles(from url: URL) -> Int {
    guard canEditCaptions,
          let raw = try? String(contentsOf: url, encoding: .utf8)
    else { return 0 }
    let parsed = VideoEditorSubtitleWriter.parse(raw)
    guard !parsed.isEmpty else { return 0 }

    var next = captions
    if next.segments.isEmpty, next.settings == .default {
      next.settings.apply(preset: .kineticPulse)
    }
    next.settings.isEnabled = true
    next.segments = parsed
    setCaptions(next)
    captionNotice = nil
    return parsed.count
  }

  /// Seek to the start of the active (or first) subtitle and play so the user can
  /// preview entrance, word-by-word highlight, and exit motion immediately.
  func previewCaptionMotion() {
    guard !isGIF, !captions.segments.isEmpty else { return }
    let nowSeq = CMTimeGetSeconds(currentTime)
    let targetSegment = captionSegment(atSequence: nowSeq) ?? captions.segments.first
    guard let segment = targetSegment,
          let placement = placements.first(where: {
            $0.clip.isPrimary && segment.start < $0.clip.sourceEnd && segment.end > $0.clip.sourceStart
          })
    else { return }

    let clampedSource = max(placement.clip.sourceStart, segment.start)
    let startSeq = max(0, placement.sequenceTime(atSource: clampedSource))
    seek(to: CMTime(seconds: startSeq, preferredTimescale: 600))
    if !playbackState.isPlaying {
      play()
    }
  }

  func updateCaptionText(id: UUID, text: String, recordUndo: Bool = true) {
    var value = captions
    guard let index = value.segments.firstIndex(where: { $0.id == id }),
          value.segments[index].text != text else { return }
    value.segments[index].text = text
    value.segments[index].words = nil
    setCaptions(value, recordUndo: recordUndo)
  }

  /// New source range for a caption, clamped to at least 0.2 s and the recording.
  func updateCaptionRange(id: UUID, range: ClosedRange<TimeInterval>, recordUndo: Bool = true) {
    var value = captions
    guard let index = value.segments.firstIndex(where: { $0.id == id }) else { return }
    let total = CMTimeGetSeconds(duration)
    let hasTotal = total.isFinite && total > 0
    let maxStart = hasTotal ? max(0, total - 0.2) : range.lowerBound
    let start = min(max(0, range.lowerBound), maxStart)
    let rawEnd = max(start + 0.2, range.upperBound)
    let end = hasTotal ? min(rawEnd, max(total, start + 0.2)) : rawEnd
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

  /// The caption shown at a structural playhead time together with its mapped source time.
  func captionSegmentWithSourceTime(atSequence time: TimeInterval)
    -> (segment: CaptionSegment, sourceTime: TimeInterval)? {
    guard !isGIF, captions.settings.isEnabled, !captions.segments.isEmpty,
          let source = cursorSourceTime(atSequence: time)
    else { return nil }
    let resolver = cachedCaptionResolver ?? VideoEditorCaptionResolver(captions: captions)
    cachedCaptionResolver = resolver
    guard let seg = resolver.segment(atSource: source, rate: Double(previewSourceRate(atSequence: time))) else {
      return nil
    }
    return (seg, source)
  }

  /// The caption shown at a structural playhead time (preview).
  func captionSegment(atSequence time: TimeInterval) -> CaptionSegment? {
    captionSegmentWithSourceTime(atSequence: time)?.segment
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

private extension [CaptionSegment] {
  var isSortedByStart: Bool {
    zip(self, dropFirst()).allSatisfy { $0.start <= $1.start }
  }
}
