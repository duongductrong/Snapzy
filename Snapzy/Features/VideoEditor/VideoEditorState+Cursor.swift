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
    guard !isGIF, hasEditableCursor, let metadata = recordingMetadata,
          let layer = cursorSprites.makeLayer(
            metadata: metadata,
            settings: cursorSettings,
            mapping: VideoEditorSourceTimeMapping(sequenceMap: sequenceMap, playbackPlacements: playbackPlacements)
          ),
          layer.isActive
    else { return .empty }
    return VideoEditorStudioRecipe(layers: [layer])
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
}
