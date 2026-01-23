//
//  VideoEditorExporter.swift
//  ClaudeShot
//
//  Video trimming, zoom effects, and export functionality
//

import AVFoundation
import Foundation

/// Handles video trimming and export operations
@MainActor
enum VideoEditorExporter {

  // MARK: - Export Methods

  /// Export trimmed video to specified URL (with zoom effects if present)
  static func exportTrimmed(
    state: VideoEditorState,
    to outputURL: URL,
    progress: @escaping (Float) -> Void
  ) async throws {
    let hasZooms = state.zoomSegments.contains { $0.isEnabled }

    // If has zooms, use composition-based export
    if hasZooms {
      try await exportWithZooms(state: state, to: outputURL, progress: progress)
      return
    }

    // If muted, export without audio
    if state.isMuted {
      try await exportVideoOnly(state: state, to: outputURL, progress: progress)
      return
    }

    // Standard export without zooms
    try await exportStandard(state: state, to: outputURL, progress: progress)
  }

  /// Standard export without zoom effects
  private static func exportStandard(
    state: VideoEditorState,
    to outputURL: URL,
    progress: @escaping (Float) -> Void
  ) async throws {
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

  /// Export with zoom effects applied
  private static func exportWithZooms(
    state: VideoEditorState,
    to outputURL: URL,
    progress: @escaping (Float) -> Void
  ) async throws {
    print("🔍 [ZoomExport] Starting export with zooms")
    print("🔍 [ZoomExport] Output URL: \(outputURL)")
    print("🔍 [ZoomExport] Video duration: \(CMTimeGetSeconds(state.duration))s")
    print("🔍 [ZoomExport] Trim range: \(CMTimeGetSeconds(state.trimStart))s - \(CMTimeGetSeconds(state.trimEnd))s")
    print("🔍 [ZoomExport] Trimmed duration: \(CMTimeGetSeconds(state.trimmedDuration))s")
    print("🔍 [ZoomExport] Natural size: \(state.naturalSize)")
    print("🔍 [ZoomExport] Total zoom segments: \(state.zoomSegments.count)")

    let timeRange = CMTimeRange(start: state.trimStart, end: state.trimEnd)
    let trimStartSeconds = CMTimeGetSeconds(state.trimStart)

    // Adjust zoom times relative to trim start
    let adjustedZooms = state.zoomSegments.map { segment -> ZoomSegment in
      var adjusted = segment
      adjusted.startTime = segment.startTime - trimStartSeconds
      return adjusted
    }.filter { $0.startTime + $0.duration > 0 && $0.startTime < CMTimeGetSeconds(state.trimmedDuration) }

    print("🔍 [ZoomExport] Adjusted zooms count: \(adjustedZooms.count)")
    for (index, zoom) in adjustedZooms.enumerated() {
      print("🔍 [ZoomExport] Zoom[\(index)]: start=\(zoom.startTime)s, duration=\(zoom.duration)s, level=\(zoom.zoomLevel)x, enabled=\(zoom.isEnabled)")
    }

    // Create composition
    let composition = AVMutableComposition()
    print("🔍 [ZoomExport] Created AVMutableComposition")

    // Add video track
    guard let sourceVideoTrack = try await state.asset.loadTracks(withMediaType: .video).first else {
      print("❌ [ZoomExport] ERROR: No video track found in source asset")
      throw ExportError.exportFailed
    }
    print("🔍 [ZoomExport] Source video track ID: \(sourceVideoTrack.trackID)")

    guard let compositionVideoTrack = composition.addMutableTrack(
      withMediaType: .video,
      preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
      print("❌ [ZoomExport] ERROR: Failed to add video track to composition")
      throw ExportError.exportFailed
    }
    print("🔍 [ZoomExport] Composition video track ID: \(compositionVideoTrack.trackID)")

    do {
      try compositionVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)
      print("🔍 [ZoomExport] Inserted video time range successfully")
    } catch {
      print("❌ [ZoomExport] ERROR inserting video time range: \(error)")
      throw error
    }

    // Copy video track transform
    let transform = try await sourceVideoTrack.load(.preferredTransform)
    compositionVideoTrack.preferredTransform = transform
    print("🔍 [ZoomExport] Applied video transform: \(transform)")

    // Add audio track if not muted
    if !state.isMuted {
      if let sourceAudioTrack = try await state.asset.loadTracks(withMediaType: .audio).first {
        if let compositionAudioTrack = composition.addMutableTrack(
          withMediaType: .audio,
          preferredTrackID: kCMPersistentTrackID_Invalid
        ) {
          try? compositionAudioTrack.insertTimeRange(timeRange, of: sourceAudioTrack, at: .zero)
          print("🔍 [ZoomExport] Added audio track")
        }
      } else {
        print("🔍 [ZoomExport] No audio track in source")
      }
    } else {
      print("🔍 [ZoomExport] Audio muted, skipping audio track")
    }

    // Create zoom compositor
    print("🔍 [ZoomExport] Creating ZoomCompositor with renderSize: \(state.naturalSize)")
    let zoomCompositor = ZoomCompositor(
      zooms: adjustedZooms,
      renderSize: state.naturalSize
    )

    let compositionTimeRange = CMTimeRange(start: .zero, duration: state.trimmedDuration)
    print("🔍 [ZoomExport] Composition time range: start=\(CMTimeGetSeconds(compositionTimeRange.start))s, duration=\(CMTimeGetSeconds(compositionTimeRange.duration))s")

    let videoComposition: AVMutableVideoComposition
    do {
      videoComposition = try await zoomCompositor.createVideoComposition(
        for: composition,
        timeRange: compositionTimeRange
      )
      print("🔍 [ZoomExport] Created video composition successfully")
      print("🔍 [ZoomExport] Video composition render size: \(videoComposition.renderSize)")
      print("🔍 [ZoomExport] Video composition frame duration: \(videoComposition.frameDuration)")
      print("🔍 [ZoomExport] Video composition instructions count: \(videoComposition.instructions.count)")
    } catch {
      print("❌ [ZoomExport] ERROR creating video composition: \(error)")
      throw error
    }

    // Export with video composition
    guard let exportSession = AVAssetExportSession(
      asset: composition,
      presetName: AVAssetExportPresetHighestQuality
    ) else {
      print("❌ [ZoomExport] ERROR: Failed to create export session")
      throw ExportError.sessionCreationFailed
    }
    print("🔍 [ZoomExport] Created export session")
    print("🔍 [ZoomExport] Supported file types: \(exportSession.supportedFileTypes)")

    try? FileManager.default.removeItem(at: outputURL)
    exportSession.outputURL = outputURL
    exportSession.outputFileType = outputFileType(for: state.fileExtension)
    exportSession.videoComposition = videoComposition
    print("🔍 [ZoomExport] Export session configured with output type: \(exportSession.outputFileType?.rawValue ?? "nil")")

    let progressTask = Task {
      while !Task.isCancelled && exportSession.status == .exporting {
        progress(exportSession.progress)
        print("🔍 [ZoomExport] Export progress: \(Int(exportSession.progress * 100))%")
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds for less spam
      }
    }

    print("🔍 [ZoomExport] Starting export...")
    await exportSession.export()
    progressTask.cancel()

    print("🔍 [ZoomExport] Export finished with status: \(exportSession.status.rawValue)")
    if let error = exportSession.error {
      print("❌ [ZoomExport] Export error: \(error)")
      print("❌ [ZoomExport] Error localized: \(error.localizedDescription)")
      if let nsError = error as NSError? {
        print("❌ [ZoomExport] Error domain: \(nsError.domain)")
        print("❌ [ZoomExport] Error code: \(nsError.code)")
        print("❌ [ZoomExport] Error userInfo: \(nsError.userInfo)")
      }
    }

    guard exportSession.status == .completed else {
      print("❌ [ZoomExport] Export failed with status: \(exportSession.status.rawValue)")
      throw exportSession.error ?? ExportError.exportFailed
    }

    print("✅ [ZoomExport] Export completed successfully!")
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
