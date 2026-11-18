//
//  VideoEditorState+Cursor.swift
//  Snapzy
//
//  Studio cursor layer: availability, preview time mapping and the export recipe.
//

import CoreMedia
import Foundation

extension VideoEditorState {
  /// The recording captured the cursor as data (Studio recording), so it can be edited.
  var hasEditableCursor: Bool {
    guard let metadata = recordingMetadata else { return false }
    return metadata.cursorCapture != nil && !metadata.isCursorBaked
  }

  /// Recording time under a structural timeline time; `nil` over inserted clips or
  /// trimmed-out footage (no cursor data there).
  func cursorSourceTime(atSequence time: TimeInterval) -> TimeInterval? {
    guard let placement = TimelineSequence.activePlacement(at: time, in: placements),
          placement.clip.isPrimary
    else { return nil }
    return placement.sourceTime(at: time)
  }

  /// Studio layers for an export with the given output → sequence mapping. GIF output
  /// and recordings without editable cursor data get an empty recipe.
  func makeStudioRecipe(
    sequenceMap: TimelineSequenceMap,
    playbackPlacements: [TimelineSequence.Placement]
  ) -> VideoEditorStudioRecipe {
    guard !isGIF, let metadata = recordingMetadata else { return .empty }
    let mapping = VideoEditorSourceTimeMapping(sequenceMap: sequenceMap, playbackPlacements: playbackPlacements)
    var layers: [any VideoEditorStudioLayer] = []
    if hasEditableCursor,
       let cursor = cursorSprites.makeLayer(metadata: metadata, settings: cursorSettings, mapping: mapping),
       cursor.isActive {
      layers.append(cursor)
    }
    if hasEditableCamera, let source = metadata.cameraSource, cameraSettings.isVisible {
      layers.append(VideoEditorCameraLayer(settings: cameraSettings, source: source, mapping: mapping))
    }
    return VideoEditorStudioRecipe(layers: layers)
  }

  /// The recording has a camera sidecar on disk, so the camera can be edited.
  var hasEditableCamera: Bool {
    cameraSourceURL != nil && recordingMetadata?.cameraSource != nil
  }

  /// Output times for the Studio click sound; empty when it is off or unavailable.
  func clickSoundOutputTimes(
    sequenceMap: TimelineSequenceMap,
    playbackPlacements: [TimelineSequence.Placement]
  ) -> [TimeInterval] {
    guard !isGIF, hasEditableCursor, cursorSettings.clickSound,
          let clicks = recordingMetadata?.cursorCapture?.clicks
    else { return [] }
    return VideoEditorClickSound.outputTimes(
      clickSourceTimes: clicks.filter { $0.phase == .down }.map(\.time),
      playbackPlacements: playbackPlacements,
      sequenceMap: sequenceMap
    )
  }

  /// Recording seconds per wall-clock second at a structural playhead time while
  /// playing (the speed segment's rate, else 1). Drives the camera preview player.
  func previewSourceRate(atSequence time: TimeInterval) -> Float {
    let segment = speedSegments.first {
      $0.isEnabled && time >= $0.startTime && time < $0.startTime + $0.duration
    }
    return Float(segment?.rate ?? 1)
  }
}
