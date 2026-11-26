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

  /// Capture before suspending so an edit during path generation cannot mix recipes.
  static func prepareSnapshot(for state: VideoEditorState) async throws -> VideoEditorExportSnapshot {
    var snapshot = VideoEditorExportSnapshot(state: state)
    snapshot.autoFocusPaths = await state.awaitExactAutoFocusPaths(
      for: snapshot.zoomSegments,
      metadata: snapshot.recordingMetadata
    )
    snapshot.studioRecipe = state.makeStudioRecipe(
      sequenceMap: snapshot.sequenceMap,
      playbackPlacements: snapshot.playbackPlacements
    )
    snapshot.clickSoundTimes = state.clickSoundOutputTimes(
      sequenceMap: snapshot.sequenceMap,
      playbackPlacements: snapshot.playbackPlacements
    )
    snapshot.clickSoundVolume = Float(state.cursorSettings.clickSoundVolume)
    if snapshot.studioRecipe.requiredAuxiliaryTracks.contains(.camera) {
      snapshot.cameraSourceURL = state.cameraSourceURL
    }
    try Task.checkCancellation()
    return snapshot
  }

  /// Export trimmed video to specified URL (with zoom effects if present)
  static func exportTrimmed(
    state: VideoEditorState,
    to outputURL: URL,
    progress: @escaping (Float) -> Void
  ) async throws {
    let state = try await prepareSnapshot(for: state)
    DiagnosticLogger.shared.log(.info, .export, "Video export started", context: [
      "file": state.sourceURL.lastPathComponent,
      "hasZooms": "\(state.zoomSegments.contains { $0.isEnabled })",
      "hasBackground": "\(state.backgroundStyle != .none && state.backgroundPadding > 0)",
      "hasCustomAudio": "\(state.exportSettings.audioMode == .custom)",
      "hasSpeed": "\(state.hasSpeedSegments)",
      "hasStudioLayers": "\(state.studioRecipe.hasActiveLayers)",
      "clips": "\(state.clips.count)",
      "hasInsertedClips": "\(state.hasInsertedClips)",
      "quality": state.exportSettings.quality.exportPreset,
    ])
    let outputAccess = SandboxFileAccessManager.shared.beginAccessingURL(outputURL.deletingLastPathComponent())
    defer { outputAccess.stop() }
    let scopedOutputURL = outputAccess.url.appendingPathComponent(outputURL.lastPathComponent)

    // Guard against destroying an active source/clip file when outputURL matches a source media path:
    // render to a sibling temporary file first, then atomically replace ONLY after export succeeds.
    var protectedSourcePaths: Set<String> = [
      state.sourceURL.standardizedFileURL.path,
      state.primaryAudioSourceURL.standardizedFileURL.path,
    ]
    for clip in state.clips {
      if let clipURL = clip.url {
        protectedSourcePaths.insert(clipURL.standardizedFileURL.path)
      }
    }
    for audio in state.addedAudioClips {
      if let audioURL = audio.fileURL {
        protectedSourcePaths.insert(audioURL.standardizedFileURL.path)
      }
    }
    let needsTempStaging = protectedSourcePaths.contains(scopedOutputURL.standardizedFileURL.path)
    let renderURL: URL = if needsTempStaging {
      scopedOutputURL.deletingLastPathComponent().appendingPathComponent(
        ".\(scopedOutputURL.deletingPathExtension().lastPathComponent).export-tmp-\(UUID().uuidString).\(scopedOutputURL.pathExtension)"
      )
    } else {
      scopedOutputURL
    }
    defer {
      if needsTempStaging {
        try? FileManager.default.removeItem(at: renderURL)
      }
    }

    let hasCameraEffects = state.zoomSegments.contains { $0.isEnabled }
    let hasBackground = state.backgroundStyle != .none && state.backgroundPadding > 0
    let hasCustomAudio = state.exportSettings.requiresAudioMix
      || state.usesIndependentAudioPlayback
      || !state.addedAudioClips.isEmpty
    let hasSpeed = state.hasSpeedSegments
    // Anything beyond a single untouched primary clip needs the composition path.
    let hasSequenceEdits = state.hasSequenceEdits
    // Studio layers (cursor, camera, captions) and text overlays only render through the compositor.
    let hasStudioLayers = state.studioRecipe.hasActiveLayers
      || !state.clickSoundTimes.isEmpty
      || state.hasTextOverlays
      || state.hasActiveTransitions

    // If visual effects, custom audio, speed scaling, or a multi-clip sequence are in
    // play, use composition-based export. Speed scaling requires the composition path
    // even with no other effects (and even when muted — audio is simply dropped while
    // the video is still time-scaled).
    if hasCameraEffects || hasBackground || hasCustomAudio || hasSpeed || hasSequenceEdits || hasStudioLayers {
      try await exportWithZooms(state: state, to: renderURL, progress: progress)
      try await normalizeExportAudioForCompatibilityIfNeeded(
        at: renderURL,
        fileExtension: state.fileExtension
      )
    } else if state.exportSettings.audioMode == .mute {
      // If muted via export settings, export without audio
      try await exportVideoOnly(state: state, to: renderURL, progress: progress)
    } else {
      // Standard export without zooms
      try await exportStandard(state: state, to: renderURL, progress: progress)
      try await normalizeExportAudioForCompatibilityIfNeeded(
        at: renderURL,
        fileExtension: state.fileExtension
      )
    }

    if needsTempStaging {
      _ = try FileManager.default.replaceItemAt(scopedOutputURL, withItemAt: renderURL)
    }
  }

  /// Standard export without zoom effects
  private static func exportStandard(
    state: VideoEditorExportSnapshot,
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
      audioTimeRange: timeRange,
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

    await withTaskCancellationHandler {
      await exportSession.export()
    } onCancel: {
      exportSession.cancelExport()
    }
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
    state: VideoEditorExportSnapshot,
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
      adjustedZooms
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
        },
      uniquingKeysWith: { first, _ in first }
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

    let transform = try await sourceVideoTrack.load(.preferredTransform)
    compositionVideoTrack.preferredTransform = transform
    print("🔍 [ZoomExport] Applied video transform: \(transform)")

    let preserveVideoGaps = state.hasVideoGaps
    let usesDualTrackCrossfade = state.placements.indices.dropFirst().contains { idx in
      let prev = state.placements[idx - 1]
      let curr = state.placements[idx]
      guard abs(curr.activeStart - prev.activeEnd) <= TimelineClipTransition.abuttingGapTolerance,
            let transition = curr.clip.leadingTransition,
            transition.style == .crossfade,
            transition.isActive
      else { return false }
      return TimelineClipTransition.effectiveDuration(
        requested: transition.duration,
        outgoingClipDuration: prev.clip.duration,
        incomingClipDuration: curr.clip.duration
      ) > 0.01
    }

    var secondaryVideoTrack: AVMutableCompositionTrack?
    if usesDualTrackCrossfade {
      guard let trackB = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
      ) else {
        throw ExportError.exportFailed
      }
      trackB.preferredTransform = transform
      secondaryVideoTrack = trackB
    }

    var exportTransitions: [VideoEditorExportTransition] = []

    do {
      // Compute clip composition spans first so transitions and dual-track crossfade
      // handles align seamlessly without altering total sequence duration.
      struct ClipSpan {
        let placement: TimelineSequence.Placement
        let startSeconds: TimeInterval
        let endSeconds: TimeInterval
        let track: AVMutableCompositionTrack
      }

      var spans: [ClipSpan] = []
      var cursorSeconds: TimeInterval = 0
      var prevActiveEnd: TimeInterval = 0
      for (idx, placement) in state.placements.enumerated() {
        if preserveVideoGaps {
          let gapSeconds = max(0, placement.activeStart - prevActiveEnd)
          cursorSeconds += gapSeconds
          prevActiveEnd = placement.activeEnd
        }
        let targetTrack: AVMutableCompositionTrack = if let trackB = secondaryVideoTrack, idx % 2 == 1 {
          trackB
        } else {
          compositionVideoTrack
        }
        let endSeconds = cursorSeconds + placement.clip.duration
        spans.append(
          ClipSpan(
            placement: placement,
            startSeconds: cursorSeconds,
            endSeconds: endSeconds,
            track: targetTrack
          )
        )
        cursorSeconds = endSeconds
      }

      if !usesDualTrackCrossfade {
        // Classic single-track insertion path (unchanged for non-crossfade exports).
        var cursor = CMTime.zero
        var prevEnd: TimeInterval = 0
        for (idx, placement) in state.placements.enumerated() {
          let clip = placement.clip
          if preserveVideoGaps {
            let gapSeconds = max(0, placement.activeStart - prevEnd)
            if gapSeconds > 0.001 {
              let gapDuration = CMTime(seconds: gapSeconds, preferredTimescale: 600)
              compositionVideoTrack.insertEmptyTimeRange(
                CMTimeRange(start: cursor, duration: gapDuration)
              )
              cursor = CMTimeAdd(cursor, gapDuration)
            }
            prevEnd = placement.activeEnd
          }

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
            compositionVideoTrack.insertEmptyTimeRange(
              CMTimeRange(start: cursor, duration: clipDuration)
            )
            cursor = CMTimeAdd(cursor, clipDuration)
            continue
          }

          try compositionVideoTrack.insertTimeRange(sourceRange, of: track, at: cursor)
          cursor = CMTimeAdd(cursor, clipDuration)

          if idx > 0 {
            let prevSpan = spans[idx - 1]
            let currSpan = spans[idx]
            if abs(currSpan.placement.activeStart - prevSpan.placement.activeEnd) <= TimelineClipTransition.abuttingGapTolerance,
               let transition = clip.leadingTransition,
               transition.style == .dipToBlack,
               transition.isActive {
              let eff = TimelineClipTransition.effectiveDuration(
                requested: transition.duration,
                outgoingClipDuration: prevSpan.placement.clip.duration,
                incomingClipDuration: clip.duration
              )
              if eff > 0.01 {
                let half = eff / 2.0
                let cutSeq = currSpan.startSeconds
                exportTransitions.append(
                  VideoEditorExportTransition(
                    style: .dipToBlack,
                    startTime: sequenceMap.toOutput(max(0, cutSeq - half)),
                    cutTime: sequenceMap.toOutput(cutSeq),
                    endTime: sequenceMap.toOutput(cutSeq + half),
                    outgoingTrackID: compositionVideoTrack.trackID,
                    incomingTrackID: compositionVideoTrack.trackID
                  )
                )
              }
            }
          }
        }
        print("🔍 [ZoomExport] Inserted \(clips.count) clip(s); composition duration \(CMTimeGetSeconds(cursor))s")
      } else {
        // Dual-track A/B insertion for true GPU-blended Crossfade transitions without changing total duration.
        for (idx, span) in spans.enumerated() {
          let clip = span.placement.clip
          var leadInHandle: TimeInterval = 0
          var leadOutHandle: TimeInterval = 0

          var desiredLeadIn: TimeInterval = 0
          var desiredLeadOut: TimeInterval = 0

          if idx > 0 {
            let prev = spans[idx - 1]
            if abs(span.placement.activeStart - prev.placement.activeEnd) <= TimelineClipTransition.abuttingGapTolerance,
               let transition = clip.leadingTransition,
               transition.isActive {
              let eff = TimelineClipTransition.effectiveDuration(
                requested: transition.duration,
                outgoingClipDuration: prev.placement.clip.duration,
                incomingClipDuration: clip.duration
              )
              if eff > 0.01 {
                let half = eff / 2.0
                if transition.style == .crossfade {
                  desiredLeadIn = min(half, span.startSeconds)
                  leadInHandle = min(desiredLeadIn, clip.sourceStart)
                }
                let cutSeq = span.startSeconds
                exportTransitions.append(
                  VideoEditorExportTransition(
                    style: transition.style,
                    startTime: sequenceMap.toOutput(max(0, cutSeq - half)),
                    cutTime: sequenceMap.toOutput(cutSeq),
                    endTime: sequenceMap.toOutput(cutSeq + half),
                    outgoingTrackID: prev.track.trackID,
                    incomingTrackID: span.track.trackID
                  )
                )
              }
            }
          }

          if idx + 1 < spans.count {
            let next = spans[idx + 1]
            if abs(next.placement.activeStart - span.placement.activeEnd) <= TimelineClipTransition.abuttingGapTolerance,
               let nextTransition = next.placement.clip.leadingTransition,
               nextTransition.style == .crossfade,
               nextTransition.isActive {
              let eff = TimelineClipTransition.effectiveDuration(
                requested: nextTransition.duration,
                outgoingClipDuration: clip.duration,
                incomingClipDuration: next.placement.clip.duration
              )
              if eff > 0.01 {
                desiredLeadOut = eff / 2.0
                leadOutHandle = min(desiredLeadOut, max(0, clip.sourceDuration - clip.sourceEnd))
              }
            }
          }

          let insertSourceStart = max(0, clip.sourceStart - leadInHandle)
          let insertSourceEnd = min(clip.sourceDuration, clip.sourceEnd + leadOutHandle)
          let insertDurationSeconds = max(0.01, insertSourceEnd - insertSourceStart)
          let insertAtSeconds = max(0, span.startSeconds - leadInHandle)

          let track: AVAssetTrack? = if clip.isPrimary {
            sourceVideoTrack
          } else {
            try await state.clipAsset(for: clip).loadTracks(withMediaType: .video).first
          }
          guard let track else { continue }

          // 1. Freeze-frame lead-in handle BEFORE the main clip when untrimmed incoming clip
          // lacks extra source frames before `sourceStart` (inserted first so main clip stays anchored).
          let missingLeadIn = desiredLeadIn - leadInHandle
          if missingLeadIn > 0.01 {
            let freezeStart = max(0, span.startSeconds - desiredLeadIn)
            let sampleDur = min(1.0 / 30.0, insertDurationSeconds)
            let sampleRange = CMTimeRange(
              start: CMTime(seconds: insertSourceStart, preferredTimescale: 600),
              duration: CMTime(seconds: sampleDur, preferredTimescale: 600)
            )
            let targetAt = CMTime(seconds: freezeStart, preferredTimescale: 600)
            try span.track.insertTimeRange(sampleRange, of: track, at: targetAt)
            span.track.scaleTimeRange(
              CMTimeRange(start: targetAt, duration: sampleRange.duration),
              toDuration: CMTime(seconds: missingLeadIn, preferredTimescale: 600)
            )
          }

          // 2. Main clip range (plus any genuine source handles)
          let sourceRange = CMTimeRange(
            start: CMTime(seconds: insertSourceStart, preferredTimescale: 600),
            duration: CMTime(seconds: insertDurationSeconds, preferredTimescale: 600)
          )
          try span.track.insertTimeRange(
            sourceRange,
            of: track,
            at: CMTime(seconds: insertAtSeconds, preferredTimescale: 600)
          )

          // 3. Freeze-frame lead-out handle AFTER the main clip when untrimmed outgoing clip
          // lacks extra source frames past `sourceEnd`.
          let missingLeadOut = desiredLeadOut - leadOutHandle
          if missingLeadOut > 0.01 {
            let tailInsertAt = CMTime(seconds: insertAtSeconds + insertDurationSeconds, preferredTimescale: 600)
            let sampleDur = min(1.0 / 30.0, insertDurationSeconds)
            let sampleStart = max(0, insertSourceEnd - sampleDur)
            let sampleRange = CMTimeRange(
              start: CMTime(seconds: sampleStart, preferredTimescale: 600),
              duration: CMTime(seconds: sampleDur, preferredTimescale: 600)
            )
            try span.track.insertTimeRange(sampleRange, of: track, at: tailInsertAt)
            span.track.scaleTimeRange(
              CMTimeRange(start: tailInsertAt, duration: sampleRange.duration),
              toDuration: CMTime(seconds: missingLeadOut, preferredTimescale: 600)
            )
          }
        }
        print("🔍 [ZoomExport] Inserted \(clips.count) dual-track clip(s) with \(exportTransitions.count) transition(s)")
      }
    } catch {
      print("❌ [ZoomExport] ERROR inserting video time range: \(error)")
      DiagnosticLogger.shared.logError(.export, error, "Failed to insert video time range")
      throw error
    }

    // Apply per-segment speed scaling to the video track(s) (reverse order so earlier ranges
    // are not shifted by later scaling).
    if let speedMap {
      applySpeedScaling(to: compositionVideoTrack, map: speedMap, logPrefix: "[ZoomExport] video")
      if let secondaryVideoTrack {
        applySpeedScaling(to: secondaryVideoTrack, map: speedMap, logPrefix: "[ZoomExport] videoB")
      }
    }

    // Compute projected independent audio pieces & final extended duration first so embedded
    // and imported audio global fade-outs share the exact same end timestamp.
    let projectedAudioPieces = projectAudioClips(for: state)
    let maxAudioEnd = projectedAudioPieces.map { piece -> TimeInterval in
      let end = piece.playableStart + piece.duration
      if let speedMap {
        return end > speedMap.sequenceDuration
          ? speedMap.outputDuration + (end - speedMap.sequenceDuration)
          : speedMap.toOutput(end)
      }
      return end
    }.max() ?? 0
    let extendedDuration = CMTime(
      seconds: max(CMTimeGetSeconds(composition.duration), maxAudioEnd),
      preferredTimescale: 600
    )

    // Add embedded video clip audio tracks (skips primary audio when edited independently,
    // and skips any clip whose audio was detached onto an independent lane).
    let needsEmbeddedAudio = (!state.usesIndependentAudioPlayback && !state.audioTrackRoles.isEmpty)
      || state.clips.contains(where: { !$0.isPrimary && !$0.isAudioDetached })
    let baseAudioMix: AVMutableAudioMix? = if needsEmbeddedAudio {
      try await addAudioTracks(
        to: composition,
        from: state.asset,
        state: state,
        settings: state.exportSettings,
        roles: state.audioTrackRoles,
        speedMap: speedMap,
        fadeTotalDuration: extendedDuration,
        logPrefix: "[ZoomExport]"
      )
    } else {
      nil
    }
    let audioMix = try await addImportedAudioClips(
      to: composition,
      state: state,
      projectedPieces: projectedAudioPieces,
      baseMix: baseAudioMix,
      maxDuration: extendedDuration,
      speedMap: speedMap
    )
    let cameraTrackID = try await addCameraTrack(to: composition, state: state, clips: clips, speedMap: speedMap)
    let clickLaneURL = try addClickSoundLane(to: composition, state: state)
    defer {
      if let clickLaneURL {
        try? FileManager.default.removeItem(at: clickLaneURL)
      }
    }

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

    // Project timeline Text / Title overlays onto output time (preserving overlays placed
    // over black-screen gaps or audio tails when gaps are preserved).
    let finalOutputSeconds = max(CMTimeGetSeconds(composition.duration), CMTimeGetSeconds(extendedDuration))
    let mapTailAwareOutputTime: (TimeInterval) -> TimeInterval = { seqTime in
      if seqTime > sequenceMap.sequenceDuration {
        return sequenceMap.outputDuration + (seqTime - sequenceMap.sequenceDuration)
      }
      return sequenceMap.toOutput(seqTime)
    }
    let adjustedTextOverlays: [VideoEditorTextOverlay] = state.textOverlays.compactMap { overlay in
      if preserveVideoGaps {
        let outStart = mapTailAwareOutputTime(overlay.startTime)
        let outEnd = mapTailAwareOutputTime(overlay.endTime)
        guard outEnd > 0.001, outStart < finalOutputSeconds else { return nil }
        var copy = overlay
        copy.startTime = max(0, outStart)
        copy.duration = max(VideoEditorTextOverlay.minDuration, min(finalOutputSeconds, outEnd) - copy.startTime)
        return copy
      } else {
        let pieces = state.projectToPlaybackSequence(
          timelineRange: overlay.startTime ... overlay.endTime
        )
        guard let firstPiece = pieces.first, let lastPiece = pieces.last else { return nil }
        let outStart = sequenceMap.toOutput(firstPiece.lowerBound)
        let outEnd = sequenceMap.toOutput(lastPiece.upperBound)
        guard outEnd - outStart >= 0.05 else { return nil }
        var copy = overlay
        copy.startTime = max(0, outStart)
        copy.duration = max(VideoEditorTextOverlay.minDuration, outEnd - copy.startTime)
        return copy
      }
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
      cornerRadius: state.backgroundCornerRadius,
      studioRecipe: state.studioRecipe,
      motionBlur: state.motionBlurSettings,
      textOverlays: adjustedTextOverlays,
      exportTransitions: exportTransitions
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
        timeRange: compositionTimeRange,
        screenTrackID: compositionVideoTrack.trackID,
        secondaryVideoTrackID: secondaryVideoTrack?.trackID,
        auxiliaryTrackIDs: cameraTrackID.map { [.camera: $0] } ?? [:]
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
    exportSession.timeRange = compositionTimeRange
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
    await withTaskCancellationHandler {
      await exportSession.export()
    } onCancel: {
      exportSession.cancelExport()
    }
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
    state: VideoEditorExportSnapshot,
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

    await withTaskCancellationHandler {
      await exportSession.export()
    } onCancel: {
      exportSession.cancelExport()
    }
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
    state: VideoEditorExportSnapshot,
    settings: ExportSettings,
    roles: [VideoEditorAudioTrackRole],
    speedMap: TimelineSequenceMap?,
    fadeTotalDuration: CMTime? = nil,
    logPrefix: String
  ) async throws -> AVMutableAudioMix? {
    guard settings.shouldIncludeAudio else {
      print("\(logPrefix) Audio muted, skipping audio tracks")
      return nil
    }

    let sourceAudioTracks: [AVAssetTrack] = state.usesIndependentAudioPlayback
      ? []
      : (try await asset.loadTracks(withMediaType: .audio))
    let attachedInsertedPlacements = state.placements.filter {
      !$0.clip.isPrimary && !$0.clip.isAudioDetached
    }
    guard !sourceAudioTracks.isEmpty || !attachedInsertedPlacements.isEmpty else {
      print("\(logPrefix) No audio tracks in source or attached inserted clips")
      return nil
    }

    let preserveVideoGaps = state.hasVideoGaps
    var primaryCompositionTracks: [AVMutableCompositionTrack] = []

    // 1. Primary recording embedded audio lanes (one per mic/system role when not detached/independent).
    for sourceAudioTrack in sourceAudioTracks {
      guard let compositionAudioTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
      ) else {
        DiagnosticLogger.shared.log(.error, .export, "Failed to add composition audio track")
        throw ExportError.exportFailed
      }

      var cursor = CMTime.zero
      var prevActiveEnd: TimeInterval = 0
      var insertedAnySample = false
      for placement in state.placements {
        let clip = placement.clip
        if preserveVideoGaps {
          let gapSeconds = max(0, placement.activeStart - prevActiveEnd)
          if gapSeconds > 0.001 {
            let gapDuration = CMTime(seconds: gapSeconds, preferredTimescale: 600)
            compositionAudioTrack.insertEmptyTimeRange(
              CMTimeRange(start: cursor, duration: gapDuration)
            )
            cursor = CMTimeAdd(cursor, gapDuration)
          }
          prevActiveEnd = placement.activeEnd
        }

        let clipDuration = CMTime(seconds: clip.duration, preferredTimescale: 600)
        let sourceRange = CMTimeRange(
          start: CMTime(seconds: clip.sourceStart, preferredTimescale: 600),
          duration: clipDuration
        )

        if clip.isPrimary, !clip.isAudioDetached, !state.usesIndependentAudioPlayback {
          try compositionAudioTrack.insertTimeRange(sourceRange, of: sourceAudioTrack, at: cursor)
          insertedAnySample = true
        } else {
          compositionAudioTrack.insertEmptyTimeRange(
            CMTimeRange(start: cursor, duration: clipDuration)
          )
        }
        cursor = CMTimeAdd(cursor, clipDuration)
      }

      if insertedAnySample {
        primaryCompositionTracks.append(compositionAudioTrack)
      } else {
        composition.removeTrack(compositionAudioTrack)
      }
    }

    // 2. Non-detached inserted `.file` clips use their own backing asset (`state.clipAsset(for: clip)`)
    // on dedicated composition track(s) so custom primary mic/system muting never silences inserted clips.
    var insertedCompositionTracks: [AVMutableCompositionTrack] = []
    if !attachedInsertedPlacements.isEmpty {
      var clipTracksById: [UUID: [AVAssetTrack]] = [:]
      var maxInsertedLanes = 0
      for placement in attachedInsertedPlacements {
        let tracks = try await state.clipAsset(for: placement.clip).loadTracks(withMediaType: .audio)
        clipTracksById[placement.clip.id] = tracks
        maxInsertedLanes = max(maxInsertedLanes, tracks.count)
      }

      for laneIdx in 0 ..< maxInsertedLanes {
        guard let compositionAudioTrack = composition.addMutableTrack(
          withMediaType: .audio,
          preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
          throw ExportError.exportFailed
        }

        var cursor = CMTime.zero
        var prevActiveEnd: TimeInterval = 0
        var insertedAnySample = false
        for placement in state.placements {
          let clip = placement.clip
          if preserveVideoGaps {
            let gapSeconds = max(0, placement.activeStart - prevActiveEnd)
            if gapSeconds > 0.001 {
              let gapDuration = CMTime(seconds: gapSeconds, preferredTimescale: 600)
              compositionAudioTrack.insertEmptyTimeRange(
                CMTimeRange(start: cursor, duration: gapDuration)
              )
              cursor = CMTimeAdd(cursor, gapDuration)
            }
            prevActiveEnd = placement.activeEnd
          }

          let clipDuration = CMTime(seconds: clip.duration, preferredTimescale: 600)
          let sourceRange = CMTimeRange(
            start: CMTime(seconds: clip.sourceStart, preferredTimescale: 600),
            duration: clipDuration
          )

          if !clip.isPrimary,
             !clip.isAudioDetached,
             let tracks = clipTracksById[clip.id],
             tracks.indices.contains(laneIdx) {
            try compositionAudioTrack.insertTimeRange(sourceRange, of: tracks[laneIdx], at: cursor)
            insertedAnySample = true
          } else {
            compositionAudioTrack.insertEmptyTimeRange(
              CMTimeRange(start: cursor, duration: clipDuration)
            )
          }
          cursor = CMTimeAdd(cursor, clipDuration)
        }

        if insertedAnySample {
          insertedCompositionTracks.append(compositionAudioTrack)
        } else {
          composition.removeTrack(compositionAudioTrack)
        }
      }
    }

    let compositionAudioTracks = primaryCompositionTracks + insertedCompositionTracks
    guard !compositionAudioTracks.isEmpty else { return nil }

    // Time-scale audio with the same spans as video so A/V stays in sync.
    if let speedMap {
      for track in compositionAudioTracks {
        applySpeedScaling(to: track, map: speedMap, logPrefix: "\(logPrefix) audio")
      }
    }

    print("\(logPrefix) Added \(compositionAudioTracks.count) audio track(s)")
    let effectiveFadeDuration = fadeTotalDuration ?? composition.duration
    let compositionRange = CMTimeRange(start: .zero, duration: effectiveFadeDuration)
    let primaryMix = primaryCompositionTracks.isEmpty
      ? nil
      : makeAudioMix(
        for: primaryCompositionTracks,
        settings: settings,
        roles: roles,
        audioTimeRange: compositionRange,
        logPrefix: logPrefix
      )
    var mergedParams = (primaryMix?.inputParameters as? [AVMutableAudioMixInputParameters]) ?? []

    if !insertedCompositionTracks.isEmpty, settings.hasAudioFades || abs(settings.audioVolume - 1.0) > 0.001 {
      var insertedSettings = ExportSettings()
      insertedSettings.audioMode = abs(settings.audioVolume - 1.0) > 0.001 ? .custom : .keep
      insertedSettings.audioVolume = settings.audioVolume
      insertedSettings.setAudioFadeIn(settings.clampedAudioFadeIn)
      insertedSettings.setAudioFadeOut(settings.clampedAudioFadeOut)
      let insertedRoles = Array(repeating: VideoEditorAudioTrackRole.systemAudio, count: insertedCompositionTracks.count)
      if let insertedMix = makeAudioMix(
        for: insertedCompositionTracks,
        settings: insertedSettings,
        roles: insertedRoles,
        audioTimeRange: compositionRange,
        logPrefix: "\(logPrefix) insertedClipAudio"
      ), let extraParams = insertedMix.inputParameters as? [AVMutableAudioMixInputParameters] {
        mergedParams.append(contentsOf: extraParams)
      }
    }

    let baseMix: AVMutableAudioMix? = if mergedParams.isEmpty {
      nil
    } else {
      {
        let mix = AVMutableAudioMix()
        mix.inputParameters = mergedParams
        return mix
      }()
    }

    // Preserve pitch on scaled audio (independent of volume/custom mode).
    return applyPitchPreservation(
      to: baseMix,
      tracks: compositionAudioTracks,
      speedMap: speedMap,
      logPrefix: logPrefix
    )
  }

  private struct ProjectedAudioPiece {
    let clip: AudioTimelineClip
    let playableStart: TimeInterval
    let sourceStart: TimeInterval
    let duration: TimeInterval
    let fadeIn: TimeInterval
    let fadeOut: TimeInterval
  }

  /// Project independent/detached audio clips from the structural timeline onto the
  /// compact playable sequence (matching video, zooms, and text overlays) so head-trimmed
  /// clips never shift audio out of sync or add an unintended black tail.
  private static func projectAudioClips(for state: VideoEditorExportSnapshot) -> [ProjectedAudioPiece] {
    guard !state.addedAudioClips.isEmpty else { return [] }
    let preserveVideoGaps = state.hasVideoGaps
    let lastStructuralActiveEnd = state.placements.map(\.activeEnd).max() ?? 0
    let playableEnd = state.playbackPlacements.last?.end ?? 0

    var pieces: [ProjectedAudioPiece] = []
    for clip in state.addedAudioClips where clip.duration >= AudioTimelineClip.minDuration {
      if preserveVideoGaps {
        pieces.append(
          ProjectedAudioPiece(
            clip: clip,
            playableStart: clip.timelineStart,
            sourceStart: clip.sourceStart,
            duration: clip.duration,
            fadeIn: clip.fadeIn,
            fadeOut: clip.fadeOut
          )
        )
        continue
      }

      var clipPieces: [ProjectedAudioPiece] = []
      for placement in state.placements {
        let overlapStart = max(clip.timelineStart, placement.activeStart)
        let overlapEnd = min(clip.timelineEnd, placement.activeEnd)
        let overlapDuration = overlapEnd - overlapStart
        guard overlapDuration >= 0.05,
              let playable = state.playbackPlacements.first(where: { $0.clip.id == placement.clip.id })
        else { continue }

        let offsetInClip = overlapStart - clip.timelineStart
        let offsetInActivePlacement = overlapStart - placement.activeStart
        let piecePlayableStart = playable.start + offsetInActivePlacement
        let pieceSourceStart = min(clip.sourceEnd, clip.sourceStart + offsetInClip)
        let pieceDuration = min(overlapDuration, max(0, clip.sourceEnd - pieceSourceStart))
        guard pieceDuration >= 0.05 else { continue }

        let isFirstPiece = abs(overlapStart - clip.timelineStart) < 0.02
        let isLastPiece = abs(overlapEnd - clip.timelineEnd) < 0.02
        if let last = clipPieces.last,
           abs((last.playableStart + last.duration) - piecePlayableStart) < 0.02,
           abs((last.sourceStart + last.duration) - pieceSourceStart) < 0.02 {
          let mergedDuration = last.duration + pieceDuration
          clipPieces[clipPieces.count - 1] = ProjectedAudioPiece(
            clip: clip,
            playableStart: last.playableStart,
            sourceStart: last.sourceStart,
            duration: mergedDuration,
            fadeIn: last.fadeIn,
            fadeOut: isLastPiece ? min(clip.fadeOut, mergedDuration) : 0
          )
        } else {
          clipPieces.append(
            ProjectedAudioPiece(
              clip: clip,
              playableStart: piecePlayableStart,
              sourceStart: pieceSourceStart,
              duration: pieceDuration,
              fadeIn: isFirstPiece ? min(clip.fadeIn, pieceDuration) : 0,
              fadeOut: isLastPiece ? min(clip.fadeOut, pieceDuration) : 0
            )
          )
        }
      }

      // Preserve any intentional external-audio tail overhanging past the final active video frame.
      if !clip.isPrimary, clip.timelineEnd > lastStructuralActiveEnd + 0.02 {
        let tailStructuralStart = max(clip.timelineStart, lastStructuralActiveEnd)
        let tailDuration = clip.timelineEnd - tailStructuralStart
        if tailDuration >= 0.05 {
          let offsetInClip = tailStructuralStart - clip.timelineStart
          let tailPlayableStart = playableEnd + max(0, tailStructuralStart - lastStructuralActiveEnd)
          let tailSourceStart = min(clip.sourceEnd, clip.sourceStart + offsetInClip)
          let clampedTailDur = min(tailDuration, max(0, clip.sourceEnd - tailSourceStart))
          if clampedTailDur >= 0.05 {
            if let last = clipPieces.last,
               abs((last.playableStart + last.duration) - tailPlayableStart) < 0.02,
               abs((last.sourceStart + last.duration) - tailSourceStart) < 0.02 {
              clipPieces[clipPieces.count - 1] = ProjectedAudioPiece(
                clip: clip,
                playableStart: last.playableStart,
                sourceStart: last.sourceStart,
                duration: last.duration + clampedTailDur,
                fadeIn: last.fadeIn,
                fadeOut: min(clip.fadeOut, last.duration + clampedTailDur)
              )
            } else {
              clipPieces.append(
                ProjectedAudioPiece(
                  clip: clip,
                  playableStart: tailPlayableStart,
                  sourceStart: tailSourceStart,
                  duration: clampedTailDur,
                  fadeIn: clipPieces.isEmpty ? min(clip.fadeIn, clampedTailDur) : 0,
                  fadeOut: min(clip.fadeOut, clampedTailDur)
                )
              )
            }
          }
        }
      }

      pieces.append(contentsOf: clipPieces)
    }
    return pieces
  }

  /// Insert independent and imported audio pieces into the export composition with
  /// per-clip volume/fades AND global `exportSettings.audioFadeIn / audioFadeOut`.
  private static func addImportedAudioClips(
    to composition: AVMutableComposition,
    state: VideoEditorExportSnapshot,
    projectedPieces: [ProjectedAudioPiece],
    baseMix: AVMutableAudioMix?,
    maxDuration: CMTime,
    speedMap: TimelineSequenceMap? = nil
  ) async throws -> AVMutableAudioMix? {
    guard state.exportSettings.audioMode != .mute, !projectedPieces.isEmpty else {
      return baseMix
    }
    let maxSeconds = CMTimeGetSeconds(maxDuration)
    guard maxSeconds > 0.01 else { return baseMix }
    let preScaleMaxSeconds: TimeInterval = if let speedMap {
      max(speedMap.sequenceDuration, speedMap.sequenceDuration + max(0, maxSeconds - speedMap.outputDuration))
    } else {
      maxSeconds
    }

    let globalFades: (fadeIn: TimeInterval, fadeOut: TimeInterval) = if state.exportSettings.hasAudioFades {
      VideoEditorAudioMixFactory.resolvedFadeDurations(
        fadeIn: state.exportSettings.clampedAudioFadeIn,
        fadeOut: state.exportSettings.clampedAudioFadeOut,
        totalDuration: maxSeconds
      )
    } else {
      (0, 0)
    }

    var inputParams = (baseMix?.inputParameters as? [AVMutableAudioMixInputParameters]) ?? []
    let timescale: CMTimeScale = 600

    for piece in projectedPieces {
      let clip = piece.clip
      let clipURL: URL = clip.isPrimary ? state.primaryAudioSourceURL : (clip.fileURL ?? state.primaryAudioSourceURL)
      guard piece.playableStart < preScaleMaxSeconds,
            piece.duration >= 0.05
      else { continue }

      let clippedDuration = min(piece.duration, preScaleMaxSeconds - piece.playableStart)
      guard clippedDuration >= 0.05 else { continue }

      let audioAsset = AVURLAsset(url: clipURL)
      let loadedTracks = try await audioAsset.loadTracks(withMediaType: .audio)
      guard !loadedTracks.isEmpty else { continue }
      let tracksToMix: [AVAssetTrack] = clip.isPrimary ? loadedTracks : [loadedTracks[0]]

      for (trackIdx, sourceTrack) in tracksToMix.enumerated() {
        guard let compTrack = composition.addMutableTrack(
          withMediaType: .audio,
          preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { continue }

        let srcRange = CMTimeRange(
          start: CMTime(seconds: piece.sourceStart, preferredTimescale: timescale),
          duration: CMTime(seconds: clippedDuration, preferredTimescale: timescale)
        )
        let insertAt = CMTime(seconds: piece.playableStart, preferredTimescale: timescale)
        if piece.playableStart > 0.001 {
          compTrack.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: insertAt))
        }
        try compTrack.insertTimeRange(srcRange, of: sourceTrack, at: insertAt)

        if let speedMap {
          applySpeedScaling(to: compTrack, map: speedMap, logPrefix: "[ZoomExport] addedAudio")
        }

        let mapOut: (TimeInterval) -> TimeInterval = { seqTime in
          guard let speedMap else { return seqTime }
          if seqTime > speedMap.sequenceDuration {
            return speedMap.outputDuration + (seqTime - speedMap.sequenceDuration)
          }
          return speedMap.toOutput(seqTime)
        }
        let outStart = mapOut(piece.playableStart)
        let outEnd = max(outStart + 0.05, mapOut(piece.playableStart + clippedDuration))
        let outDuration = outEnd - outStart

        let params = AVMutableAudioMixInputParameters(track: compTrack)
        if speedMap != nil {
          let formatDescriptions = try await sourceTrack.load(.formatDescriptions)
          let sampleRate = formatDescriptions.first
            .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mSampleRate } ?? 48_000
          params.audioTimePitchAlgorithm = (sampleRate > 0 && sampleRate < 16_000) ? .timeDomain : .spectral
        }
        let roleGain: Float = if clip.isPrimary, state.audioTrackRoles.indices.contains(trackIdx) {
          state.exportSettings.effectiveVolume(for: state.audioTrackRoles[trackIdx])
        } else {
          1.0
        }
        let targetVolume = clip.volume * roleGain

        let clipFades = VideoEditorAudioMixFactory.resolvedFadeDurations(
          fadeIn: piece.fadeIn,
          fadeOut: piece.fadeOut,
          totalDuration: outDuration
        )

        // Build unified piecewise-linear volume envelope combining per-clip fades AND
        // global master `exportSettings.audioFadeIn / audioFadeOut` across `[outStart, outEnd]`.
        var breakpoints: [TimeInterval] = [outStart, outEnd]
        if clipFades.fadeIn > 0.001 {
          breakpoints.append(outStart + clipFades.fadeIn)
        }
        if clipFades.fadeOut > 0.001 {
          breakpoints.append(outEnd - clipFades.fadeOut)
        }
        if globalFades.fadeIn > 0.001, globalFades.fadeIn > outStart, globalFades.fadeIn < outEnd {
          breakpoints.append(globalFades.fadeIn)
        }
        let globalFadeOutStart = maxSeconds - globalFades.fadeOut
        if globalFades.fadeOut > 0.001, globalFadeOutStart > outStart, globalFadeOutStart < outEnd {
          breakpoints.append(globalFadeOutStart)
        }
        breakpoints.sort()

        var uniquePoints: [TimeInterval] = []
        for pt in breakpoints {
          let clampedPt = min(max(pt, outStart), outEnd)
          if let prev = uniquePoints.last, abs(clampedPt - prev) < 0.002 {
            continue
          }
          uniquePoints.append(clampedPt)
        }

        let gainAt: (TimeInterval) -> Float = { t in
          guard targetVolume > 0 else { return 0 }
          var env = 1.0
          if clipFades.fadeIn > 0.001, t < outStart + clipFades.fadeIn {
            env *= min(1.0, max(0.0, (t - outStart) / clipFades.fadeIn))
          }
          if clipFades.fadeOut > 0.001, t > outEnd - clipFades.fadeOut {
            env *= min(1.0, max(0.0, (outEnd - t) / clipFades.fadeOut))
          }
          if globalFades.fadeIn > 0.001, t < globalFades.fadeIn {
            env *= min(1.0, max(0.0, t / globalFades.fadeIn))
          }
          if globalFades.fadeOut > 0.001, t > globalFadeOutStart {
            env *= min(1.0, max(0.0, (maxSeconds - t) / globalFades.fadeOut))
          }
          return targetVolume * Float(env)
        }

        let outInsertAt = CMTime(seconds: outStart, preferredTimescale: timescale)
        if uniquePoints.count >= 2,
           clipFades.fadeIn > 0.001 || clipFades.fadeOut > 0.001 || globalFades.fadeIn > 0.001 || globalFades
           .fadeOut > 0.001 {
          for idx in 0 ..< (uniquePoints.count - 1) {
            let segStart = uniquePoints[idx]
            let segEnd = uniquePoints[idx + 1]
            let segDur = segEnd - segStart
            guard segDur >= 0.002 else { continue }
            params.setVolumeRamp(
              fromStartVolume: gainAt(segStart),
              toEndVolume: gainAt(segEnd),
              timeRange: CMTimeRange(
                start: CMTime(seconds: segStart, preferredTimescale: timescale),
                duration: CMTime(seconds: segDur, preferredTimescale: timescale)
              )
            )
          }
        } else {
          params.setVolume(targetVolume, at: outInsertAt)
        }
        inputParams.append(params)
      }
    }

    guard !inputParams.isEmpty else { return baseMix }
    let mix = baseMix ?? AVMutableAudioMix()
    mix.inputParameters = inputParams
    return mix
  }

  /// Studio camera: the sidecar laid out clip by clip like the screen track (same
  /// source windows, empty over inserted files), then speed-scaled the same way.
  private static func addCameraTrack(
    to composition: AVMutableComposition,
    state: VideoEditorExportSnapshot,
    clips _: [TimelineClip],
    speedMap: TimelineSequenceMap?
  ) async throws -> CMPersistentTrackID? {
    guard let url = state.cameraSourceURL else { return nil }
    let asset = AVURLAsset(url: url)
    guard let source = try await asset.loadTracks(withMediaType: .video).first,
          let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else { return nil }
    let cameraDuration = try await asset.load(.duration)
    let preserveVideoGaps = state.hasVideoGaps
    var cursor = CMTime.zero
    var prevActiveEnd: TimeInterval = 0
    for placement in state.placements {
      let clip = placement.clip
      if preserveVideoGaps {
        let gapSeconds = max(0, placement.activeStart - prevActiveEnd)
        if gapSeconds > 0.001 {
          let gapDuration = CMTime(seconds: gapSeconds, preferredTimescale: 600)
          track.insertEmptyTimeRange(CMTimeRange(start: cursor, duration: gapDuration))
          cursor = CMTimeAdd(cursor, gapDuration)
        }
        prevActiveEnd = placement.activeEnd
      }
      let clipDuration = CMTime(seconds: clip.duration, preferredTimescale: 600)
      let start = CMTime(seconds: clip.sourceStart, preferredTimescale: 600)
      let available = CMTimeMinimum(clipDuration, CMTimeMaximum(.zero, CMTimeSubtract(cameraDuration, start)))
      if clip.isPrimary, available > .zero {
        try track.insertTimeRange(CMTimeRange(start: start, duration: available), of: source, at: cursor)
        if available < clipDuration {
          track.insertEmptyTimeRange(CMTimeRange(
            start: CMTimeAdd(cursor, available),
            duration: CMTimeSubtract(clipDuration, available)
          ))
        }
      } else {
        track.insertEmptyTimeRange(CMTimeRange(start: cursor, duration: clipDuration))
      }
      cursor = CMTimeAdd(cursor, clipDuration)
    }
    if let speedMap {
      applySpeedScaling(to: track, map: speedMap, logPrefix: "[ZoomExport] camera")
    }
    return track.trackID
  }

  /// Studio click sound: a synthesized PCM lane placed in output time (cuts, reorder and
  /// speed are already applied to the click times). Returns the temp file to delete
  /// once the export finishes, or `nil` when there is no lane.
  private static func addClickSoundLane(
    to composition: AVMutableComposition,
    state: VideoEditorExportSnapshot
  ) throws -> URL? {
    guard state.exportSettings.shouldIncludeAudio, !state.clickSoundTimes.isEmpty, state.clickSoundVolume > 0 else {
      return nil
    }
    let duration = CMTimeGetSeconds(composition.duration)
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("snapzy-clicks-\(UUID().uuidString).caf")
    try VideoEditorClickSound.writeLane(
      times: state.clickSoundTimes, duration: duration, volume: state.clickSoundVolume, to: url
    )
    let laneAsset = AVURLAsset(url: url)
    guard let laneTrack = laneAsset.tracks(withMediaType: .audio).first,
          let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
    else {
      try? FileManager.default.removeItem(at: url)
      return nil
    }
    let range = CMTimeRange(start: .zero, duration: min(laneAsset.duration, composition.duration))
    try track.insertTimeRange(range, of: laneTrack, at: .zero)
    DiagnosticLogger.shared.log(.debug, .export, "Click sound lane added", context: [
      "clicks": "\(state.clickSoundTimes.count)",
    ])
    return url
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
    audioTimeRange: CMTimeRange? = nil,
    logPrefix: String
  ) async throws -> AVMutableAudioMix? {
    guard settings.requiresAudioMix else { return nil }

    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    guard !audioTracks.isEmpty else {
      print("\(logPrefix) Audio mix requested, but source has no audio tracks")
      return nil
    }

    return makeAudioMix(
      for: audioTracks,
      settings: settings,
      roles: roles,
      audioTimeRange: audioTimeRange,
      logPrefix: logPrefix
    )
  }

  private static func makeAudioMix(
    for audioTracks: [AVAssetTrack],
    settings: ExportSettings,
    roles: [VideoEditorAudioTrackRole],
    audioTimeRange: CMTimeRange? = nil,
    logPrefix: String
  ) -> AVMutableAudioMix? {
    guard settings.requiresAudioMix else { return nil }

    let resolvedRoles: [VideoEditorAudioTrackRole] = if roles.count == audioTracks.count {
      roles
    } else {
      VideoEditorAudioTrackRole.roles(forAudioTrackCount: audioTracks.count)
    }
    let mix = VideoEditorAudioMixFactory.makeAudioMix(
      for: audioTracks,
      settings: settings,
      roles: resolvedRoles,
      audioTimeRange: audioTimeRange
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
