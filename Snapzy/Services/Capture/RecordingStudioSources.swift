//
//  RecordingStudioSources.swift
//  Snapzy
//
//  Metadata v6 pieces for Studio recordings and the sidecar kinds the metadata store
//  keeps next to recordings. Cursor data lives in `RecordingCursorCapture.swift`; the
//  camera payload is a placeholder phase 3 extends with `decodeIfPresent` fields.
//

import CoreGraphics
import Foundation

/// Camera recorded as a separate sidecar movie (Studio recording). The sidecar's
/// time 0 is the screen recording's time 0; pauses are cut the same way.
nonisolated struct RecordingCameraSource: Codable, Equatable, Sendable {
  /// File name inside the `CameraSources` sidecar directory.
  var fileName: String
  /// Camera frame size in pixels (unmirrored, as written).
  var naturalSize: CGSize
  /// The overlay showed the camera mirrored while recording.
  var isMirrored: Bool
  /// `RecordingCameraShape.rawValue` of the overlay at stop.
  var shape: String
  /// Overlay frame at stop, normalized to the capture rect, top-left origin.
  var normalizedFrame: CGRect
  /// Overlay frame size in points (corner radius is defined in points).
  var pointSize: CGSize
  /// Spans (recording time) with no camera frames, e.g. a disconnected camera.
  var gaps: [RecordingTimeRange]

  init(
    fileName: String,
    naturalSize: CGSize = .zero,
    isMirrored: Bool = false,
    shape: String = "rectangle",
    normalizedFrame: CGRect = .zero,
    pointSize: CGSize = .zero,
    gaps: [RecordingTimeRange] = []
  ) {
    self.fileName = fileName
    self.naturalSize = naturalSize
    self.isMirrored = isMirrored
    self.shape = shape
    self.normalizedFrame = normalizedFrame
    self.pointSize = pointSize
    self.gaps = gaps
  }

  private enum CodingKeys: String, CodingKey {
    case fileName, naturalSize, isMirrored, shape, normalizedFrame, pointSize, gaps
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    fileName = try c.decode(String.self, forKey: .fileName)
    naturalSize = try c.decodeIfPresent(CGSize.self, forKey: .naturalSize) ?? .zero
    isMirrored = try c.decodeIfPresent(Bool.self, forKey: .isMirrored) ?? false
    shape = try c.decodeIfPresent(String.self, forKey: .shape) ?? "rectangle"
    normalizedFrame = try c.decodeIfPresent(CGRect.self, forKey: .normalizedFrame) ?? .zero
    pointSize = try c.decodeIfPresent(CGSize.self, forKey: .pointSize) ?? .zero
    gaps = try c.decodeIfPresent([RecordingTimeRange].self, forKey: .gaps) ?? []
  }
}

nonisolated struct RecordingTimeRange: Codable, Equatable, Sendable {
  var start: TimeInterval
  var end: TimeInterval
}

/// Kinds of files the recording metadata store owns next to recording metadata.
nonisolated enum RecordingSidecarKind: String, CaseIterable, Sendable {
  /// Multi-track audio source movie (`RecordingMetadata.audioSourceURL`).
  case audio
  /// Separate camera movie (`RecordingMetadata.cameraSource`).
  case camera
  /// Per-recording folder of cursor images (`RecordingMetadata.cursorCapture`).
  case cursorImages
  /// Cursor-less original of a flattened Studio recording (`RecordingMetadata.studioSourceFileName`).
  case studioSource

  var folderName: String {
    switch self {
    case .audio: "AudioSources"
    case .camera: "CameraSources"
    case .cursorImages: "CursorImages"
    case .studioSource: "StudioSources"
    }
  }

  /// Extension used when the stored item has none; `nil` keeps it extension-less
  /// (directories).
  var defaultPathExtension: String? {
    switch self {
    case .audio, .camera, .studioSource: "mov"
    case .cursorImages: nil
    }
  }
}

nonisolated extension RecordingMetadata {
  /// Sidecar items this metadata references, as (kind, path relative to that kind's
  /// folder or absolute URL). The store resolves and validates them before deleting.
  var sidecarReferences: [RecordingSidecarReference] {
    var references: [RecordingSidecarReference] = []
    if let audioSourceURL {
      references.append(.absolute(.audio, audioSourceURL))
    }
    if let fileName = cameraSource?.fileName, !fileName.isEmpty {
      references.append(.named(.camera, fileName))
    }
    if let folder = cursorCapture?.imagesFolderName, !folder.isEmpty {
      references.append(.named(.cursorImages, folder))
    }
    if let fileName = studioSourceFileName, !fileName.isEmpty {
      references.append(.named(.studioSource, fileName))
    }
    return references
  }
}

nonisolated enum RecordingSidecarReference: Equatable {
  case absolute(RecordingSidecarKind, URL)
  case named(RecordingSidecarKind, String)

  var kind: RecordingSidecarKind {
    switch self {
    case .absolute(let kind, _), .named(let kind, _): kind
    }
  }

  /// Resolves to a URL strictly inside `kindRoot`, or `nil` for anything that would
  /// escape it (absolute paths elsewhere, `..`, nested separators in names).
  func resolvedURL(in kindRoot: URL) -> URL? {
    let candidate: URL
    switch self {
    case .absolute(_, let url):
      candidate = url
    case .named(_, let name):
      guard !name.contains("/"), name != ".", name != ".." else { return nil }
      candidate = kindRoot.appendingPathComponent(name)
    }
    let path = candidate.standardizedFileURL.resolvingSymlinksInPath().path
    let rootPath = kindRoot.standardizedFileURL.resolvingSymlinksInPath().path
    return path.hasPrefix(rootPath + "/") ? candidate : nil
  }
}
