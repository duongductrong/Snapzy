//
//  RecordingStudioSources.swift
//  Snapzy
//
//  Metadata v6 pieces for Studio recordings and the sidecar kinds the metadata store
//  keeps next to recordings. Cursor/camera payloads are placeholders: phase 1 (cursor)
//  and phase 3 (camera) extend them with `decodeIfPresent` fields.
//

import CoreGraphics
import Foundation

/// Cursor appearance/click data captured by a Studio recording (filled in by phase 1).
nonisolated struct RecordingCursorCapture: Codable, Equatable {
  /// Folder inside the `CursorImages` sidecar directory holding this recording's
  /// cursor PNGs. `nil` while no image was captured.
  var imagesFolderName: String?

  init(imagesFolderName: String? = nil) {
    self.imagesFolderName = imagesFolderName
  }
}

/// Camera recorded as a separate sidecar movie (filled in by phase 3).
nonisolated struct RecordingCameraSource: Codable, Equatable {
  /// File name inside the `CameraSources` sidecar directory.
  var fileName: String

  init(fileName: String) {
    self.fileName = fileName
  }
}

/// Kinds of files the recording metadata store owns next to recording metadata.
nonisolated enum RecordingSidecarKind: String, CaseIterable, Sendable {
  /// Multi-track audio source movie (`RecordingMetadata.audioSourceURL`).
  case audio
  /// Separate camera movie (`RecordingMetadata.cameraSource`).
  case camera
  /// Per-recording folder of cursor images (`RecordingMetadata.cursorCapture`).
  case cursorImages

  var folderName: String {
    switch self {
    case .audio: "AudioSources"
    case .camera: "CameraSources"
    case .cursorImages: "CursorImages"
    }
  }

  /// Extension used when the stored item has none; `nil` keeps it extension-less
  /// (directories).
  var defaultPathExtension: String? {
    switch self {
    case .audio, .camera: "mov"
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
