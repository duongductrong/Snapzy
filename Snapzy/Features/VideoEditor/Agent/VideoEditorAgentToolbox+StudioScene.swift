//
//  VideoEditorAgentToolbox+StudioScene.swift
//  Snapzy
//
//  What get_timeline reports about the Studio layers and captions: cursor and camera
//  only when they can be edited, captions once they exist. Times are timeline seconds.
//

import CoreGraphics
import Foundation

extension VideoEditorAgentToolbox {
  // MARK: - Scene

  /// Cursor or camera were recorded apart, so the agent can restyle them.
  func isStudioRecording(_ state: VideoEditorState) -> Bool {
    state.hasEditableCursor || state.hasEditableCamera
  }

  func studioCursorScene(_ state: VideoEditorState) -> VideoEditorAgentScene.Cursor? {
    guard state.hasEditableCursor else { return nil }
    let s = state.cursorSettings
    return .init(
      visible: s.isVisible, scale: Self.round(s.scale), smoothing: Self.round(s.smoothing),
      hideWhenIdle: s.hideWhenIdle, clickEffect: s.clickEffect.rawValue, clickSound: s.clickSound,
      clicks: recordedClickDowns(state).count
    )
  }

  func studioCameraScene(_ state: VideoEditorState) -> VideoEditorAgentScene.Camera? {
    guard state.hasEditableCamera else { return nil }
    let s = state.cameraSettings
    let hidden = VideoEditorSourceTrackLayout.pieces(
      s.hiddenRanges.map { ($0.id, $0.start, $0.end) },
      placements: state.placements, duration: 1, width: 1, minimumWidth: 0
    ).sorted { $0.x < $1.x }.map { piece in
      VideoEditorAgentScene.HiddenStretch(
        id: reference(.hidden, for: piece.rangeID),
        start: Self.round(Double(piece.x)),
        end: Self.round(Double(piece.x + piece.width))
      )
    }
    return .init(
      visible: s.isVisible, shape: s.shape, size: Self.round(s.size),
      center: [Self.round(s.center.x), Self.round(s.center.y)], mirrored: s.isMirrored, hidden: hidden
    )
  }

  func captionsScene(_ state: VideoEditorState) -> VideoEditorAgentScene.Captions? {
    let captions = state.captions
    guard !captions.isEmpty else { return nil }
    let items = captions.segments.prefix(VideoEditorAgentStudioTools.maximumListedCaptions).map { captionItem($0, state) }
    let settings = captions.settings
    return .init(
      showOnVideo: settings.isEnabled,
      position: settings.position.rawValue,
      textSize: Self.round(settings.fontSize),
      bold: settings.isBold,
      textColor: Self.hex(settings.textColor),
      backgroundOpacity: Self.round(settings.backgroundOpacity),
      hideWhenFast: settings.hideDuringFastSpeed,
      language: settings.languageIdentifier,
      count: captions.segments.count,
      items: Array(items),
      font: settings.customFontId,
      fontWeight: settings.fontWeight,
      italic: settings.isItalic
    )
  }

  func availableFontsList() -> [String] {
    let manager = VideoEditorFontManager.shared
    var result: [String] = [VideoEditorFontResolver.defaultFamilyId]
    result.append(contentsOf: manager.downloadedCatalogIds.sorted())
    result.append(contentsOf: manager.importedFonts.map(\.id))
    return result
  }

  /// A caption with its timeline span: the first playing piece of the recording it falls on.
  func captionItem(_ segment: CaptionSegment, _ state: VideoEditorState) -> VideoEditorAgentScene.Caption {
    let placement = state.placements.first {
      $0.clip.isPrimary && segment.start < $0.clip.sourceEnd && segment.end > $0.clip.sourceStart
    }
    return VideoEditorAgentScene.Caption(
      id: reference(.caption, for: segment.id),
      start: placement.map { Self.round($0.sequenceTime(atSource: max(segment.start, $0.clip.sourceStart))) },
      end: placement.map { Self.round($0.sequenceTime(atSource: min(segment.end, $0.clip.sourceEnd))) },
      text: segment.text
    )
  }

  /// Mouse-down clicks of a Studio recording, in recording time.
  func recordedClickDowns(_ state: VideoEditorState) -> [RecordedClick] {
    (state.recordingMetadata?.cursorCapture?.clicks ?? []).filter { $0.phase == .down }
  }

  static func hex(_ color: VideoEditorRGBAColor) -> String {
    func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", byte(color.red), byte(color.green), byte(color.blue))
  }
}
