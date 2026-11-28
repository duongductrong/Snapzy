//
//  VideoEditorSessionData.swift
//  Snapzy
//
//  In-memory and persisted representations of the non-destructive video editor
//  authoring session.
//

import CoreGraphics
import Foundation

/// The editable recipe that must survive a rendered Video Editor save.
///
/// `sourceSnapshotURL` points to the unrendered master kept by
/// `VideoEditorSessionStore`. The current capture/destination URL is deliberately
/// not used as the authoring source after the first commit because it already
/// contains the previous render.
nonisolated struct VideoEditorSessionData: Equatable {
  var sourceSnapshotURL: URL
  var recordingMetadata: RecordingMetadata?
  var clips: [TimelineClip]
  var zoomSegments: [ZoomSegment]
  var speedSegments: [SpeedSegment]
  var backgroundStyle: BackgroundStyle
  var backgroundPadding: CGFloat
  var backgroundShadowIntensity: CGFloat
  var backgroundCornerRadius: CGFloat
  var backgroundAlignment: ImageAlignment
  var backgroundAspectRatio: AspectRatioOption
  var exportSettings: ExportSettings
  var isMuted: Bool
  /// Studio layers; `nil` = not saved (older sessions), keep the editor defaults.
  var cursorSettings: VideoEditorCursorSettings?
  var cameraSettings: VideoEditorCameraSettings?
  var captions: VideoEditorCaptions?
  var motionBlurSettings: VideoEditorMotionBlurSettings?

  init(
    sourceSnapshotURL: URL,
    recordingMetadata: RecordingMetadata? = nil,
    clips: [TimelineClip] = [],
    zoomSegments: [ZoomSegment] = [],
    speedSegments: [SpeedSegment] = [],
    backgroundStyle: BackgroundStyle = .none,
    backgroundPadding: CGFloat = 0,
    backgroundShadowIntensity: CGFloat = 0,
    backgroundCornerRadius: CGFloat = 0,
    backgroundAlignment: ImageAlignment = .center,
    backgroundAspectRatio: AspectRatioOption = .auto,
    exportSettings: ExportSettings = .init(),
    isMuted: Bool = false,
    cursorSettings: VideoEditorCursorSettings? = nil,
    cameraSettings: VideoEditorCameraSettings? = nil,
    captions: VideoEditorCaptions? = nil,
    motionBlurSettings: VideoEditorMotionBlurSettings? = nil
  ) {
    self.sourceSnapshotURL = sourceSnapshotURL
    self.recordingMetadata = recordingMetadata
    self.clips = clips
    self.zoomSegments = zoomSegments
    self.speedSegments = speedSegments
    self.backgroundStyle = backgroundStyle
    self.backgroundPadding = backgroundPadding
    self.backgroundShadowIntensity = backgroundShadowIntensity
    self.backgroundCornerRadius = backgroundCornerRadius
    self.backgroundAlignment = backgroundAlignment
    self.backgroundAspectRatio = backgroundAspectRatio
    self.exportSettings = exportSettings
    self.isMuted = isMuted
    self.cursorSettings = cursorSettings
    self.cameraSettings = cameraSettings
    self.captions = captions
    self.motionBlurSettings = motionBlurSettings
  }
}

