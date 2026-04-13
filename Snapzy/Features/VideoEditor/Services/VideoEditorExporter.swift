//
//  VideoEditorExporter.swift
//  Snapzy
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
    DiagnosticLogger.shared.log(.info, .export, "Video export started", context: [
      "file": state.sourceURL.lastPathComponent,
      "hasZooms": "\(state.zoomSegments.contains { $0.isEnabled })",
      "hasBackground": "\(state.backgroundStyle != .none && state.backgroundPadding > 0)",
      "quality": state.exportSettings.quality.exportPreset
    ])
    let outputAccess = SandboxFileAccessManager.shared.beginAccessingURL(outputURL.deletingLastPathComponent())
    defer { outputAccess.stop() }
    let scopedOutputURL = outputAccess.url.appendingPathComponent(outputURL.lastPathComponent)

    let hasCameraEffects = state.zoomSegments.contains { $0.isEnabled }
    let hasBackground = state.backgroundStyle != .none && state.backgroundPadding > 0

    // If has zooms or background, use composition-based export
    if hasCameraEffects || hasBackground {
      try await exportWithZooms(state: state, to: scopedOutputURL, progress: progress)
      return
    }

    // If muted via export settings, export without audio
    if state.exportSettings.audioMode == .mute {
      try await exportVideoOnly(state: state, to: scopedOutputURL, progress: progress)
      return
    }

    // Standard export without zooms
    try await exportStandard(state: state, to: scopedOutputURL, progress: progress)
  }

  /// Standard export without zoom effects
  private static func exportStandard(
    state: VideoEditorState,
    to outputURL: URL,
    progress: @escaping (Float) -> Void
  ) async throws {
    let timeRange = CMTimeRange(start: state.trimStart, end: state.trimEnd)

    print("📹 [Export] Standard export starting")
    DiagnosticLogger.shared.log(.info, .export, "Standard export", context: [
      "trim": "\(String(format: "%.1f", CMTimeGetSeconds(state.trimStart)))s-\(String(format: "%.1f", CMTimeGetSeconds(state.trimEnd)))s",
      "output": outputURL.lastPathComponent
    ])

    guard let exportSession = AVAssetExportSession(
      asset: state.asset,
      presetName: state.exportSettings.quality.exportPreset
    ) else {
      throw ExportError.sessionCreationFailed
    }

    // Remove existing file if present
    try? FileManager.default.removeItem(at: outputURL)

    exportSession.outputURL = outputURL
    exportSession.outputFileType = outputFileType(for: state.fileExtension)
    exportSession.timeRange = timeRange

    // Apply custom dimensions if not using original size
    if state.exportSettings.dimensionPreset != .original {
      let targetSize = state.exportSettings.exportSize(from: state.naturalSize)

      // Get video track for composition
      if let videoTrack = try await state.asset.loadTracks(withMediaType: .video).first {
        let sourceFrameDuration = try await sourceFrameDuration(for: videoTrack)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = targetSize
        videoComposition.frameDuration = sourceFrameDuration

        // Create layer instruction for scaling
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)

        // Calculate uniform aspect-fit scale to preserve entire frame without cropping
        let naturalSize = state.naturalSize
        let scale = min(targetSize.width / naturalSize.width, targetSize.height / naturalSize.height)
        let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)

        // Center the scaled content within target size
        let scaledWidth = naturalSize.width * scale
        let scaledHeight = naturalSize.height * scale
        let translateX = (targetSize.width - scaledWidth) / 2
        let translateY = (targetSize.height - scaledHeight) / 2
        let centerTransform = CGAffineTransform(translationX: translateX, y: translateY)

        // Apply preferred transform first, then scale, then center
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        layerInstruction.setTransform(preferredTransform.concatenating(scaleTransform).concatenating(centerTransform), at: .zero)

        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        exportSession.videoComposition = videoComposition
        print("📹 [Export] Applied custom dimensions: \(targetSize)")
        DiagnosticLogger.shared.log(.debug, .export, "Applied custom dimensions", context: ["size": "\(Int(targetSize.width))x\(Int(targetSize.height))"])
      }
    }

    // Start progress monitoring
    let progressTask = Task {
      while !Task.isCancelled && exportSession.status == .exporting {
        progress(exportSession.progress)
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
      }
    }

    await exportSession.export()
    progressTask.cancel()

    print("📹 [Export] Export status: \(exportSession.status.rawValue)")
    if let error = exportSession.error {
      print("📹 [Export] Export error: \(error)")
      DiagnosticLogger.shared.logError(.export, error, "Standard export failed")
    }

    guard exportSession.status == .completed else {
      throw exportSession.error ?? ExportError.exportFailed
    }

    // Verify exported file exists
    let fileExists = FileManager.default.fileExists(atPath: outputURL.path)
    print("📹 [Export] Exported file exists: \(fileExists)")
  }

  /// Export with zoom effects applied
  private static func exportWithZooms(
    state: VideoEditorState,
    to outputURL: URL,
    progress: @escaping (Float) -> Void
  ) async throws {
    DiagnosticLogger.shared.log(.info, .export, "Zoom export started", context: [
      "zoomSegments": "\(state.zoomSegments.count)",
      "trim": "\(String(format: "%.1f", CMTimeGetSeconds(state.trimStart)))s-\(String(format: "%.1f", CMTimeGetSeconds(state.trimEnd)))s",
      "size": "\(Int(state.naturalSize.width))x\(Int(state.naturalSize.height))"
    ])
    print("🔍 [ZoomExport] Starting export with zooms")
    print("🔍 [ZoomExport] Output URL: \(outputURL)")
    print("🔍 [ZoomExport] Video duration: \(CMTimeGetSeconds(state.duration))s")
    print("🔍 [ZoomExport] Trim START: \(CMTimeGetSeconds(state.trimStart))s")
    print("🔍 [ZoomExport] Trim END: \(CMTimeGetSeconds(state.trimEnd))s")
    print("🔍 [ZoomExport] Trimmed duration: \(CMTimeGetSeconds(state.trimmedDuration))s")
    print("🔍 [ZoomExport] Natural size: \(state.naturalSize)")
    print("🔍 [ZoomExport] Total zoom segments: \(state.zoomSegments.count)")

    // Validate trim range
    let trimStartSeconds = CMTimeGetSeconds(state.trimStart)
    let trimEndSeconds = CMTimeGetSeconds(state.trimEnd)
    let fullDuration = CMTimeGetSeconds(state.duration)

    let hasTrimChanges = trimStartSeconds > 0.1 || (fullDuration - trimEndSeconds) > 0.1
    print("🔍 [ZoomExport] Has trim changes: \(hasTrimChanges)")

    let timeRange = CMTimeRange(start: state.trimStart, end: state.trimEnd)

    // Adjust zoom times relative to trim start
    let adjustedZooms = state.zoomSegments.map { segment -> ZoomSegment in
      var adjusted = segment
      adjusted.startTime = segment.startTime - trimStartSeconds
      return adjusted
    }.filter { $0.startTime + $0.duration > 0 && $0.startTime < CMTimeGetSeconds(state.trimmedDuration) }

    let adjustedAutoFocusPaths = Dictionary(
      uniqueKeysWithValues: adjustedZooms
        .filter { $0.isAutoMode }
        .map { segment in
          (
            segment.id,
            VideoEditorAutoFocusEngine.trimmedPath(
              state.autoFocusPath(for: segment),
              trimStart: trimStartSeconds,
              trimEnd: trimEndSeconds
            )
          )
        }
    )

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
      DiagnosticLogger.shared.log(.error, .export, "No video track in source asset")
      throw ExportError.exportFailed
    }
    print("🔍 [ZoomExport] Source video track ID: \(sourceVideoTrack.trackID)")
    let sourceFrameDuration = try await sourceFrameDuration(for: sourceVideoTrack)

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
      print("🔍 [ZoomExport] Inserted video time range: \(CMTimeGetSeconds(timeRange.start))s - \(CMTimeGetSeconds(timeRange.end))s (duration: \(CMTimeGetSeconds(timeRange.duration))s)")
    } catch {
      print("❌ [ZoomExport] ERROR inserting video time range: \(error)")
      DiagnosticLogger.shared.logError(.export, error, "Failed to insert video time range")
      throw error
    }

    // Copy video track transform
    let transform = try await sourceVideoTrack.load(.preferredTransform)
    compositionVideoTrack.preferredTransform = transform
    print("🔍 [ZoomExport] Applied video transform: \(transform)")

    // Add audio track based on export settings
    var audioMix: AVMutableAudioMix?
    if state.exportSettings.shouldIncludeAudio {
      if let sourceAudioTrack = try await state.asset.loadTracks(withMediaType: .audio).first {
        if let compositionAudioTrack = composition.addMutableTrack(
          withMediaType: .audio,
          preferredTrackID: kCMPersistentTrackID_Invalid
        ) {
          try? compositionAudioTrack.insertTimeRange(timeRange, of: sourceAudioTrack, at: .zero)
          print("🔍 [ZoomExport] Added audio track")

          // Apply volume adjustment if custom volume
          if state.exportSettings.audioMode == .custom {
            let mix = AVMutableAudioMix()
            let params = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
            params.setVolume(state.exportSettings.effectiveVolume, at: .zero)
            mix.inputParameters = [params]
            audioMix = mix
            print("🔍 [ZoomExport] Applied custom volume: \(state.exportSettings.effectiveVolume)")
          }
        }
      } else {
        print("🔍 [ZoomExport] No audio track in source")
      }
    } else {
      print("🔍 [ZoomExport] Audio muted, skipping audio track")
    }

    // Verify composition duration
    print("🔍 [ZoomExport] Composition duration: \(CMTimeGetSeconds(composition.duration))s")

    // Verify composition has video tracks before proceeding
    guard let composedVideoTrack = composition.tracks(withMediaType: .video).first else {
      print("❌ [ZoomExport] ERROR: Composition has no video tracks after insertion")
      throw ExportError.exportFailed
    }
    print("🔍 [ZoomExport] Verified composed video track ID: \(composedVideoTrack.trackID)")

    // Calculate target render size BEFORE creating compositor
    // This prevents AVFoundation from recalculating frame boundaries after composition is created
    let baseRenderSize: CGSize
    if state.exportSettings.dimensionPreset != .original {
      baseRenderSize = state.exportSettings.exportSize(from: state.naturalSize)
      print("🔍 [ZoomExport] Using custom dimensions: \(baseRenderSize)")
    } else {
      baseRenderSize = state.naturalSize
      print("🔍 [ZoomExport] Using original dimensions: \(baseRenderSize)")
    }

    // Create zoom compositor with correct render size from the start
    print("🔍 [ZoomExport] Creating ZoomCompositor with renderSize: \(baseRenderSize)")
    let zoomCompositor = ZoomCompositor(
      zooms: adjustedZooms,
      autoFocusPaths: adjustedAutoFocusPaths,
      renderSize: baseRenderSize,
      frameDuration: sourceFrameDuration,
      transitionDuration: state.zoomTransitionDuration,
      backgroundStyle: state.backgroundStyle,
      backgroundPadding: state.backgroundPadding,
      cornerRadius: state.backgroundCornerRadius
    )

    // Use actual composition duration to prevent frame boundary issues
    let actualCompositionDuration = composition.duration
    let compositionTimeRange = CMTimeRange(start: .zero, duration: actualCompositionDuration)
    print("🔍 [ZoomExport] Composition time range: start=\(CMTimeGetSeconds(compositionTimeRange.start))s, duration=\(CMTimeGetSeconds(compositionTimeRange.duration))s")

    let videoComposition: AVMutableVideoComposition
    do {
      videoComposition = try await zoomCompositor.createVideoComposition(
        for: composition,
        timeRange: compositionTimeRange
      )
      // RenderSize is already set correctly in ZoomCompositor, just use paddedRenderSize for background
      videoComposition.renderSize = zoomCompositor.paddedRenderSize
      print("🔍 [ZoomExport] Created video composition successfully")
      print("🔍 [ZoomExport] Video composition render size: \(videoComposition.renderSize)")
      print("🔍 [ZoomExport] Video composition frame duration: \(videoComposition.frameDuration)")
      print("🔍 [ZoomExport] Video composition instructions count: \(videoComposition.instructions.count)")
    } catch {
      print("❌ [ZoomExport] ERROR creating video composition: \(error)")
      DiagnosticLogger.shared.logError(.export, error, "Failed to create video composition")
      throw error
    }

    // Export with video composition
    guard let exportSession = AVAssetExportSession(
      asset: composition,
      presetName: state.exportSettings.quality.exportPreset
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
    if let audioMix = audioMix {
      exportSession.audioMix = audioMix
    }
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
    DiagnosticLogger.shared.log(.info, .export, "Zoom export completed", context: ["output": outputURL.lastPathComponent])
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
    let sourceFrameDuration = try await sourceFrameDuration(for: videoTrack)

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

    // Create video composition for custom dimensions
    var videoComposition: AVMutableVideoComposition?
    if state.exportSettings.dimensionPreset != .original {
      let targetSize = state.exportSettings.exportSize(from: state.naturalSize)

      let composition = AVMutableVideoComposition()
      composition.renderSize = targetSize
      composition.frameDuration = sourceFrameDuration

      // Create layer instruction for scaling
      let instruction = AVMutableVideoCompositionInstruction()
      instruction.timeRange = CMTimeRange(start: .zero, duration: compositionVideoTrack.timeRange.duration)

      let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)

      // Calculate uniform aspect-fit scale to preserve entire frame without cropping
      let naturalSize = state.naturalSize
      let scale = min(targetSize.width / naturalSize.width, targetSize.height / naturalSize.height)
      let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)

      // Center the scaled content within target size
      let scaledWidth = naturalSize.width * scale
      let scaledHeight = naturalSize.height * scale
      let translateX = (targetSize.width - scaledWidth) / 2
      let translateY = (targetSize.height - scaledHeight) / 2
      let centerTransform = CGAffineTransform(translationX: translateX, y: translateY)

      layerInstruction.setTransform(transform.concatenating(scaleTransform).concatenating(centerTransform), at: .zero)

      instruction.layerInstructions = [layerInstruction]
      composition.instructions = [instruction]

      videoComposition = composition
      print("📹 [Export] Video-only: Applied custom dimensions: \(targetSize)")
    }

    // Export composition
    guard let exportSession = AVAssetExportSession(
      asset: composition,
      presetName: state.exportSettings.quality.exportPreset
    ) else {
      throw ExportError.sessionCreationFailed
    }

    try? FileManager.default.removeItem(at: outputURL)
    exportSession.outputURL = outputURL
    exportSession.outputFileType = outputFileType(for: state.fileExtension)
    if let videoComposition = videoComposition {
      exportSession.videoComposition = videoComposition
    }

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

    print("📹 [ReplaceOriginal] Temp URL: \(tempURL)")
    print("📹 [ReplaceOriginal] Source URL: \(state.sourceURL)")
    print("📹 [ReplaceOriginal] Original URL (target): \(state.originalURL)")
    DiagnosticLogger.shared.log(.info, .export, "Replace original started", context: ["file": state.originalURL.lastPathComponent])

    try await exportTrimmed(state: state, to: tempURL, progress: progress)

    // Verify temp file was created
    guard FileManager.default.fileExists(atPath: tempURL.path) else {
      print("❌ [ReplaceOriginal] Temp file not found after export!")
      DiagnosticLogger.shared.log(.error, .export, "Temp file missing after export")
      throw ExportError.exportFailed
    }

    // Get temp file size for verification
    let tempAttributes = try? FileManager.default.attributesOfItem(atPath: tempURL.path)
    let tempSize = tempAttributes?[.size] as? Int64 ?? 0
    print("📹 [ReplaceOriginal] Temp file size: \(tempSize) bytes")

    // Replace original with temp file - use originalURL for correct target
    let targetDirectoryAccess = SandboxFileAccessManager.shared.beginAccessingURL(
      state.originalURL.deletingLastPathComponent())
    defer { targetDirectoryAccess.stop() }

    let targetURL = targetDirectoryAccess.url.appendingPathComponent(state.originalURL.lastPathComponent)

    // Use replaceItemAt for atomic replacement (safer)
    let backupURL = targetURL.deletingLastPathComponent()
      .appendingPathComponent(".\(targetURL.lastPathComponent).backup")

    do {
      // Remove any existing backup
      try? FileManager.default.removeItem(at: backupURL)

      // Move original to backup
      try FileManager.default.moveItem(at: targetURL, to: backupURL)
      print("📹 [ReplaceOriginal] Moved original to backup")

      // Move temp to original location
      try FileManager.default.moveItem(at: tempURL, to: targetURL)
      print("📹 [ReplaceOriginal] Moved temp to original location")

      try? RecordingMetadataStore.delete(for: targetURL)

      // Remove backup
      try? FileManager.default.removeItem(at: backupURL)
      print("📹 [ReplaceOriginal] Cleanup complete")

    } catch {
      print("❌ [ReplaceOriginal] Error during replacement: \(error)")
      DiagnosticLogger.shared.logError(.export, error, "File replacement failed")
      // Try to restore from backup if something went wrong
      if FileManager.default.fileExists(atPath: backupURL.path) {
        try? FileManager.default.moveItem(at: backupURL, to: targetURL)
      }
      throw error
    }

    // Verify final file
    let finalAttributes = try? FileManager.default.attributesOfItem(atPath: targetURL.path)
    let finalSize = finalAttributes?[.size] as? Int64 ?? 0
    print("📹 [ReplaceOriginal] Final file size: \(finalSize) bytes")
    print("✅ [ReplaceOriginal] Replacement complete!")
    DiagnosticLogger.shared.log(.info, .export, "Replace original completed", context: ["size": "\(finalSize) bytes"])
  }

  /// Save trimmed video as a copy
  static func saveAsCopy(state: VideoEditorState, progress: @escaping (Float) -> Void) async throws -> URL {
    let copyURL = generateCopyURL(from: state.sourceURL)
    DiagnosticLogger.shared.log(.info, .export, "Save as copy started", context: ["output": copyURL.lastPathComponent])
    try await exportTrimmed(state: state, to: copyURL, progress: progress)
    DiagnosticLogger.shared.log(.info, .export, "Save as copy completed")
    return copyURL
  }

  // MARK: - Helper Methods

  /// Generate copy filename with _trimmed suffix (without directory)
  static func generateCopyFilename(from originalURL: URL) -> String {
    let baseName = originalURL.deletingPathExtension().lastPathComponent
    let ext = originalURL.pathExtension
    return "\(baseName)_trimmed.\(ext)"
  }

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

  private static func sourceFrameDuration(for videoTrack: AVAssetTrack) async throws -> CMTime {
    let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
    if nominalFrameRate > 0 {
      return CMTime(seconds: 1.0 / Double(nominalFrameRate), preferredTimescale: 60_000)
    }

    let minFrameDuration = try await videoTrack.load(.minFrameDuration)
    if minFrameDuration.isValid && minFrameDuration.seconds > 0 {
      return minFrameDuration
    }

    return CMTime(value: 1, timescale: 30)
  }

  // MARK: - Errors

  enum ExportError: Error, LocalizedError {
    case sessionCreationFailed
    case exportFailed

    var errorDescription: String? {
      switch self {
      case .sessionCreationFailed:
        return L10n.VideoExport.sessionCreationFailed
      case .exportFailed:
        return L10n.VideoExport.exportFailed
      }
    }
  }
}
