import AVFoundation
import Foundation

/// One immutable authoring recipe for the entire export, including async asset loads.
/// Source camera paths are resolved for this recipe before the exporter consumes it.
@MainActor
struct VideoEditorExportSnapshot {
  let sourceURL: URL
  let asset: AVAsset
  let fileExtension: String
  let duration: CMTime
  let naturalSize: CGSize
  let trimStart: CMTime
  let trimEnd: CMTime
  let trimmedDuration: CMTime
  let clips: [TimelineClip]
  let zoomSegments: [ZoomSegment]
  let speedSegments: [SpeedSegment]
  let recordingMetadata: RecordingMetadata?
  let exportSettings: ExportSettings
  let audioTrackRoles: [VideoEditorAudioTrackRole]
  let zoomTransitionDuration: TimeInterval
  let motionBlurSettings: VideoEditorMotionBlurSettings
  let backgroundStyle: BackgroundStyle
  let backgroundPadding: CGFloat
  let backgroundCornerRadius: CGFloat
  let placements: [TimelineSequence.Placement]
  let playbackPlacements: [TimelineSequence.Placement]
  let sequenceMap: TimelineSequenceMap
  private let clipAssets: [UUID: AVAsset]
  var autoFocusPaths: [UUID: [AutoFocusCameraSample]] = [:]
  /// Studio layers resolved for this export. Empty until cursor/camera/caption phases
  /// populate it; empty keeps the pre-Studio export routing byte-for-byte.
  var studioRecipe: VideoEditorStudioRecipe = .empty
  /// Studio click sound: output times of clicks (empty = no click lane) and volume.
  var clickSoundTimes: [TimeInterval] = []
  var clickSoundVolume: Float = 0
  /// Studio camera sidecar read as an auxiliary track when the camera layer is active.
  var cameraSourceURL: URL?

  init(state: VideoEditorState) {
    sourceURL = state.sourceURL
    asset = state.asset
    fileExtension = state.fileExtension
    duration = state.duration
    naturalSize = state.naturalSize
    trimStart = state.trimStart
    trimEnd = state.trimEnd
    trimmedDuration = state.trimmedDuration
    clips = state.clips
    zoomSegments = state.zoomSegments
    speedSegments = state.speedSegments
    recordingMetadata = state.recordingMetadata
    exportSettings = state.exportSettings
    audioTrackRoles = state.audioTrackRoles
    zoomTransitionDuration = state.zoomTransitionDuration
    motionBlurSettings = state.motionBlurSettings
    backgroundStyle = state.backgroundStyle
    backgroundPadding = state.backgroundPadding
    backgroundCornerRadius = state.backgroundCornerRadius
    placements = TimelineSequence.layout(clips)
    playbackPlacements = TimelineSequence.playableLayout(clips)
    sequenceMap = TimelineSequenceMap(clips: clips, speedSegments: speedSegments)
    clipAssets = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, state.clipAsset(for: $0)) })
  }

  var sequenceDuration: TimeInterval { sequenceMap.sequenceDuration }
  var hasSpeedSegments: Bool { speedSegments.contains { $0.isEnabled && $0.rate != 1 } }
  var hasInsertedClips: Bool { clips.contains { !$0.isPrimary } }
  var hasSequenceEdits: Bool { clips.count > 1 || hasInsertedClips }

  func clipAsset(for clip: TimelineClip) -> AVAsset {
    // All assets are captured before any await; never ask the changing editor again.
    clipAssets[clip.id] ?? asset
  }

  func projectToPlaybackSequence(timelineRange: ClosedRange<TimeInterval>) -> [ClosedRange<TimeInterval>] {
    TimelineSequence.project(timelineRange: timelineRange, from: placements, to: playbackPlacements)
  }

  func autoFocusPath(for segment: ZoomSegment) -> [AutoFocusCameraSample] {
    autoFocusPaths[segment.id] ?? []
  }
}