/// JSON-safe edit fields. SwiftUI `Color` and the background enum are converted
/// using the same durable representation as Annotate sessions.
nonisolated struct PersistedVideoEditorEditState: Codable, Equatable {
  static let maxDecodedItems: Int = 2_000

  var clips: [TimelineClip]
  var zoomSegments: [ZoomSegment]
  var speedSegments: [SpeedSegment]
  var backgroundStyle: CodableBackgroundStyle
  var backgroundPadding: CGFloat
  var backgroundShadowIntensity: CGFloat
  var backgroundCornerRadius: CGFloat
  var backgroundAlignment: String
  var backgroundAspectRatio: String
  var exportSettings: ExportSettings
  var isMuted: Bool
  // Added after schema 1 shipped: optional, so older manifests still decode
  // (synthesized Codable uses decodeIfPresent) and the schema is not bumped.
  var cursorSettings: VideoEditorCursorSettings?
  var cameraSettings: VideoEditorCameraSettings?
  var captions: VideoEditorCaptions?
  var motionBlurSettings: VideoEditorMotionBlurSettings?

  private enum CodingKeys: String, CodingKey {
    case clips, zoomSegments, speedSegments, backgroundStyle
    case backgroundPadding, backgroundShadowIntensity, backgroundCornerRadius
    case backgroundAlignment, backgroundAspectRatio, exportSettings, isMuted
    case cursorSettings, cameraSettings, captions, motionBlurSettings
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let rawClips = try c.decode([TimelineClip].self, forKey: .clips)
    clips = Self.deduplicateClips(Array(rawClips.prefix(Self.maxDecodedItems)))
    let rawZooms = try c.decode([ZoomSegment].self, forKey: .zoomSegments)
    zoomSegments = Self.deduplicateZooms(Array(rawZooms.prefix(Self.maxDecodedItems)))
    let rawSpeeds = try c.decode([SpeedSegment].self, forKey: .speedSegments)
    speedSegments = Self.deduplicateSpeeds(Array(rawSpeeds.prefix(Self.maxDecodedItems)))
    backgroundStyle = try c.decode(CodableBackgroundStyle.self, forKey: .backgroundStyle)
    let rawPad = (try? c.decode(CGFloat.self, forKey: .backgroundPadding)) ?? 0
    backgroundPadding = rawPad.isFinite ? min(500, max(0, rawPad)) : 0
    let rawShadow = (try? c.decode(CGFloat.self, forKey: .backgroundShadowIntensity)) ?? 0
    backgroundShadowIntensity = rawShadow.isFinite ? min(1, max(0, rawShadow)) : 0
    let rawRadius = (try? c.decode(CGFloat.self, forKey: .backgroundCornerRadius)) ?? 0
    backgroundCornerRadius = rawRadius.isFinite ? min(500, max(0, rawRadius)) : 0
    backgroundAlignment = try c.decode(String.self, forKey: .backgroundAlignment)
    backgroundAspectRatio = try c.decode(String.self, forKey: .backgroundAspectRatio)
    exportSettings = try c.decode(ExportSettings.self, forKey: .exportSettings)
    isMuted = try c.decode(Bool.self, forKey: .isMuted)
    cursorSettings = try c.decodeIfPresent(VideoEditorCursorSettings.self, forKey: .cursorSettings)
    cameraSettings = try c.decodeIfPresent(VideoEditorCameraSettings.self, forKey: .cameraSettings)
    captions = try c.decodeIfPresent(VideoEditorCaptions.self, forKey: .captions)
    motionBlurSettings = try c.decodeIfPresent(VideoEditorMotionBlurSettings.self, forKey: .motionBlurSettings)
  }

  private static func deduplicateClips(_ items: [TimelineClip]) -> [TimelineClip] {
    var seen: Set<UUID> = []
    return items.map { item in
      guard !seen.contains(item.id) else {
        let freshId = UUID()
        seen.insert(freshId)
        return TimelineClip(
          id: freshId,
          source: item.source,
          sourceDuration: item.sourceDuration,
          sourceStart: item.sourceStart,
          sourceEnd: item.sourceEnd,
          slotStart: item.slotStart,
          slotEnd: item.slotEnd
        )
      }
      seen.insert(item.id)
      return item
    }
  }

  private static func deduplicateZooms(_ items: [ZoomSegment]) -> [ZoomSegment] {
    var seen: Set<UUID> = []
    return items.map { item in
      guard !seen.contains(item.id) else {
        let freshId = UUID()
        seen.insert(freshId)
        return ZoomSegment(
          id: freshId,
          startTime: item.startTime,
          duration: item.duration,
          zoomLevel: item.zoomLevel,
          zoomCenter: item.zoomCenter,
          zoomType: item.zoomType,
          followSpeed: item.followSpeed,
          focusMargin: item.focusMargin,
          isEnabled: item.isEnabled,
          smartKeyframes: item.smartKeyframes
        )
      }
      seen.insert(item.id)
      return item
    }
  }

  private static func deduplicateSpeeds(_ items: [SpeedSegment]) -> [SpeedSegment] {
    var seen: Set<UUID> = []
    return items.map { item in
      guard !seen.contains(item.id) else {
        let freshId = UUID()
        seen.insert(freshId)
        return SpeedSegment(
          id: freshId,
          startTime: item.startTime,
          duration: item.duration,
          rate: item.rate,
          isEnabled: item.isEnabled
        )
      }
      seen.insert(item.id)
      return item
    }
  }

  init(sessionData: VideoEditorSessionData) {
    clips = sessionData.clips
    zoomSegments = sessionData.zoomSegments
    speedSegments = sessionData.speedSegments
    backgroundStyle = CodableBackgroundStyle(from: sessionData.backgroundStyle)
      ?? CodableBackgroundStyle(from: .none)!
    backgroundPadding = sessionData.backgroundPadding
    backgroundShadowIntensity = sessionData.backgroundShadowIntensity
    backgroundCornerRadius = sessionData.backgroundCornerRadius
    backgroundAlignment = sessionData.backgroundAlignment.rawValue
    backgroundAspectRatio = sessionData.backgroundAspectRatio.rawValue
    exportSettings = sessionData.exportSettings
    isMuted = sessionData.isMuted
    cursorSettings = sessionData.cursorSettings
    cameraSettings = sessionData.cameraSettings
    captions = sessionData.captions
    motionBlurSettings = sessionData.motionBlurSettings
  }

  func sessionData(
    sourceSnapshotURL: URL,
    recordingMetadata: RecordingMetadata?
  ) -> VideoEditorSessionData {
    VideoEditorSessionData(
      sourceSnapshotURL: sourceSnapshotURL,
      recordingMetadata: recordingMetadata,
      clips: clips,
      zoomSegments: zoomSegments,
      speedSegments: speedSegments,
      backgroundStyle: backgroundStyle.toBackgroundStyle(),
      backgroundPadding: backgroundPadding,
      backgroundShadowIntensity: backgroundShadowIntensity,
      backgroundCornerRadius: backgroundCornerRadius,
      backgroundAlignment: ImageAlignment(rawValue: backgroundAlignment) ?? .center,
      backgroundAspectRatio: AspectRatioOption(rawValue: backgroundAspectRatio) ?? .auto,
      exportSettings: exportSettings,
      isMuted: isMuted,
      cursorSettings: cursorSettings,
      cameraSettings: cameraSettings,
      captions: captions,
      motionBlurSettings: motionBlurSettings
    )
  }
}

