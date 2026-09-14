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
struct VideoEditorSessionData: Equatable {
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
    isMuted: Bool = false
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
  }
}

/// JSON-safe edit fields. SwiftUI `Color` and the background enum are converted
/// using the same durable representation as Annotate sessions.
nonisolated struct PersistedVideoEditorEditState: Codable, Equatable {
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
      isMuted: isMuted
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
      isMuted: state.isMuted
    )
  }
}
