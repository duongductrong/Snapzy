//
//  VideoEditorAgentToolbox+Studio.swift
//  Snapzy
//
//  Agent tools for the Studio layers: set_cursor and set_camera, plus the notes that
//  tell the model when the camera covers a zoom target or the captions.
//  Hidden-camera stretches are stored in source time; the model sees timeline time.
//

import CoreGraphics
import Foundation

extension VideoEditorAgentToolbox {
  private func invalid(_ detail: String) -> VideoEditorAgentToolError { .invalidArguments(detail) }

  // MARK: - Cursor

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
    if let delay = args.idleDelay {
      let range = VideoEditorCursorSettings.idleDelayRange
      settings.idleDelay = min(max(delay, range.lowerBound), range.upperBound)
    }
    if let arrow = args.alwaysArrow { settings.alwaysUseArrow = arrow }
    if let raw = args.clickEffect {
      guard let effect = VideoEditorCursorClickEffect(rawValue: raw.lowercased()) else {
        throw invalid("click_effect must be one of \(VideoEditorCursorClickEffect.allCases.map(\.rawValue).joined(separator: ", ")).")
      }
      settings.clickEffect = effect
    }
    if let raw = args.clickColor {
      // Keep the effect's see-through look unless the color spells out its own opacity.
      settings.clickColor = try VideoEditorAgentStudioTools.color(raw, name: "click_color", alpha: settings.clickColor.alpha)
    }
    if let sound = args.clickSound { settings.clickSound = sound }
    if let volume = args.clickVolume { settings.clickSoundVolume = min(max(volume, 0), 1) }
    guard settings != state.cursorSettings else { throw invalid("Give at least one setting to change.") }
    state.setCursorSettings(settings)
    return .success([:])
  }

  // MARK: - Camera

  func setCamera(_ args: VideoEditorAgentCameraArguments, state: VideoEditorState) throws -> AgentToolResult {
    guard state.hasEditableCamera, let source = state.recordingMetadata?.cameraSource else {
      throw VideoEditorAgentToolError.unavailable(
        "This recording has no separate camera track (or the camera is baked in). Tell the user."
      )
    }
    // Same as the Camera panel's reset button: the recorded layout, shown everywhere.
    var settings = args.reset == true ? VideoEditorCameraSettings.recorded(source) : state.cameraSettings
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
      let key = raw.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
      guard let preset = VideoEditorAgentStudioTools.cameraPositions.first(where: { $0.name == key }) else {
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
    if let references = args.showHidden {
      try showHidden(references, in: &settings)
    }
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
    var hiddenForZooms = 0
    if args.hideDuringZooms == true {
      let ranges = state.zoomSegments.filter(\.isEnabled).flatMap { zoom in
        sourceRanges(forTimeline: zoom.startTime ... zoom.endTime, state)
      }
      guard !ranges.isEmpty else {
        throw invalid("There are no zoom blocks over the recording to hide the camera for.")
      }
      for range in ranges {
        settings = settings.addingHiddenRange(VideoEditorCameraHiddenRange(start: range.lowerBound, end: range.upperBound))
      }
      hiddenForZooms = ranges.count
    }
    guard settings != state.cameraSettings else { throw invalid("Give at least one setting to change.") }
    state.setCameraSettings(settings)

    var payload: [String: Any] = [:]
    if hiddenForZooms > 0 { payload["hidden_for_zooms"] = hiddenForZooms }
    if args.position != nil || args.center != nil || args.size != nil || args.visible == true || args.reset == true,
       let note = captionCameraOverlapNote(state) {
      payload["note"] = note
    }
    return .success(payload)
  }

  private func showHidden(_ references: [String], in settings: inout VideoEditorCameraSettings) throws {
    if references.contains(where: { $0.lowercased() == "all" }) {
      settings.hiddenRanges = []
      return
    }
    for reference in references {
      guard let id = lookup(.hidden, reference), settings.hiddenRanges.contains(where: { $0.id == id }) else {
        throw VideoEditorAgentToolError.notFound("hidden camera stretch '\(reference)'. get_timeline lists them under camera.hidden")
      }
      settings.hiddenRanges.removeAll { $0.id == id }
    }
  }

  // MARK: - Time mapping

  /// Timeline time → recording time; inserted videos and trimmed footage have none.
  func sourceTime(_ value: VideoEditorAgentTime, _ state: VideoEditorState, name: String) throws -> TimeInterval {
    let t = try time(value, state, name: name)
    guard let source = state.cursorSourceTime(atSequence: t) else {
      throw invalid("\(name) is not over the recording's playing footage.")
    }
    return source
  }

  /// The recording footage a timeline range plays, one source range per primary clip piece.
  func sourceRanges(forTimeline range: ClosedRange<TimeInterval>, _ state: VideoEditorState) -> [ClosedRange<TimeInterval>] {
    state.placements.compactMap { placement in
      guard placement.clip.isPrimary else { return nil }
      let low = max(range.lowerBound, placement.activeStart)
      let high = min(range.upperBound, placement.activeEnd)
      guard high - low >= VideoEditorCameraHiddenRange.minimumDuration else { return nil }
      return placement.sourceTime(at: low) ... placement.sourceTime(at: high)
    }
  }

  // MARK: - Overlap notes

  /// Camera rect in video space, 0…1 from the top left; nil when it doesn't show.
  func visibleCameraRect(_ state: VideoEditorState, atTimeline time: TimeInterval? = nil) -> CGRect? {
    guard state.hasEditableCamera, state.cameraSettings.isVisible, let source = state.recordingMetadata?.cameraSource else {
      return nil
    }
    if let time, let sourceTime = state.cursorSourceTime(atSequence: time),
       state.cameraSettings.hiddenRanges.contains(where: { $0.start <= sourceTime && sourceTime < $0.end }) {
      return nil
    }
    let size = state.naturalSize
    guard size.width > 0, size.height > 0 else { return nil }
    let rect = state.cameraSettings.rect(in: CGRect(origin: .zero, size: size), aspect: source.overlayAspect)
    return CGRect(x: rect.minX / size.width, y: rect.minY / size.height, width: rect.width / size.width, height: rect.height / size.height)
  }

  /// A fixed zoom center under the camera bubble: the zoomed-in detail sits behind it.
  func zoomCameraNote(_ segment: ZoomSegment, _ state: VideoEditorState) -> String? {
    guard segment.zoomType != .auto, segment.isEnabled,
          let camera = visibleCameraRect(state, atTimeline: (segment.startTime + segment.endTime) / 2),
          camera.insetBy(dx: -0.03, dy: -0.03).contains(segment.zoomCenter)
    else { return nil }
    return "The camera covers this zoom's center. Move the camera (set_camera position) or hide it during zooms "
      + "(set_camera hide_during_zooms), unless the user wants it there."
  }

  /// Camera bubble over the band the captions draw in.
  func captionCameraOverlapNote(_ state: VideoEditorState) -> String? {
    let captions = state.captions
    guard !captions.isEmpty, captions.settings.isEnabled, let camera = visibleCameraRect(state) else { return nil }
    let settings = captions.settings
    let size = state.naturalSize
    guard size.width > 0, size.height > 0 else { return nil }
    // Rough box of a full caption: centered, about half an em per character, padded.
    let height = settings.fontSize * 1.35 * CGFloat(max(settings.maxLines, 1)) + settings.fontSize * 0.6
    let width = min(0.9, (CGFloat(settings.maxCharsPerLine) * 0.52 + 1) * settings.fontSize * size.height / size.width)
    let band = CGRect(
      x: (1 - width) / 2,
      y: settings.position == .bottom ? 1 - settings.margin - height : settings.margin,
      width: width,
      height: height
    )
    // Grazing a corner of the longest possible line isn't worth a note.
    let overlap = camera.intersection(band)
    guard !overlap.isNull, overlap.width > 0.04, overlap.height > 0.02 else { return nil }
    return "The camera overlaps the captions. Move the camera (set_camera position) or the captions (edit_caption position)."
  }
}
