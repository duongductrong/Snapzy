//
//  VideoEditorState+Camera.swift
//  Snapzy
//
//  Hidden-camera ranges of a Studio recording: add at the playhead, re-time, remove.
//  Stored in `cameraSettings` (source time), so they undo with the camera settings
//  and are saved with the session.
//

import CoreMedia
import Foundation

extension VideoEditorState {
  /// The Camera timeline track shows once the recording has an editable camera.
  var showsCameraTrack: Bool { !isGIF && hasEditableCamera }

  /// Hides the camera for `VideoEditorCameraHiddenRange.defaultDuration` from a structural
  /// timeline time (playhead by default). No-op over inserted clips or trimmed footage.
  @discardableResult
  func hideCamera(atSequence time: TimeInterval? = nil) -> UUID? {
    let sequence = time ?? CMTimeGetSeconds(currentTime)
    guard hasEditableCamera,
          let placement = TimelineSequence.activePlacement(at: sequence, in: placements),
          placement.clip.isPrimary,
          let start = cursorSourceTime(atSequence: sequence)
    else { return nil }
    let end = min(start + VideoEditorCameraHiddenRange.defaultDuration, placement.clip.sourceEnd)
    guard end - start >= VideoEditorCameraHiddenRange.minimumDuration else { return nil }
    let range = VideoEditorCameraHiddenRange(start: start, end: end)
    let updated = cameraSettings.addingHiddenRange(range)
    setCameraSettings(updated)
    return updated.hiddenRanges.first { $0.start <= start && $0.end >= end }?.id
  }

  func updateCameraHiddenRange(id: UUID, start: TimeInterval, end: TimeInterval, recordUndo: Bool = true) {
    var settings = cameraSettings
    guard let index = settings.hiddenRanges.firstIndex(where: { $0.id == id }) else { return }
    let lower = max(0, start)
    settings.hiddenRanges[index].start = lower
    settings.hiddenRanges[index].end = max(end, lower + VideoEditorCameraHiddenRange.minimumDuration)
    settings.hiddenRanges.sort { $0.start < $1.start }
    setCameraSettings(settings, recordUndo: recordUndo)
  }

  func removeCameraHiddenRange(id: UUID) {
    var settings = cameraSettings
    settings.hiddenRanges.removeAll { $0.id == id }
    setCameraSettings(settings)
  }
}
