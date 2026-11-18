//
//  VideoEditorAgentToolbox+Studio.swift
//  Snapzy
//
//  Agent tools for the Studio layers and captions: set_cursor, set_camera,
//  generate_captions, edit_caption, plus what get_timeline reports about them.
//  Captions are stored in source time; the model sees and edits timeline time.
//

import Foundation

extension VideoEditorAgentToolbox {
  private func invalid(_ detail: String) -> VideoEditorAgentToolError { .invalidArguments(detail) }

  // MARK: - Cursor & camera

  func setCursor(_ args: VideoEditorAgentCursorArguments, state: VideoEditorState) throws -> AgentToolResult {
    guard state.hasEditableCursor else {
      throw VideoEditorAgentToolError.unavailable(
        "This recording has the cursor baked in; only Studio recordings can change it. Tell the user."
      )
    }
    var settings = state.cursorSettings
    if let visible = args.visible { settings.isVisible = visible }
    if let scale = args.scale {
      let range = VideoEditorCursorSettings.scaleRange
      settings.scale = min(max(CGFloat(scale), range.lowerBound), range.upperBound)
    }
    if let smoothing = args.smoothing { settings.smoothing = min(max(smoothing, 0), 1) }
    if let idle = args.hideWhenIdle { settings.hideWhenIdle = idle }
    if let raw = args.clickEffect {
      guard let effect = VideoEditorCursorClickEffect(rawValue: raw.lowercased()) else {
        throw invalid("click_effect must be one of \(VideoEditorCursorClickEffect.allCases.map(\.rawValue).joined(separator: ", ")).")
      }
      settings.clickEffect = effect
    }
    if let sound = args.clickSound { settings.clickSound = sound }
    guard settings != state.cursorSettings else { throw invalid("Give at least one setting to change.") }
    state.setCursorSettings(settings)
    return .success([:])
  }

  func setCamera(_ args: VideoEditorAgentCameraArguments, state: VideoEditorState) throws -> AgentToolResult {
    guard state.hasEditableCamera else {
      throw VideoEditorAgentToolError.unavailable(
        "This recording has no separate camera track (or the camera is baked in). Tell the user."
      )
    }
    var settings = state.cameraSettings
    if let visible = args.visible { settings.isVisible = visible }
    if let raw = args.shape {
      guard let shape = RecordingCameraShape(rawValue: raw.lowercased()) else {
        throw invalid("shape must be one of \(RecordingCameraShape.allCases.map(\.rawValue).joined(separator: ", ")).")
      }
      settings.shape = shape.rawValue
    }
    if let size = args.size {
      let range = VideoEditorCameraSettings.sizeRange
      settings.size = min(max(CGFloat(size), range.lowerBound), range.upperBound)
    }
    if let raw = args.position {
      guard let preset = VideoEditorAgentStudioTools.cameraPositions.first(where: { $0.name == raw.lowercased() }) else {
        throw invalid("position must be one of \(VideoEditorAgentStudioTools.cameraPositions.map(\.name).joined(separator: ", ")).")
      }
      settings.center = preset.center
    }
    if let center = args.center {
      guard center.count == 2, center.allSatisfy({ (0 ... 1).contains($0) }) else {
        throw invalid("center must be [x, y] with values from 0 to 1.")
      }
      settings.center = CGPoint(x: center[0], y: center[1])
    }
    if let mirrored = args.mirrored { settings.isMirrored = mirrored }
    if args.clearHidden == true { settings.hiddenRanges = [] }
    if args.hideStart != nil || args.hideEnd != nil {
      guard let rawStart = args.hideStart, let rawEnd = args.hideEnd else {
        throw invalid("Give both hide_start and hide_end.")
      }
      let start = try sourceTime(rawStart, state, name: "hide_start")
      let end = try sourceTime(rawEnd, state, name: "hide_end")
      guard end - start >= VideoEditorCameraHiddenRange.minimumDuration else {
        throw invalid("hide_end must be after hide_start, inside the same clip.")
      }
      settings = settings.addingHiddenRange(VideoEditorCameraHiddenRange(start: start, end: end))
    }
    guard settings != state.cameraSettings else { throw invalid("Give at least one setting to change.") }
    state.setCameraSettings(settings)
    return .success([:])
  }

  // MARK: - Captions

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
    if let reference = args.id {
      guard let id = lookup(.caption, reference), let index = captions.segments.firstIndex(where: { $0.id == id }) else {
        throw VideoEditorAgentToolError.notFound("caption '\(reference)'. Call get_timeline for caption ids")
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
      guard end - start >= 0.2 else { throw invalid("end must be at least 0.2s after start.") }
      captions.segments[index].sourceRange = start ... end
    } else if args.text != nil || args.start != nil || args.end != nil {
      throw invalid("id is required to change a caption's text or timing.")
    }
    guard captions != state.captions else { throw invalid("Give at least one change.") }
    state.setCaptions(captions)
    return .success([:])
  }

  /// Timeline time → recording time; inserted videos and trimmed footage have none.
  private func sourceTime(_ value: VideoEditorAgentTime, _ state: VideoEditorState, name: String) throws -> TimeInterval {
    let t = try time(value, state, name: name)
    guard let source = state.cursorSourceTime(atSequence: t) else {
      throw invalid("\(name) is not over the recording's playing footage.")
    }
    return source
  }
}
