//
//  RecordingMetadata.swift
//  Snapzy
//
//  Sidecar metadata for recordings that need editor-only context.
//

import CoreGraphics
import Foundation

struct RecordedMouseSample: Codable, Equatable {
  var time: TimeInterval
  var normalizedX: CGFloat
  var normalizedY: CGFloat
  var isInsideCapture: Bool

  var normalizedPoint: CGPoint {
    CGPoint(x: normalizedX, y: normalizedY)
  }
}

struct RecordingMetadata: Codable, Equatable {
  static let currentVersion = 1

  var version: Int
  var captureSize: CGSize
  var samplesPerSecond: Int
  var mouseSamples: [RecordedMouseSample]

  init(
    version: Int = RecordingMetadata.currentVersion,
    captureSize: CGSize,
    samplesPerSecond: Int,
    mouseSamples: [RecordedMouseSample]
  ) {
    self.version = version
    self.captureSize = captureSize
    self.samplesPerSecond = samplesPerSecond
    self.mouseSamples = mouseSamples
  }
}

@MainActor
enum RecordingMetadataStore {
  private static let sidecarExtension = "snapzy-recording.json"

  static func sidecarURL(for videoURL: URL) -> URL {
    videoURL
      .deletingPathExtension()
      .appendingPathExtension(sidecarExtension)
  }

  static func load(for videoURL: URL) -> RecordingMetadata? {
    let sidecarURL = sidecarURL(for: videoURL)
    return SandboxFileAccessManager.shared.withScopedAccess(to: sidecarURL.deletingLastPathComponent()) {
      guard FileManager.default.fileExists(atPath: sidecarURL.path),
            let data = try? Data(contentsOf: sidecarURL)
      else {
        return nil
      }

      return try? JSONDecoder().decode(RecordingMetadata.self, from: data)
    }
  }

  static func save(_ metadata: RecordingMetadata, for videoURL: URL) throws {
    let sidecarURL = sidecarURL(for: videoURL)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    let data = try encoder.encode(metadata)
    try SandboxFileAccessManager.shared.withScopedAccess(to: sidecarURL.deletingLastPathComponent()) {
      try data.write(to: sidecarURL, options: .atomic)
    }
  }

  static func delete(for videoURL: URL) throws {
    let sidecarURL = sidecarURL(for: videoURL)
    try SandboxFileAccessManager.shared.withScopedAccess(to: sidecarURL.deletingLastPathComponent()) {
      guard FileManager.default.fileExists(atPath: sidecarURL.path) else { return }
      try FileManager.default.removeItem(at: sidecarURL)
    }
  }
}
