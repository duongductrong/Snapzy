//
//  VideoEditorAgentToolbox+StudioScene.swift
//  Snapzy
//
//  What get_timeline reports about the Studio layers and captions: cursor and camera
//  only when they can be edited, captions once they exist. Times are timeline seconds.
//

import Foundation

extension VideoEditorAgentToolbox {
  // MARK: - Scene

  func studioCursorScene(_ state: VideoEditorState) -> VideoEditorAgentScene.Cursor? {
    guard state.hasEditableCursor else { return nil }
    let s = state.cursorSettings
    return .init(
      visible: s.isVisible, scale: Self.round(s.scale), smoothing: Self.round(s.smoothing),
      hideWhenIdle: s.hideWhenIdle, clickEffect: s.clickEffect.rawValue, clickSound: s.clickSound
    )
  }

  func studioCameraScene(_ state: VideoEditorState) -> VideoEditorAgentScene.Camera? {
    guard state.hasEditableCamera else { return nil }
    let s = state.cameraSettings
    let hidden = VideoEditorSourceTrackLayout.pieces(
      s.hiddenRanges.map { ($0.id, $0.start, $0.end) },
      placements: state.placements, duration: 1, width: 1, minimumWidth: 0
    ).map { [Self.round(Double($0.x)), Self.round(Double($0.x + $0.width))] }
    return .init(
      visible: s.isVisible, shape: s.shape, size: Self.round(s.size),
      center: [Self.round(s.center.x), Self.round(s.center.y)], mirrored: s.isMirrored, hidden: hidden
    )
  }

  func captionsScene(_ state: VideoEditorState) -> VideoEditorAgentScene.Captions? {
    let captions = state.captions
    guard !captions.isEmpty else { return nil }
    let items = captions.segments.prefix(VideoEditorAgentStudioTools.maximumListedCaptions).map { segment in
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
    return .init(
      showOnVideo: captions.settings.isEnabled,
      position: captions.settings.position.rawValue,
      textSize: Self.round(captions.settings.fontSize),
      count: captions.segments.count,
      items: Array(items)
    )
  }
}
