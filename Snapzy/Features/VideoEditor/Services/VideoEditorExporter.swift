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
      "hasCustomAudio": "\(state.exportSettings.audioMode == .custom)",
      "hasSpeed": "\(state.hasSpeedSegments)",
      "clips": "\(state.clips.count)",
      "hasInsertedClips": "\(state.hasInsertedClips)",
      "quality": state.exportSettings.quality.exportPreset,
    ])
    let outputAccess = SandboxFileAccessManager.shared.beginAccessingURL(outputURL.deletingLastPathComponent())
    defer { outputAccess.stop() }
    let scopedOutputURL = outputAccess.url.appendingPathComponent(outputURL.lastPathComponent)

    let hasCameraEffects = state.zoomSegments.contains { $0.isEnabled }
    let hasBackground = state.backgroundStyle != .none && state.backgroundPadding > 0
    let hasCustomAudio = state.exportSettings.audioMode == .custom
    let hasSpeed = state.hasSpeedSegments
    // Anything beyond a single untouched primary clip needs the composition path.
    let hasSequenceEdits = state.hasSequenceEdits

    // If visual effects, custom audio, speed scaling, or a multi-clip sequence are in
    // play, use composition-based export. Speed scaling requires the composition path
    // even with no other effects (and even when muted — audio is simply dropped while
    // the video is still time-scaled).
    if hasCameraEffects || hasBackground || hasCustomAudio || hasSpeed || hasSequenceEdits {
      try await exportWithZooms(state: state, to: scopedOutputURL, progress: progress)
      try await normalizeExportAudioForCompatibilityIfNeeded(
        at: scopedOutputURL,
        fileExtension: state.fileExtension
      )
      return
    }

    // If muted via export settings, export without audio
    if state.exportSettings.audioMode == .mute {
      try await exportVideoOnly(state: state, to: scopedOutputURL, progress: progress)
      return
    }

    // Standard export without zooms
    try await exportStandard(state: state, to: scopedOutputURL, progress: progress)
    try await normalizeExportAudioForCompatibilityIfNeeded(
      at: scopedOutputURL,
      fileExtension: state.fileExtension
    )
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
      "output": outputURL.lastPathComponent,
    ])

    guard let exportSession = AVAssetExportSession(
      asset: state.asset,
      presetName: state.exportSettings.quality.exportPreset
    ) else {
      DiagnosticLogger.shared.log(.error, .export, "Standard video export session creation failed")
      throw ExportError.sessionCreationFailed
    }

    // Remove existing file if present
    try? FileManager.default.removeItem(at: outputURL)

    exportSession.outputURL = outputURL
    exportSession.outputFileType = outputFileType(for: state.fileExtension)
    exportSession.timeRange = timeRange
    if let audioMix = try await makeAudioMix(
      for: state.asset,
      settings: state.exportSettings,
      roles: state.audioTrackRoles,
      logPrefix: "[Export]"
    ) {
      exportSession.audioMix = audioMix
    }

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
        let fittedRect = state.exportSettings.videoContentRect(from: state.naturalSize)
        let scaleTransform = CGAffineTransform(
          scaleX: fittedRect.width / state.naturalSize.width,
          y: fittedRect.height / state.naturalSize.height
        )
        let centerTransform = CGAffineTransform(
          translationX: fittedRect.origin.x,
          y: fittedRect.origin.y
        )

        // Apply preferred transform first, then scale, then center
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        layerInstruction.setTransform(
          preferredTransform.concatenating(scaleTransform).concatenating(centerTransform),
          at: .zero
        )

        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        exportSession.videoComposition = videoComposition
        print("📹 [Export] Applied custom dimensions: \(targetSize)")
        DiagnosticLogger.shared.log(
          .debug,
          .export,
          "Applied custom dimensions",
          context: ["size": "\(Int(targetSize.width))x\(Int(targetSize.height))"]
        )
      }
    }

    // Start progress monitoring
    let progressTask = Task {
      while !Task.isCancelled, exportSession.status == .exporting {
        progress(exportSession.progress)
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
      }
    }

    await exportSession.export()
    progressTask.cancel()

    print("📹 [Export] Export status: \(exportSession.status.rawValue)")
    DiagnosticLogger.shared.log(
      .debug,
      .export,
      "Standard video export finished",
      context: ["status": "\(exportSession.status.rawValue)"]
    )
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
    DiagnosticLogger.shared.log(
      fileExists ? .info : .error,
      .export,
      "Standard video export completed",
      context: ["output": outputURL.lastPathComponent, "fileExists": fileExists ? "true" : "false"]
    )
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
      "size": "\(Int(state.naturalSize.width))x\(Int(state.naturalSize.height))",
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

    // The sequence is inserted clip by clip; composition time == SEQUENCE time before
    // speed scaling, then OUTPUT time after it.
    let clips = state.clips
    guard !clips.isEmpty, state.sequenceDuration > 0.0001 else {
      DiagnosticLogger.shared.log(.error, .export, "Export rejected: empty timeline sequence")
      throw ExportError.exportFailed
    }

    let placements = state.playbackPlacements
    let sequenceMap = state.sequenceMap
    let speedMap: TimelineSequenceMap? = state.hasSpeedSegments ? sequenceMap : nil
    print(
      "🔍 [ZoomExport] Sequence: \(clips.count) clip(s), \(String(format: "%.2f", sequenceMap.sequenceDuration))s → output \(String(format: "%.2f", sequenceMap.outputDuration))s"
    )

    // Zoom segments are authored on the independent structural timeline. Project
    // their ranges onto active playable material only at export time, then apply
    // speed on the same compact sequence axis. A segment entirely over trimmed-out
    // slots is dropped; reorder never changes the authored effect position.
    let outputSeconds = sequenceMap.outputDuration
    let adjustedZooms = state.zoomSegments.compactMap { segment -> ZoomSegment? in
      let pieces = state.projectToPlaybackSequence(
        timelineRange: segment.startTime ... segment.endTime
      )
      guard let firstPiece = pieces.first, let lastPiece = pieces.last else { return nil }

      var adjusted = segment
      adjusted.startTime = sequenceMap.toOutput(firstPiece.lowerBound)
      adjusted.duration = max(0, sequenceMap.toOutput(lastPiece.upperBound) - adjusted.startTime)
      return adjusted
    }.filter { $0.startTime + $0.duration > 0 && $0.startTime < outputSeconds }

    let adjustedAutoFocusPaths = Dictionary(
      uniqueKeysWithValues: adjustedZooms
        .filter(\.isAutoMode)
        .map { segment -> (UUID, [AutoFocusCameraSample]) in
          // Trim-relative source path → playable sequence (clip-aware) → output.
          var path = VideoEditorAutoFocusEngine.trimmedPath(
            state.autoFocusPath(for: segment),
            trimStart: trimStartSeconds,
            trimEnd: trimEndSeconds
          )
          path = VideoEditorAutoFocusEngine.sequencePath(
            path,
            placements: placements,
            trimStart: trimStartSeconds
          )
          if let map = speedMap {
            path = VideoEditorAutoFocusEngine.scaledPath(path, map: map)
          }
          // The path can cover the whole recording, while this effect owns only its
          // authored output range. Keep the compositor from interpolating outside it.
          path = path.filter { $0.time >= segment.startTime && $0.time <= segment.endTime }
          return (segment.id, path)
        }
    )

    print("🔍 [ZoomExport] Adjusted zooms count: \(adjustedZooms.count)")
    for (index, zoom) in adjustedZooms.enumerated() {
      print(
        "🔍 [ZoomExport] Zoom[\(index)]: start=\(zoom.startTime)s, duration=\(zoom.duration)s, level=\(zoom.zoomLevel)x, enabled=\(zoom.isEnabled)"
      )
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
      DiagnosticLogger.shared.log(.error, .export, "Zoom export failed to add video track to composition")
      throw ExportError.exportFailed
    }
    print("🔍 [ZoomExport] Composition video track ID: \(compositionVideoTrack.trackID)")

    do {
      // One pass over the sequence: each clip contributes its own source window from its
      // own asset, in timeline order.
      var cursor = CMTime.zero
      for clip in clips {
        let clipDuration = CMTime(seconds: clip.duration, preferredTimescale: 600)
        let sourceRange = CMTimeRange(
          start: CMTime(seconds: clip.sourceStart, preferredTimescale: 600),
          duration: clipDuration
        )

        let track: AVAssetTrack? = if clip.isPrimary {
          sourceVideoTrack
        } else {
          try await state.clipAsset(for: clip).loadTracks(withMediaType: .video).first
        }
        guard let track else {
          // A clip with no video track still has to hold its slot, or everything after
          // it would slide earlier than the timeline says.
          compositionVideoTrack.insertEmptyTimeRange(
            CMTimeRange(start: cursor, duration: clipDuration)
          )
          cursor = CMTimeAdd(cursor, clipDuration)
          continue
        }

        try compositionVideoTrack.insertTimeRange(sourceRange, of: track, at: cursor)
        cursor = CMTimeAdd(cursor, clipDuration)
      }
      print("🔍 [ZoomExport] Inserted \(clips.count) clip(s); composition duration \(CMTimeGetSeconds(cursor))s")
    } catch {
      print("❌ [ZoomExport] ERROR inserting video time range: \(error)")
      DiagnosticLogger.shared.logError(.export, error, "Failed to insert video time range")
      throw error
    }

    // Copy video track transform
    let transform = try await sourceVideoTrack.load(.preferredTransform)
    compositionVideoTrack.preferredTransform = transform
    print("🔍 [ZoomExport] Applied video transform: \(transform)")

    // Apply per-segment speed scaling to the video track (reverse order so earlier ranges
    // are not shifted by later scaling). Composition time is already trim-relative, so the
    // map's span coordinates map directly.
    if let speedMap {
      applySpeedScaling(to: compositionVideoTrack, map: speedMap, logPrefix: "[ZoomExport] video")
    }

    // Add audio track based on export settings (scaled + pitch-preserved when speed active).
    let audioMix = try await addAudioTracks(
      to: composition,
      from: state.asset,
      state: state,
      settings: state.exportSettings,
      roles: state.audioTrackRoles,
      speedMap: speedMap,
      logPrefix: "[ZoomExport]"
    )

    // Verify composition duration
    print("🔍 [ZoomExport] Composition duration: \(CMTimeGetSeconds(composition.duration))s")

    // Verify composition has video tracks before proceeding
    guard let composedVideoTrack = composition.tracks(withMediaType: .video).first else {
      print("❌ [ZoomExport] ERROR: Composition has no video tracks after insertion")
      DiagnosticLogger.shared.log(.error, .export, "Zoom export composition has no video tracks after insertion")
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
    print(
      "🔍 [ZoomExport] Composition time range: start=\(CMTimeGetSeconds(compositionTimeRange.start))s, duration=\(CMTimeGetSeconds(compositionTimeRange.duration))s"
    )

    // Validate the scaled composition duration matches the expected output length.
    if let speedMap {
      let actualSeconds = CMTimeGetSeconds(actualCompositionDuration)
      // The sequence map already covers every clip, inserted ones included.
      let expectedSeconds = speedMap.outputDuration
      if abs(actualSeconds - expectedSeconds) > 0.1 {
        DiagnosticLogger.shared.log(.warning, .export, "Speed-scaled composition duration mismatch", context: [
          "actual": String(format: "%.3f", actualSeconds),
          "expected": String(format: "%.3f", expectedSeconds),
        ])
        print("⚠️ [ZoomExport] Scaled duration mismatch: actual=\(actualSeconds)s expected=\(expectedSeconds)s")
      }
    }

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
      DiagnosticLogger.shared.log(.error, .export, "Zoom export session creation failed")
      throw ExportError.sessionCreationFailed
    }
    print("🔍 [ZoomExport] Created export session")
    print("🔍 [ZoomExport] Supported file types: \(exportSession.supportedFileTypes)")

    try? FileManager.default.removeItem(at: outputURL)
    exportSession.outputURL = outputURL
    exportSession.outputFileType = outputFileType(for: state.fileExtension)
    exportSession.videoComposition = videoComposition
    if let audioMix {
      exportSession.audioMix = audioMix
    }
    print(
      "🔍 [ZoomExport] Export session configured with output type: \(exportSession.outputFileType?.rawValue ?? "nil")"
    )

    let progressTask = Task {
      while !Task.isCancelled, exportSession.status == .exporting {
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
      DiagnosticLogger.shared.logError(
        .export,
        error,
        "Zoom export failed",
        context: ["status": "\(exportSession.status.rawValue)"]
      )
      if let nsError = error as NSError? {
        print("❌ [ZoomExport] Error domain: \(nsError.domain)")
        print("❌ [ZoomExport] Error code: \(nsError.code)")
        print("❌ [ZoomExport] Error userInfo: \(nsError.userInfo)")
      }
    }

    guard exportSession.status == .completed else {
      print("❌ [ZoomExport] Export failed with status: \(exportSession.status.rawValue)")
      DiagnosticLogger.shared.log(
        .error,
        .export,
        "Zoom export failed with non-completed status",
        context: ["status": "\(exportSession.status.rawValue)"]
      )
      throw exportSession.error ?? ExportError.exportFailed
    }

    print("✅ [ZoomExport] Export completed successfully!")
    DiagnosticLogger.shared.log(
      .info,
      .export,
      "Zoom export completed",
      context: ["output": outputURL.lastPathComponent]
    )
  }

  /// Export video without audio track
  private static func exportVideoOnly(
    state: VideoEditorState,
    to outputURL: URL,
    progress: @escaping (Float) -> Void
  ) async throws {
    DiagnosticLogger.shared.log(
      .info,
      .export,
      "Video-only export started",
      context: ["output": outputURL.lastPathComponent]
    )
    let timeRange = CMTimeRange(start: state.trimStart, end: state.trimEnd)
    let composition = AVMutableComposition()

    // Add only video track
    guard let videoTrack = try await state.asset.loadTracks(withMediaType: .video).first else {
      DiagnosticLogger.shared.log(.error, .export, "Video-only export failed; source video track missing")
      throw ExportError.exportFailed
    }
    let sourceFrameDuration = try await sourceFrameDuration(for: videoTrack)

    guard let compositionVideoTrack = composition.addMutableTrack(
      withMediaType: .video,
      preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
      DiagnosticLogger.shared.log(.error, .export, "Video-only export failed to add video track")
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
      let fittedRect = state.exportSettings.videoContentRect(from: state.naturalSize)
      let scaleTransform = CGAffineTransform(
        scaleX: fittedRect.width / state.naturalSize.width,
        y: fittedRect.height / state.naturalSize.height
      )
      let centerTransform = CGAffineTransform(
        translationX: fittedRect.origin.x,
        y: fittedRect.origin.y
      )

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
      DiagnosticLogger.shared.log(.error, .export, "Video-only export session creation failed")
      throw ExportError.sessionCreationFailed
    }

    try? FileManager.default.removeItem(at: outputURL)
    exportSession.outputURL = outputURL
    exportSession.outputFileType = outputFileType(for: state.fileExtension)
    if let videoComposition {
      exportSession.videoComposition = videoComposition
    }

    let progressTask = Task {
      while !Task.isCancelled, exportSession.status == .exporting {
        progress(exportSession.progress)
        try? await Task.sleep(nanoseconds: 100_000_000)
      }
    }

    await exportSession.export()
    progressTask.cancel()

    guard exportSession.status == .completed else {
      if let error = exportSession.error {
        DiagnosticLogger.shared.logError(.export, error, "Video-only export failed")
      } else {
        DiagnosticLogger.shared.log(
          .error,
          .export,
          "Video-only export failed with non-completed status",
          context: ["status": "\(exportSession.status.rawValue)"]
        )
      }
      throw exportSession.error ?? ExportError.exportFailed
    }
    DiagnosticLogger.shared.log(
      .info,
      .export,
      "Video-only export completed",
      context: ["output": outputURL.lastPathComponent]
    )
  }

  /// Replace original file with trimmed version
  static func replaceOriginal(state: VideoEditorState, progress: @escaping (Float) -> Void) async throws {
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(state.fileExtension)

    print("📹 [ReplaceOriginal] Temp URL: \(tempURL)")
    print("📹 [ReplaceOriginal] Source URL: \(state.sourceURL)")
    print("📹 [ReplaceOriginal] Original URL (target): \(state.originalURL)")
    DiagnosticLogger.shared.log(
      .info,
      .export,
      "Replace original started",
      context: ["file": state.originalURL.lastPathComponent]
    )

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
      state.originalURL.deletingLastPathComponent()
    )
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
      DiagnosticLogger.shared.log(.debug, .export, "Original video moved to backup before replacement")

      // Move temp to original location
      try FileManager.default.moveItem(at: tempURL, to: targetURL)
      print("📹 [ReplaceOriginal] Moved temp to original location")
      DiagnosticLogger.shared.log(.debug, .export, "Trimmed video moved to original location")

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

  private static func addAudioTracks(
    to composition: AVMutableComposition,
    from asset: AVAsset,
    state: VideoEditorState,
    settings: ExportSettings,
    roles: [VideoEditorAudioTrackRole],
    speedMap: TimelineSequenceMap?,
    logPrefix: String
  ) async throws -> AVMutableAudioMix? {
    guard settings.shouldIncludeAudio else {
      print("\(logPrefix) Audio muted, skipping audio tracks")
      return nil
    }

    let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
    guard !sourceAudioTracks.isEmpty else {
      print("\(logPrefix) No audio tracks in source")
      return nil
    }

    let clips = state.clips
    var compositionAudioTracks: [AVMutableCompositionTrack] = []

    // One composition track per source audio track (mic / system / …). Each walks the
    // whole sequence so inserted clips stay interleaved rather than appended.
    for (trackIndex, sourceAudioTrack) in sourceAudioTracks.enumerated() {
      guard let compositionAudioTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
      ) else {
        DiagnosticLogger.shared.log(.error, .export, "Failed to add composition audio track")
        throw ExportError.exportFailed
      }

      var cursor = CMTime.zero
      for clip in clips {
        let clipDuration = CMTime(seconds: clip.duration, preferredTimescale: 600)
        let sourceRange = CMTimeRange(
          start: CMTime(seconds: clip.sourceStart, preferredTimescale: 600),
          duration: clipDuration
        )

        if clip.isPrimary {
          try compositionAudioTrack.insertTimeRange(sourceRange, of: sourceAudioTrack, at: cursor)
        } else if trackIndex == 0,
                  let clipAudio = try await state.clipAsset(for: clip)
                  .loadTracks(withMediaType: .audio).first {
          // Inserted clips carry a single audio track; it rides the first lane.
          try compositionAudioTrack.insertTimeRange(sourceRange, of: clipAudio, at: cursor)
        } else {
          // Silence keeps this lane aligned with the others.
          compositionAudioTrack.insertEmptyTimeRange(
            CMTimeRange(start: cursor, duration: clipDuration)
          )
        }

        cursor = CMTimeAdd(cursor, clipDuration)
      }

      compositionAudioTracks.append(compositionAudioTrack)
    }

    // Time-scale audio with the same spans as video so A/V stays in sync. Spans are in
    // base coordinates, matching the composition layout (merged clips sit after the
    // scaled primary span so they are unaffected).
    if let speedMap {
      for track in compositionAudioTracks {
        applySpeedScaling(to: track, map: speedMap, logPrefix: "\(logPrefix) audio")
      }
    }

    print("\(logPrefix) Added \(compositionAudioTracks.count) audio track(s)")
    let baseMix = makeAudioMix(
      for: compositionAudioTracks,
      settings: settings,
      roles: roles,
      logPrefix: logPrefix
    )
    // Preserve pitch on scaled audio (independent of volume/custom mode).
    return applyPitchPreservation(
      to: baseMix,
      tracks: compositionAudioTracks,
      speedMap: speedMap,
      logPrefix: logPrefix
    )
  }

  /// Apply per-segment `scaleTimeRange` to a composition track. Scales in reverse order
  /// (last → first) so scaling a later range does not shift the position of earlier ranges.
  private static func applySpeedScaling(
    to track: AVMutableCompositionTrack,
    map: TimelineSequenceMap,
    logPrefix: String
  ) {
    for span in map.spans.reversed() where span.rate != 1.0 {
      let range = CMTimeRange(
        start: CMTime(seconds: span.seqStart, preferredTimescale: 600),
        duration: CMTime(seconds: span.seqDuration, preferredTimescale: 600)
      )
      let newDuration = CMTime(seconds: span.scaledDuration, preferredTimescale: 600)
      track.scaleTimeRange(range, toDuration: newDuration)
    }
    print("\(logPrefix) scaled → duration \(CMTimeGetSeconds(track.timeRange.duration))s")
  }

  /// Ensure scaled audio keeps its original pitch. Sets `.spectral` on the audio-mix input
  /// parameters for every track. Reuses the volume mix when present, otherwise builds a
  /// pitch-only mix. Returns the base mix unchanged when no speed scaling is active.
  private static func applyPitchPreservation(
    to baseMix: AVMutableAudioMix?,
    tracks: [AVMutableCompositionTrack],
    speedMap: TimelineSequenceMap?,
    logPrefix: String
  ) -> AVMutableAudioMix? {
    guard let speedMap, !speedMap.isIdentity else { return baseMix }

    let mix = baseMix ?? AVMutableAudioMix()
    let existing = (mix.inputParameters as? [AVMutableAudioMixInputParameters]) ?? []
    let existingByTrack = Dictionary(
      existing.map { ($0.trackID, $0) },
      uniquingKeysWith: { first, _ in first }
    )

    mix.inputParameters = tracks.map { track in
      let params = existingByTrack[track.trackID] ?? AVMutableAudioMixInputParameters(track: track)
      params.audioTimePitchAlgorithm = .spectral
      return params
    }
    print("\(logPrefix) Applied .spectral pitch preservation to \(tracks.count) audio track(s)")
    return mix
  }

  private static func makeAudioMix(
    for asset: AVAsset,
    settings: ExportSettings,
    roles: [VideoEditorAudioTrackRole],
    logPrefix: String
  ) async throws -> AVMutableAudioMix? {
    guard settings.audioMode == .custom else { return nil }

    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    guard !audioTracks.isEmpty else {
      print("\(logPrefix) Custom volume requested, but source has no audio tracks")
      return nil
    }

    return makeAudioMix(
      for: audioTracks,
      settings: settings,
      roles: roles,
      logPrefix: logPrefix
    )
  }

  private static func makeAudioMix(
    for audioTracks: [AVAssetTrack],
    settings: ExportSettings,
    roles: [VideoEditorAudioTrackRole],
    logPrefix: String
  ) -> AVMutableAudioMix? {
    guard settings.audioMode == .custom else { return nil }

    let resolvedRoles: [VideoEditorAudioTrackRole] = if roles.count == audioTracks.count {
      roles
    } else {
      VideoEditorAudioTrackRole.roles(forAudioTrackCount: audioTracks.count)
    }
    let mix = VideoEditorAudioMixFactory.makeAudioMix(
      for: audioTracks,
      settings: settings,
      roles: resolvedRoles
    )
    for (_, role) in zip(audioTracks, resolvedRoles) {
      let volume = settings.effectiveVolume(for: role)
      print("\(logPrefix) Applied \(role.localizedLabel) volume: \(volume)")
    }
    return mix
  }

  private static func normalizeExportAudioForCompatibilityIfNeeded(
    at outputURL: URL,
    fileExtension: String
  ) async throws {
    let result = try await RecordingAudioCompatibilityExporter.normalizeIfNeeded(
      at: outputURL,
      fileType: outputFileType(for: fileExtension),
      preservesAudioSource: false
    )

    guard result.didNormalize else {
      DiagnosticLogger.shared.log(.debug, .export, "Video export audio normalization skipped", context: [
        "output": outputURL.lastPathComponent,
        "audioTracks": "\(result.audioTrackCount)",
      ])
      return
    }

    DiagnosticLogger.shared.log(.info, .export, "Video export audio normalized for compatibility", context: [
      "output": outputURL.lastPathComponent,
      "sourceAudioTracks": "\(result.audioTrackCount)",
      "outputAudioTracks": "1",
    ])
  }

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
      .mp4
    case "mov":
      .mov
    default:
      .mp4
    }
  }

  private static func sourceFrameDuration(for videoTrack: AVAssetTrack) async throws -> CMTime {
    let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
    if nominalFrameRate > 0 {
      return CMTime(seconds: 1.0 / Double(nominalFrameRate), preferredTimescale: 60_000)
    }

    let minFrameDuration = try await videoTrack.load(.minFrameDuration)
    if minFrameDuration.isValid, minFrameDuration.seconds > 0 {
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
        L10n.VideoExport.sessionCreationFailed
      case .exportFailed:
        L10n.VideoExport.exportFailed
      }
    }
  }
}
