//
//  VideoEditorAgentToolbox+Captions.swift
//  Snapzy
//
//  Caption tools: generate_captions, edit_caption, get_captions, add_caption,
//  remove_captions, replace_in_captions and translate_captions. Captions are stored in
//  recording (source) time; the model reads and writes timeline time.
//

import Foundation

extension VideoEditorAgentToolbox {
  private func invalid(_ detail: String) -> VideoEditorAgentToolError { .invalidArguments(detail) }

  // MARK: - Generate & edit

  func generateCaptions(_ args: VideoEditorAgentCaptionArguments, state: VideoEditorState) async throws -> AgentToolResult {
    guard state.canGenerateCaptions else {
      throw VideoEditorAgentToolError.unavailable("This video has no audio, so there is nothing to caption.")
    }
    let locale = args.language.map { Self.speechLocale($0) } ?? state.captionLocale
    let result = try await VideoEditorState.transcribeCaptions(
      asset: state.asset, roles: state.audioTrackRoles, locale: locale, options: state.captions.settings.segmenterOptions
    )
    try Task.checkCancellation()
    guard !result.segments.isEmpty else { throw VideoEditorAgentToolError.notFound("speech in this video") }
    var settings = state.captions.settings
    settings.languageIdentifier = args.language == nil ? settings.languageIdentifier : locale.identifier
    var captions = VideoEditorCaptions(segments: result.segments, settings: settings)
    captions.settings.isEnabled = args.showOnVideo ?? true
    state.setCaptions(captions)
    var payload: [String: Any] = ["language": locale.identifier, "captions": result.segments.count]
    if result.unrecognized > 0 { payload["unrecognized_parts"] = result.unrecognized }
    if state.hasInsertedClips { payload["inserted_videos"] = "Inserted videos are not captioned." }
    if let note = captionCameraOverlapNote(state) { payload["note"] = note }
    return .success(payload)
  }

  func editCaption(_ args: VideoEditorAgentCaptionEditArguments, state: VideoEditorState) throws -> AgentToolResult {
    var captions = state.captions
    if let show = args.showOnVideo { captions.settings.isEnabled = show }
    if let raw = args.position {
      guard let position = VideoEditorCaptionSettings.Position(rawValue: raw.lowercased()) else {
        throw invalid("position must be bottom or top.")
      }
      captions.settings.position = position
    }
    if let size = args.textSize {
      let range = VideoEditorCaptionSettings.fontSizeRange
      captions.settings.fontSize = min(max(CGFloat(size), range.lowerBound), range.upperBound)
    }
    if let fontRaw = args.font {
      captions.settings.customFontId = try VideoEditorAgentStudioTools.resolveFontId(fontRaw)
    }
    if let weight = args.fontWeight {
      let clampedWeight = min(max(weight, 400), 900)
      captions.settings.fontWeight = clampedWeight
      captions.settings.isBold = clampedWeight >= 700
    }
    if let bold = args.bold {
      captions.settings.isBold = bold
      if bold, captions.settings.fontWeight < 700 {
        captions.settings.fontWeight = 700
      } else if !bold, captions.settings.fontWeight >= 700 {
        captions.settings.fontWeight = 500
      }
    }
    if let italic = args.italic {
      captions.settings.isItalic = italic
    }
    if let raw = args.textColor {
      // Opaque, like the Captions panel's color well.
      captions.settings.textColor = try VideoEditorAgentStudioTools.color(raw, name: "text_color", alpha: 1)
    }
    if let opacity = args.backgroundOpacity { captions.settings.backgroundOpacity = CGFloat(min(max(opacity, 0), 1)) }
    if let fast = args.hideWhenFast { captions.settings.hideDuringFastSpeed = fast }
    if let reference = args.id {
      guard let id = lookup(.caption, reference), let index = captions.segments.firstIndex(where: { $0.id == id }) else {
        throw VideoEditorAgentToolError.notFound("caption '\(reference)'. Call get_captions for caption ids")
      }
      if let text = args.text?.trimmingCharacters(in: .whitespacesAndNewlines) {
        if text.isEmpty {
          captions.segments.remove(at: index)
          state.setCaptions(captions)
          return .success(["deleted": reference])
        }
        captions.segments[index].text = text
        captions.segments[index].words = nil
      }
      let current = captions.segments[index].sourceRange
      let start = try args.start.map { try sourceTime($0, state, name: "start") } ?? current.lowerBound
      let end = try args.end.map { try sourceTime($0, state, name: "end") } ?? current.upperBound
      guard end - start >= VideoEditorAgentStudioTools.minimumCaptionDuration else {
        throw invalid("end must be at least \(VideoEditorAgentStudioTools.minimumCaptionDuration)s after start.")
      }
      captions.segments[index].sourceRange = start ... end
    } else if args.text != nil || args.start != nil || args.end != nil {
      throw invalid("id is required to change a caption's text or timing.")
    }
    guard captions != state.captions else { throw invalid("Give at least one change.") }
    state.setCaptions(captions)
    var payload: [String: Any] = [:]
    if args.showOnVideo == true || args.position != nil || args.textSize != nil, let note = captionCameraOverlapNote(state) {
      payload["note"] = note
    }
    return .success(payload)
  }

