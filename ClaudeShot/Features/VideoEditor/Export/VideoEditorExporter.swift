//
//  VideoEditorExporter.swift
//  ClaudeShot
//
//  Video trimming and export functionality
//

import AVFoundation
import Foundation

/// Handles video trimming and export operations
@MainActor
enum VideoEditorExporter {

  // MARK: - Export Methods

  /// Export trimmed video to specified URL
  static func exportTrimmed(
    state: VideoEditorState,
    to outputURL: URL,
    progress: @escaping (Float) -> Void
  ) async throws {
    // If muted, export without audio
    if state.isMuted {
      try await exportVideoOnly(state: state, to: outputURL, progress: progress)
      return
    }

    let timeRange = CMTimeRange(start: state.trimStart, end: state.trimEnd)

    guard let exportSession = AVAssetExportSession(
      asset: state.asset,
      presetName: AVAssetExportPresetHighestQuality
    ) else {
      throw ExportError.sessionCreationFailed
    }

    // Remove existing file if present
    try? FileManager.default.removeItem(at: outputURL)

    exportSession.outputURL = outputURL
    exportSession.outputFileType = outputFileType(for: state.fileExtension)
    exportSession.timeRange = timeRange

    // Start progress monitoring
    let progressTask = Task {
      while !Task.isCancelled && exportSession.status == .exporting {
        progress(exportSession.progress)
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
      }
    }

    await exportSession.export()
    progressTask.cancel()

    guard exportSession.status == .completed else {
      throw exportSession.error ?? ExportError.exportFailed
    }
  }

  /// Export video without audio track
  private static func exportVideoOnly(
    state: VideoEditorState,
    to outputURL: URL,
    progress: @escaping (Float) -> Void
  ) async throws {
    let timeRange = CMTimeRange(start: state.trimStart, end: state.trimEnd)
    let composition = AVMutableComposition()

    // Add only video track
    guard let videoTrack = try await state.asset.loadTracks(withMediaType: .video).first else {
      throw ExportError.exportFailed
    }

    guard let compositionVideoTrack = composition.addMutableTrack(
      withMediaType: .video,
      preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
      throw ExportError.exportFailed
    }

    try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)

    // Copy video track transform
    let transform = try await videoTrack.load(.preferredTransform)
    compositionVideoTrack.preferredTransform = transform

    // Export composition
    guard let exportSession = AVAssetExportSession(
      asset: composition,
      presetName: AVAssetExportPresetHighestQuality
    ) else {
      throw ExportError.sessionCreationFailed
    }

    try? FileManager.default.removeItem(at: outputURL)
    exportSession.outputURL = outputURL
    exportSession.outputFileType = outputFileType(for: state.fileExtension)

    let progressTask = Task {
      while !Task.isCancelled && exportSession.status == .exporting {
        progress(exportSession.progress)
        try? await Task.sleep(nanoseconds: 100_000_000)
      }
    }

    await exportSession.export()
    progressTask.cancel()

    guard exportSession.status == .completed else {
      throw exportSession.error ?? ExportError.exportFailed
    }
  }

  /// Replace original file with trimmed version
  static func replaceOriginal(state: VideoEditorState, progress: @escaping (Float) -> Void) async throws {
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(state.fileExtension)

    try await exportTrimmed(state: state, to: tempURL, progress: progress)

    // Replace original with temp file
    let originalURL = state.sourceURL
    try FileManager.default.removeItem(at: originalURL)
    try FileManager.default.moveItem(at: tempURL, to: originalURL)
  }

  /// Save trimmed video as a copy
  static func saveAsCopy(state: VideoEditorState, progress: @escaping (Float) -> Void) async throws -> URL {
    let copyURL = generateCopyURL(from: state.sourceURL)
    try await exportTrimmed(state: state, to: copyURL, progress: progress)
    return copyURL
  }

  // MARK: - Helper Methods

  /// Generate copy URL with _trimmed suffix
  static func generateCopyURL(from originalURL: URL) -> URL {
    let directory = originalURL.deletingLastPathComponent()
    let baseName = originalURL.deletingPathExtension().lastPathComponent
    let ext = originalURL.pathExtension
    var copyURL = directory.appendingPathComponent("\(baseName)_trimmed.\(ext)")

    // Handle filename collision
    var counter = 1
    while FileManager.default.fileExists(atPath: copyURL.path) {
      copyURL = directory.appendingPathComponent("\(baseName)_trimmed_\(counter).\(ext)")
      counter += 1
    }

    return copyURL
  }

  private static func outputFileType(for extension: String) -> AVFileType {
    switch `extension`.lowercased() {
    case "mp4":
      return .mp4
    case "mov":
      return .mov
    default:
      return .mp4
    }
  }

  // MARK: - Errors

  enum ExportError: Error, LocalizedError {
    case sessionCreationFailed
    case exportFailed

    var errorDescription: String? {
      switch self {
      case .sessionCreationFailed:
        return "Failed to create export session"
      case .exportFailed:
        return "Video export failed"
      }
    }
  }
}
