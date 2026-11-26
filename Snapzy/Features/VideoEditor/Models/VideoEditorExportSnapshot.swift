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
  let addedAudioClips: [AudioTimelineClip]
  let textOverlays: [VideoEditorTextOverlay]
  let usesIndependentAudioPlayback: Bool
  let primaryAudioSourceURL: URL
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
    usesIndependentAudioPlayback = state.usesIndependentAudioPlayback
    primaryAudioSourceURL = VideoEditorState.editorAssetURL(for: state.sourceURL, metadata: state.recordingMetadata)
    let mutedLanes = state.mutedAudioLanes
    addedAudioClips = usesIndependentAudioPlayback
      ? state.audioClips.filter { !$0.isMuted && !mutedLanes.contains($0.trackIndex) }
      : state.audioClips.filter { !$0.isPrimary && !$0.isMuted && !mutedLanes.contains($0.trackIndex) }
    textOverlays = state.textOverlays.filter {
      $0.isEnabled && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
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
    let laid = TimelineSequence.layout(clips)
    placements = laid
    let preserveGaps = clips.contains { $0.leadingGap > 0.01 }
    if preserveGaps {
      let gapAware = laid.map { placement in
        TimelineSequence.Placement(
          clip: placement.clip,
          index: placement.index,
          start: placement.activeStart,
          end: placement.activeEnd,
          sourceAxisStart: placement.clip.sourceStart,
          sourceAxisEnd: placement.clip.sourceEnd
        )
      }
      let gapDuration = gapAware.last?.end ?? 0
      playbackPlacements = gapAware
      sequenceMap = TimelineSequenceMap(
        timelinePlacements: laid,
        playablePlacements: gapAware,
        sequenceDuration: gapDuration,
        speedSegments: speedSegments
      )
    } else {
      playbackPlacements = TimelineSequence.playableLayout(clips)
      sequenceMap = TimelineSequenceMap(clips: clips, speedSegments: speedSegments)
    }
    clipAssets = Dictionary(
      clips.map { ($0.id, state.clipAsset(for: $0)) },
      uniquingKeysWith: { first, _ in first }
    )
  }

  var sequenceDuration: TimeInterval {
    sequenceMap.sequenceDuration
  }

  var hasSpeedSegments: Bool {
    speedSegments.contains { $0.isEnabled && $0.rate != 1 }
  }

  var hasInsertedClips: Bool {
    clips.contains { !$0.isPrimary }
  }

  var hasVideoGaps: Bool {
    clips.contains { $0.leadingGap > 0.01 }
  }

  var hasTextOverlays: Bool {
    !textOverlays.isEmpty
  }

  var hasActiveTransitions: Bool {
    clips.dropFirst().contains { $0.leadingTransition?.isActive == true }
  }

  var hasDetachedAudioClips: Bool {
    clips.contains(where: \.isAudioDetached)
  }

  var hasSequenceEdits: Bool {
    clips.count > 1 || hasInsertedClips || hasVideoGaps || hasActiveTransitions || hasDetachedAudioClips
  }

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