  // MARK: - List, add, remove

  func getCaptions(_ args: VideoEditorAgentCaptionRangeArguments, state: VideoEditorState) throws -> AgentToolResult {
    guard !state.captions.isEmpty else {
      throw VideoEditorAgentToolError.unavailable("There are no captions yet. generate_captions makes them from the speech.")
    }
    let lower = try args.start.map { try time($0, state, name: "start") } ?? 0
    let upper = try args.end.map { try time($0, state, name: "end") } ?? .greatestFiniteMagnitude
    guard upper > lower else { throw invalid("end must be after start.") }

    let items = state.captions.segments.map { captionItem($0, state) }
    let onTimeline = items.compactMap { item -> (item: VideoEditorAgentScene.Caption, start: Double, end: Double)? in
      guard let start = item.start, let end = item.end else { return nil }
      return (item, start, end)
    }
    let matching = onTimeline.filter { $0.end > lower && $0.start < upper }.sorted { $0.start < $1.start }
    let page = matching.prefix(VideoEditorAgentStudioTools.maximumCaptionPage)
    var payload: [String: Any] = [
      "count": state.captions.segments.count,
      "captions": page.map { ["id": $0.item.id, "start": $0.start, "end": $0.end, "text": $0.item.text] as [String: Any] },
    ]
    if matching.count > page.count, let last = page.last { payload["next_start"] = last.end }
    let offTimeline = items.count - onTimeline.count
    if offTimeline > 0 { payload["trimmed_out"] = offTimeline }
    return .success(payload)
  }