/// Versioned manifest for a committed editor session.
nonisolated struct PersistedVideoEditorSession: Codable {
  static let currentSchemaVersion = 1

  var schemaVersion: Int
  var sourceFilePath: String
  var sourceFilePathHash: String
  var sourceSignature: PersistedFileSignature
  var sourceSnapshotFileName: String
  var recordingMetadata: RecordingMetadata?
  var editState: PersistedVideoEditorEditState
  var createdAt: Date
  var updatedAt: Date

  init(
    sessionData: VideoEditorSessionData,
    sourceFilePath: String,
    sourceFilePathHash: String,
    sourceSignature: PersistedFileSignature,
    sourceSnapshotFileName: String,
    createdAt: Date,
    updatedAt: Date = Date()
  ) {
    schemaVersion = Self.currentSchemaVersion
    self.sourceFilePath = sourceFilePath
    self.sourceFilePathHash = sourceFilePathHash
    self.sourceSignature = sourceSignature
    self.sourceSnapshotFileName = sourceSnapshotFileName
    recordingMetadata = sessionData.recordingMetadata
    editState = PersistedVideoEditorEditState(sessionData: sessionData)
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  func sessionData(sourceSnapshotURL: URL) -> VideoEditorSessionData {
    var metadata = recordingMetadata
    // The recording's editor source is packaged beside the manifest. Rebinding
    // this URL keeps Smart Camera and multitrack-audio restores self-contained
    // even after the original recording metadata association is removed.
    if metadata?.audioSourceURL != nil {
      metadata?.audioSourceURL = sourceSnapshotURL
    }
    return editState.sessionData(
      sourceSnapshotURL: sourceSnapshotURL,
      recordingMetadata: metadata
    )
  }
}

extension VideoEditorSessionData {
  @MainActor
  static func snapshot(
    from state: VideoEditorState,
    sourceSnapshotURL: URL
  ) -> VideoEditorSessionData {
    VideoEditorSessionData(
      sourceSnapshotURL: sourceSnapshotURL,
      recordingMetadata: state.recordingMetadata,
      clips: state.clips,
      zoomSegments: state.zoomSegments,
      speedSegments: state.speedSegments,
      backgroundStyle: state.backgroundStyle,
      backgroundPadding: state.backgroundPadding,
      backgroundShadowIntensity: state.backgroundShadowIntensity,
      backgroundCornerRadius: state.backgroundCornerRadius,
      backgroundAlignment: state.backgroundAlignment,
      backgroundAspectRatio: state.backgroundAspectRatio,
      exportSettings: state.exportSettings,
      isMuted: state.isMuted,
      cursorSettings: state.hasEditableCursor ? state.cursorSettings : nil,
      cameraSettings: state.hasEditableCamera ? state.cameraSettings : nil,
      captions: state.captions.isEmpty ? nil : state.captions,
      motionBlurSettings: state.motionBlurSettings
    )
  }
}