  func addCaption(_ args: VideoEditorAgentAddCaptionArguments, state: VideoEditorState) throws -> AgentToolResult {
    let text = args.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw invalid("text is empty.") }
    let startTime = try time(args.start, state, name: "start")
    let endTime = try time(args.end, state, name: "end")
    guard let placement = TimelineSequence.activePlacement(at: startTime, in: state.placements),
          placement.clip.isPrimary
    else {
      throw invalid("start is not over the recording's playing footage (inserted videos and trimmed parts can't have captions).")
    }
    guard endTime <= placement.activeEnd + 0.01 else {
      throw invalid("end must be inside the same clip as start (it plays until \(Self.clock(placement.activeEnd))).")
    }
    let start = placement.sourceTime(at: startTime)
    let end = placement.sourceTime(at: min(endTime, placement.activeEnd))
    guard end - start >= VideoEditorAgentStudioTools.minimumCaptionDuration else {
      throw invalid("end must be at least \(VideoEditorAgentStudioTools.minimumCaptionDuration)s after start.")
    }
    var captions = state.captions
    if let other = captions.segments.first(where: { $0.start < end && $0.end > start }) {
      throw invalid(
        "it overlaps caption \(reference(.caption, for: other.id)) (\"\(other.text.prefix(40))\"). "
          + "Change that one with edit_caption, or pick a free time."
      )
    }
    let segment = CaptionSegment(sourceRange: start ... end, text: text)
    captions.segments.append(segment)
    state.setCaptions(captions)
    return .success([
      "id": reference(.caption, for: segment.id),
      "start": Self.round(startTime),
      "end": Self.round(min(endTime, placement.activeEnd)),
    ])
  }

  func removeCaptions(_ args: VideoEditorAgentCaptionIDsArguments, state: VideoEditorState) throws -> AgentToolResult {
    guard !state.captions.isEmpty else { throw VideoEditorAgentToolError.unavailable("There are no captions to remove.") }
    let cleaned = args.ids
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !cleaned.isEmpty else { throw invalid("ids is empty. Give caption ids like [\"t3\"], or [\"all\"].") }
    var captions = state.captions
    if cleaned.contains(where: { $0.lowercased() == "all" }) {
      let count = captions.segments.count
      captions.segments = []
      state.setCaptions(captions)
      return .success(["removed": count])
    }
    var removed: [String] = []
    for reference in cleaned {
      guard let id = lookup(.caption, reference), captions.segments.contains(where: { $0.id == id }) else {
        throw VideoEditorAgentToolError.notFound("caption '\(reference)'. Call get_captions for caption ids")
      }
      captions.segments.removeAll { $0.id == id }
      removed.append(reference.lowercased())
    }
    state.setCaptions(captions)
    return .success(["removed": removed.count])
  }

  // MARK: - Replace

  func replaceInCaptions(_ args: VideoEditorAgentReplaceCaptionArguments, state: VideoEditorState) throws -> AgentToolResult {
    guard !state.captions.isEmpty else { throw VideoEditorAgentToolError.unavailable("There are no captions yet.") }
    let find = args.find.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !find.isEmpty else { throw invalid("find is empty.") }
    let regex = try Self.captionSearch(find, matchCase: args.matchCase ?? false, wholeWord: args.wholeWord ?? true)
    let template = NSRegularExpression.escapedTemplate(for: args.replace)

    var captions = state.captions
    var changed = 0
    var emptied: [UUID] = []
    var examples: [String] = []
    for index in captions.segments.indices {
      let original = captions.segments[index].text
      let range = NSRange(original.startIndex..., in: original)
      guard regex.firstMatch(in: original, range: range) != nil else { continue }
      let replaced = regex.stringByReplacingMatches(in: original, range: range, withTemplate: template)
        .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard replaced != original else { continue }
      changed += 1
      if replaced.isEmpty {
        emptied.append(captions.segments[index].id)
      } else {
        captions.segments[index].text = replaced
        captions.segments[index].words = nil
        if examples.count < 3 { examples.append(replaced) }
      }
    }
    guard changed > 0 else { throw VideoEditorAgentToolError.notFound("'\(find)' in any caption") }
    captions.segments.removeAll { emptied.contains($0.id) }
    state.setCaptions(captions)
    var payload: [String: Any] = ["changed": changed, "examples": examples]
    if !emptied.isEmpty { payload["deleted_empty"] = emptied.count }
    return .success(payload)
  }

  /// Literal search; word boundaries only on sides that start or end with a letter or digit.
  nonisolated static func captionSearch(_ find: String, matchCase: Bool, wholeWord: Bool) throws -> NSRegularExpression {
    var pattern = NSRegularExpression.escapedPattern(for: find)
    if wholeWord {
      let isWordCharacter: (Character?) -> Bool = { $0.map { $0.isLetter || $0.isNumber } ?? false }
      if isWordCharacter(find.first) { pattern = #"(?<![\p{L}\p{N}])"# + pattern }
      if isWordCharacter(find.last) { pattern += #"(?![\p{L}\p{N}])"# }
    }
    return try NSRegularExpression(pattern: pattern, options: matchCase ? [] : [.caseInsensitive])
  }

  // MARK: - Translate

  func translateCaptions(_ args: VideoEditorAgentTranslateCaptionArguments, state: VideoEditorState) async throws -> AgentToolResult {
    guard !state.captions.isEmpty else {
      throw VideoEditorAgentToolError.unavailable("There are no captions yet. generate_captions makes them from the speech first.")
    }
    guard let targetID = VideoEditorAgentStudioTools.translationTarget(args.language),
          let target = TranslationLanguage.language(for: targetID)
    else {
      throw invalid("language must be one of \(VideoEditorAgentStudioTools.translationTargets.joined(separator: ", ")).")
    }
    let original = state.captions.segments
    let texts = original.map(\.text)
    // Read the language off the text: after a translation (or edits) the stored speech
    // language no longer describes the captions, and it must stay the speech language.
    let source = TranslationSourceLanguageDetector.detect(texts.joined(separator: "\n"))
      ?? state.captions.settings.languageIdentifier
    if let source, Self.languageCode(source) == Self.languageCode(target.identifier) {
      throw invalid("the captions are already in \(target.englishName).")
    }
    let route = TranslationEngineResolver().resolve()
    let output: BlockTranslationOutput
    do {
      output = try await state.captionTranslator.translate(texts, sourceLanguage: source, target: target, route: route)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw VideoEditorAgentToolError.unavailable(
        VideoEditorCaptionTranslator.message(for: error)
          ?? "The translation failed (\(error.localizedDescription)). Tell the user."
      )
    }
    try Task.checkCancellation()

    // Map back by id: nothing else edits captions during a run, but stay safe if it did.
    let translations = Dictionary(uniqueKeysWithValues: zip(original.map(\.id), output.texts))
    var captions = state.captions
    var translated = 0
    for index in captions.segments.indices {
      guard let text = translations[captions.segments[index].id] ?? nil, text != captions.segments[index].text else { continue }
      captions.segments[index].text = text
      captions.segments[index].words = nil
      translated += 1
    }
    guard translated > 0 else {
      throw VideoEditorAgentToolError.unavailable("The translation came back empty. Tell the user.")
    }
    state.setCaptions(captions)
    var payload: [String: Any] = ["language": target.identifier, "translated": translated]
    if translated < captions.segments.count { payload["untranslated"] = captions.segments.count - translated }
    if case .remote(let model) = route { payload["engine"] = model.name } else { payload["engine"] = "Apple Translation (on this Mac)" }
    return .success(payload)
  }

  nonisolated static func languageCode(_ identifier: String) -> String {
    let lower = identifier.lowercased().replacingOccurrences(of: "_", with: "-")
    if lower.hasPrefix("zh") {
      return ["hant", "tw", "hk", "mo"].contains { lower.contains($0) } ? "zh-hant" : "zh-hans"
    }
    return String(lower.split(separator: "-").first ?? Substring(lower))
  }
}
