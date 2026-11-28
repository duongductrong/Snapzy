//
//  VideoEditorProNLEUpgradeTests.swift
//  SnapzyTests
//
//  Comprehensive unit & real-export integration tests for:
//  - Multi-track audio lanes (auto-stacking, lane mute, vertical moves, legacy decode)
//  - Detach audio from video clips (primary & inserted, atomic Undo, non-doubled export)
//  - Close Gap & Close All Gaps on video timeline
//  - Text / Title overlays (CRUD, animation curves, CoreText render, persistence, real export)
//  - Video transitions (Crossfade dual-track A/B GPU blend + Dip to Black real export)
//  - Pro transport controls (J/K/L shuttle & ,/. single-frame stepping)
//

import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
@testable import Snapzy
import XCTest

@MainActor
final class VideoEditorProNLEUpgradeTests: XCTestCase {
  private var tempDir: URL!

  override func setUpWithError() throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("snapzy-pro-nle-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let tempDir {
      try? FileManager.default.removeItem(at: tempDir)
    }
  }

  // MARK: - 1. Multi-Track Audio Layout & Legacy Decoding

  func testMultiTrackAudioLaneLayout_autoStacksOverlappingAndReusesFreeLanes() throws {
    let a1 = AudioTimelineClip(
      source: .primary,
      name: "Voiceover",
      timelineStart: 0,
      sourceDuration: 10,
      sourceStart: 0,
      sourceEnd: 10,
      trackIndex: 0
    )
    let musicLane = AudioTimelineLaneLayout.resolvedTrackIndex(
      timelineStart: 1.0,
      timelineEnd: 9.0,
      in: [a1]
    )
    XCTAssertEqual(musicLane, 1, "Overlapping audio must auto-stack onto A2 (lane 1)")

    let a2 = AudioTimelineClip(
      source: .file(url: URL(fileURLWithPath: "/tmp/music.m4a")),
      name: "Music",
      timelineStart: 1.0,
      sourceDuration: 8.0,
      trackIndex: musicLane
    )
    let sfxLane = AudioTimelineLaneLayout.resolvedTrackIndex(
      timelineStart: 3.0,
      timelineEnd: 5.0,
      in: [a1, a2]
    )
    XCTAssertEqual(sfxLane, 2, "Third overlapping clip must stack onto A3 (lane 2)")

    // Clip placed after A1 ends reuses lane 0 automatically.
    let tailLane = AudioTimelineLaneLayout.resolvedTrackIndex(
      timelineStart: 10.5,
      timelineEnd: 14.0,
      in: [a1, a2]
    )
    XCTAssertEqual(tailLane, 0, "Non-overlapping clip should reuse lowest open lane (A1)")

    // Deduplicating legacy clips that all had trackIndex == 0 separates overlapping clips.
    let legacy = [
      AudioTimelineClip(source: .primary, name: "A", timelineStart: 0, sourceDuration: 6, trackIndex: 0),
      AudioTimelineClip(
        source: .file(url: URL(fileURLWithPath: "/tmp/b.m4a")),
        name: "B",
        timelineStart: 2,
        sourceDuration: 6,
        trackIndex: 0
      ),
    ]
    let separated = AudioTimelineLaneLayout.deduplicatingOverlaps(legacy)
    XCTAssertEqual(separated.map(\.trackIndex), [0, 1])

    // Backward compatibility: legacy JSON missing `trackIndex` decodes cleanly to lane 0.
    let legacyJSON = """
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "source": { "primary": {} },
      "name": "Legacy",
      "timelineStart": 0,
      "sourceDuration": 5,
      "sourceStart": 0,
      "sourceEnd": 5,
      "volume": 1.0,
      "isMuted": false,
      "fadeIn": 0,
      "fadeOut": 0
    }
    """
    let decoded = try JSONDecoder().decode(AudioTimelineClip.self, from: Data(legacyJSON.utf8))
    XCTAssertEqual(decoded.trackIndex, 0)
  }

  func testMultiTrackAudio_addEmptyLaneMuteMoveAndAutoStackImport() async throws {
    let videoURL = try await makeTestMovieWithAudio(name: "multi_audio_base.mov", durationSeconds: 4.0)
    let extraAudioURL = try await makeTestAudioFile(name: "music.m4a", durationSeconds: 5.0)
    let state = VideoEditorState(url: videoURL)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()

    XCTAssertEqual(state.audioClips.count, 1)
    XCTAssertEqual(state.audioLaneCount, 1)

    // Add empty track A2, verify lane count grows, then remove empty trailing track.
    state.addEmptyAudioTrack()
    XCTAssertEqual(state.audioLaneCount, 2)
    state.removeEmptyTrailingAudioTrack()
    XCTAssertEqual(state.audioLaneCount, 1)

    // Import overlapping music at t=0.5s — must auto-stack onto lane 1 (A2)!
    let imported = await state.addAudioClip(url: extraAudioURL, at: 0.5)
    let musicClip = try XCTUnwrap(imported)
    XCTAssertEqual(musicClip.trackIndex, 1)
    XCTAssertEqual(state.audioLaneCount, 2)

    // Per-lane mute affects lane 1 only.
    state.toggleAudioLaneMute(1)
    XCTAssertTrue(state.isAudioClipEffectivelyMuted(musicClip))
    XCTAssertFalse(state.isAudioClipEffectivelyMuted(state.audioClips[0]))
    state.toggleAudioLaneMute(1)
    XCTAssertFalse(state.isAudioClipEffectivelyMuted(musicClip))

    // Move music clip down to A3 (lane 2) and undo back to A2 (lane 1).
    state.moveAudioClipToAdjacentTrack(id: musicClip.id, delta: 1)
    XCTAssertEqual(state.audioClips.first(where: { $0.id == musicClip.id })?.trackIndex, 2)
    state.undo()
    XCTAssertEqual(state.audioClips.first(where: { $0.id == musicClip.id })?.trackIndex, 1)
  }

  // MARK: - 2. Detach Audio (Inserted & Primary Video Clips)

  func testDetachAudio_fromInsertedVideoClip_marksDetachedUndoesAndExports() async throws {
    let primaryURL = try await makeTestMovieWithAudio(name: "detach_primary.mov", durationSeconds: 3.0)
    let insertedURL = try await makeTestMovieWithAudio(name: "detach_inserted.mov", durationSeconds: 2.0)
    let state = VideoEditorState(url: primaryURL)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()

    let rawInsertedId = await state.insertClip(url: insertedURL, at: 1)
    let insertedId = try XCTUnwrap(rawInsertedId)
    XCTAssertEqual(state.clips.count, 2)
    XCTAssertTrue(state.canDetachAudio(forClipId: insertedId))

    let audioCountBefore = state.audioClips.count
    let detached = await state.detachAudio(fromClipId: insertedId)
    let detachedClip = try XCTUnwrap(detached)

    XCTAssertTrue(state.clips[1].isAudioDetached)
    XCTAssertFalse(state.canDetachAudio(forClipId: insertedId))
    XCTAssertEqual(state.audioClips.count, audioCountBefore + 1)
    XCTAssertEqual(detachedClip.timelineStart, 3.0, accuracy: 0.05)
    XCTAssertEqual(detachedClip.duration, 2.0, accuracy: 0.05)

    // Atomic single-step Undo restores BOTH video clip flag and audio track list!
    state.undo()
    XCTAssertFalse(state.clips[1].isAudioDetached)
    XCTAssertEqual(state.audioClips.count, audioCountBefore)

    // Redo re-applies detach and exports cleanly without error.
    state.redo()
    XCTAssertTrue(state.clips[1].isAudioDetached)

    let outputURL = tempDir.appendingPathComponent("detached_export.mov")
    try await VideoEditorExporter.exportTrimmed(state: state, to: outputURL) { _ in }
    XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    let exportedDuration = try await CMTimeGetSeconds(AVURLAsset(url: outputURL).load(.duration))
    XCTAssertEqual(exportedDuration, 5.0, accuracy: 0.25)
  }

  // MARK: - 3. Close Gap & Close All Gaps

  func testCloseGapAndCloseAllGaps_snapsClipsAndUndoes() async throws {
    let videoURL = try await makeTestMovieWithAudio(name: "gaps_source.mov", durationSeconds: 6.0)
    let state = VideoEditorState(url: videoURL)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()

    _ = try XCTUnwrap(state.splitClip(atTimeline: 2.0))
    let (middleId, thirdId) = try XCTUnwrap(state.splitClip(atTimeline: 4.0))
    XCTAssertEqual(state.clips.count, 3)

    // Move clip 2 right by 2s, then middle clip right by 1s to create two gaps.
    state.moveClipOnTimeline(id: thirdId, toActiveStart: 6.0)
    state.moveClipOnTimeline(id: middleId, toActiveStart: 3.0)
    XCTAssertEqual(state.removableVideoGaps.count, 2)
    XCTAssertTrue(state.hasRemovableVideoGaps)

    // Close only the first gap (before clip index 1).
    state.closeGap(beforeClipIndex: 1)
    XCTAssertEqual(state.removableVideoGaps.count, 1)
    XCTAssertEqual(state.placements[1].activeStart, 2.0, accuracy: 0.02)

    // Close all remaining gaps.
    state.closeAllGaps()
    XCTAssertFalse(state.hasRemovableVideoGaps)
    XCTAssertEqual(state.placements[2].activeStart, 4.0, accuracy: 0.02)

    // Undo restores gap cleanly.
    state.undo()
    XCTAssertEqual(state.removableVideoGaps.count, 1)
  }

  // MARK: - 4. Text / Title Overlays (Model, Render, Persistence, Real Export)

  func testTextOverlay_crudAnimationPersistenceUndoAndRealExport() async throws {
    // Verify animation curves directly.
    let fadeOverlay = VideoEditorTextOverlay(
      text: "Hello Snapzy",
      startTime: 1.0,
      duration: 2.0,
      animation: .fade
    )
    XCTAssertEqual(fadeOverlay.opacityAndScale(at: 0.5).opacity, 0.0, accuracy: 0.001)
    XCTAssertLessThan(fadeOverlay.opacityAndScale(at: 1.05).opacity, 0.5)
    XCTAssertEqual(fadeOverlay.opacityAndScale(at: 2.0).opacity, 1.0, accuracy: 0.001)

    let popOverlay = VideoEditorTextOverlay(
      text: "Pop Title",
      startTime: 0.0,
      duration: 2.0,
      animation: .pop
    )
    XCTAssertGreaterThan(popOverlay.opacityAndScale(at: 0.1).scale, 0.5)
    XCTAssertEqual(popOverlay.opacityAndScale(at: 1.0).scale, 1.0, accuracy: 0.001)

    // Verify pure CoreText renderer generates a crisp non-empty CIImage.
    let pill = VideoEditorTextOverlayRenderer.renderPillImage(
      for: fadeOverlay,
      canvasSize: CGSize(width: 640, height: 360)
    )
    let pillImage = try XCTUnwrap(pill)
    XCTAssertGreaterThan(pillImage.extent.width, 20)
    XCTAssertGreaterThan(pillImage.extent.height, 10)

    // State CRUD, selection mutual exclusion, Undo/Redo, and session persistence.
    let videoURL = try await makeTestMovieWithAudio(name: "text_source.mov", durationSeconds: 3.0)
    let state = VideoEditorState(url: videoURL)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()
    XCTAssertFalse(state.hasUnsavedChanges)

    let added = try XCTUnwrap(state.addTextOverlay(text: "Intro Title", at: 0.2, duration: 2.0))
    XCTAssertEqual(state.textOverlays.count, 1)
    XCTAssertEqual(state.selectedTextOverlayId, added.id)
    XCTAssertNil(state.selectedClipId)
    XCTAssertNil(state.selectedAudioClipId)
    XCTAssertTrue(state.hasUnsavedChanges)

    // Scrubbing to 1.5s while a text overlay is selected must still allow Split at playhead.
    state.seek(to: CMTime(seconds: 1.5, preferredTimescale: 600))
    XCTAssertTrue(state.canSplitAtPlayhead)

    state.updateTextOverlay(id: added.id) { item in
      item.text = "Updated Title"
      item.fontSize = 48
      item.normalizedY = 0.2
    }
    XCTAssertEqual(state.textOverlays[0].text, "Updated Title")

    // Session snapshot round-trip preserves textOverlays.
    let session = VideoEditorSessionData.snapshot(from: state, sourceSnapshotURL: videoURL)
    let encoded = try JSONEncoder().encode(PersistedVideoEditorEditState(sessionData: session))
    let decoded = try JSONDecoder().decode(PersistedVideoEditorEditState.self, from: encoded)
    XCTAssertEqual(decoded.textOverlays, state.textOverlays)

    // Duplicate & Undo/Redo.
    state.duplicateTextOverlay(id: added.id)
    XCTAssertEqual(state.textOverlays.count, 2)
    state.undo()
    XCTAssertEqual(state.textOverlays.count, 1)

    // Real GPU-composited export with Text Overlay!
    let outputURL = tempDir.appendingPathComponent("text_overlay_export.mov")
    try await VideoEditorExporter.exportTrimmed(state: state, to: outputURL) { _ in }
    XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    let exportedAsset = AVURLAsset(url: outputURL)
    let exportedDuration = try await CMTimeGetSeconds(exportedAsset.load(.duration))
    XCTAssertEqual(exportedDuration, 3.0, accuracy: 0.25)
    let tracks = try await exportedAsset.loadTracks(withMediaType: .video)
    XCTAssertEqual(tracks.count, 1)
  }

  // MARK: - 5. Video Transitions (Crossfade Dual-Track & Dip to Black Real Export)

  func testVideoTransitions_clampingUndoAndRealDualTrackExport() async throws {
    // Clamping never exceeds 45% of shorter abutting clip.
    let clamped = TimelineClipTransition.effectiveDuration(
      requested: 2.0,
      outgoingClipDuration: 1.0,
      incomingClipDuration: 4.0
    )
    XCTAssertEqual(clamped, 0.45, accuracy: 0.001)

    // Real 6s video split into 3 clips (0..2, 2..4, 4..6) with Crossfade + Dip to Black.
    let videoURL = try await makeTestMovieWithAudio(name: "transitions_source.mov", durationSeconds: 6.0)
    let state = VideoEditorState(url: videoURL)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()

    _ = try XCTUnwrap(state.splitClip(atTimeline: 2.0))
    let (clip2Id, clip3Id) = try XCTUnwrap(state.splitClip(atTimeline: 4.0))
    XCTAssertEqual(state.abuttingClipSeams.count, 2)

    state.setClipTransition(clipId: clip2Id, style: .crossfade, duration: 0.6)
    state.setClipTransition(clipId: clip3Id, style: .dipToBlack, duration: 0.5)
    XCTAssertTrue(state.hasActiveTransitions)
    XCTAssertEqual(state.clips[1].leadingTransition?.style, .crossfade)
    XCTAssertEqual(state.clips[2].leadingTransition?.style, .dipToBlack)

    // Live preview state at seam midpoints.
    let crossfadePreview = try XCTUnwrap(state.activeTransitionPreview(at: 2.0))
    XCTAssertEqual(crossfadePreview.style, .crossfade)
    XCTAssertEqual(crossfadePreview.progress, 0.5, accuracy: 0.05)

    let dipPreview = try XCTUnwrap(state.activeTransitionPreview(at: 4.0))
    XCTAssertEqual(dipPreview.style, .dipToBlack)
    XCTAssertEqual(dipPreview.dipAlpha, 1.0, accuracy: 0.05)

    // Undo / Redo transition cleanly.
    state.undo()
    XCTAssertNil(state.clips[2].leadingTransition)
    state.redo()
    XCTAssertEqual(state.clips[2].leadingTransition?.style, .dipToBlack)

    // Real dual-track Crossfade + Dip to Black GPU export!
    let outputURL = tempDir.appendingPathComponent("transitions_export.mov")
    try await VideoEditorExporter.exportTrimmed(state: state, to: outputURL) { _ in }
    XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

    let exportedAsset = AVURLAsset(url: outputURL)
    let exportedDuration = try await CMTimeGetSeconds(exportedAsset.load(.duration))
    XCTAssertEqual(exportedDuration, 6.0, accuracy: 0.25)

    // Verify frames can be decoded cleanly right at both transition seams (2.0s & 4.0s).
    let generator = AVAssetImageGenerator(asset: exportedAsset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let frameAtCrossfade = try await generator.image(at: CMTime(seconds: 2.0, preferredTimescale: 600)).image
    let frameAtDip = try await generator.image(at: CMTime(seconds: 4.0, preferredTimescale: 600)).image
    XCTAssertGreaterThan(frameAtCrossfade.width, 0)
    XCTAssertGreaterThan(frameAtDip.width, 0)
  }

  // MARK: - 6. J / K / L Shuttle & Frame Stepping (, / .)

  func testShuttleJKLAndFrameStepping_stateTransitionsAndClamping() async throws {
    let videoURL = try await makeTestMovieWithAudio(name: "shuttle_source.mov", durationSeconds: 4.0)
    let state = VideoEditorState(url: videoURL)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()

    XCTAssertEqual(state.nominalFrameRate, 30.0, accuracy: 1.0)
    XCTAssertEqual(state.playbackState.shuttleRate, 0)

    // L forward shuttle: 1x -> 2x -> 4x -> 4x
    state.shuttleForward()
    XCTAssertEqual(state.playbackState.shuttleRate, 1.0, accuracy: 0.01)
    XCTAssertTrue(state.playbackState.isPlaying)

    state.shuttleForward()
    XCTAssertEqual(state.playbackState.shuttleRate, 2.0, accuracy: 0.01)

    state.shuttleForward()
    XCTAssertEqual(state.playbackState.shuttleRate, 4.0, accuracy: 0.01)

    state.shuttleForward()
    XCTAssertEqual(state.playbackState.shuttleRate, 4.0, accuracy: 0.01)

    // K pause resets shuttle rate and stops playback.
    state.shuttlePause()
    XCTAssertEqual(state.playbackState.shuttleRate, 0.0, accuracy: 0.01)
    XCTAssertFalse(state.playbackState.isPlaying)

    // Move playhead to 2.0s and test J reverse shuttle: -1x -> -2x -> -4x -> K pause.
    state.seek(to: CMTime(seconds: 2.0, preferredTimescale: 600))
    state.shuttleReverse()
    XCTAssertEqual(state.playbackState.shuttleRate, -1.0, accuracy: 0.01)
    XCTAssertTrue(state.playbackState.isPlaying)
    XCTAssertNotNil(state.reverseShuttleTimer)

    state.shuttleReverse()
    XCTAssertEqual(state.playbackState.shuttleRate, -2.0, accuracy: 0.01)

    state.shuttleReverse()
    XCTAssertEqual(state.playbackState.shuttleRate, -4.0, accuracy: 0.01)

    state.shuttlePause()
    XCTAssertEqual(state.playbackState.shuttleRate, 0.0, accuracy: 0.01)
    XCTAssertNil(state.reverseShuttleTimer)

    // Frame stepping: `.` (+1 frame) and `,` (-1 frame)
    state.seek(to: CMTime(seconds: 1.0, preferredTimescale: 600))
    state.stepFrame(forward: true)
    let afterForward = CMTimeGetSeconds(state.playbackState.currentTime)
    XCTAssertEqual(afterForward, 1.0 + (1.0 / state.nominalFrameRate), accuracy: 0.005)

    state.stepFrame(forward: false)
    let afterBack = CMTimeGetSeconds(state.playbackState.currentTime)
    XCTAssertEqual(afterBack, 1.0, accuracy: 0.005)

    // Clamping at 0.0s never goes negative.
    state.seek(to: .zero)
    state.stepFrame(forward: false)
    XCTAssertEqual(CMTimeGetSeconds(state.playbackState.currentTime), 0.0, accuracy: 0.001)
  }

  // MARK: - 8. Ripple Cut Syncs Independent Audio Clips

  func testCutTimelineRipplesAudioClipsAndRestoresAtomicallyOnUndo() async throws {
    let url = try await makeTestMovieWithAudio(name: "ripple_audio.mov", durationSeconds: 10.0)
    let state = VideoEditorState(url: url)
    defer { state.cancelPendingPerformanceWork() }
    await state.loadMetadata()
    XCTAssertEqual(CMTimeGetSeconds(state.timelineDuration), 10.0, accuracy: 0.2)
    XCTAssertEqual(state.audioClips.count, 1)

    // Cut an interior 3s span [2.0...5.0] -> both video and primary audio shrink to 7.0s.
    let removed = state.cutTimeline(range: 2.0 ... 5.0)
    XCTAssertNotNil(removed)
    XCTAssertEqual(CMTimeGetSeconds(state.timelineDuration), 7.0, accuracy: 0.2)
    XCTAssertEqual(state.audioClips.count, 2)
    XCTAssertEqual(state.audioClips[0].timelineStart, 0.0, accuracy: 0.02)
    XCTAssertEqual(state.audioClips[0].timelineEnd, 2.0, accuracy: 0.02)
    XCTAssertEqual(state.audioClips[1].timelineStart, 2.0, accuracy: 0.02)
    XCTAssertEqual(state.audioClips[1].sourceStart, 5.0, accuracy: 0.02)
    XCTAssertEqual(state.maxAudioTimelineEnd, 7.0, accuracy: 0.2)

    // Single Undo restores both video clips and audio clips back to 10.0s.
    state.undo()
    XCTAssertEqual(CMTimeGetSeconds(state.timelineDuration), 10.0, accuracy: 0.2)
    XCTAssertEqual(state.audioClips.count, 1)
    XCTAssertEqual(state.maxAudioTimelineEnd, 10.0, accuracy: 0.2)
  }

  // MARK: - Media Fixture Builders

  /// Build a real H.264 + AAC `.mov` fixture cleanly without dual-input `AVAssetWriter`
  /// backpressure stalls: writes video via single-input `AVAssetWriter`, writes audio via
  /// `AVAudioFile`, and muxes them with `AVMutableComposition` + `AVAssetExportSession`.
  private func makeTestMovieWithAudio(name: String, durationSeconds: Double) async throws -> URL {
    let videoOnlyURL = tempDir.appendingPathComponent("vid_\(UUID().uuidString).mov")
    let audioOnlyURL = try await makeTestAudioFile(
      name: "aud_\(UUID().uuidString).caf",
      durationSeconds: durationSeconds
    )
    let outputURL = tempDir.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: outputURL)

    let writer = try AVAssetWriter(outputURL: videoOnlyURL, fileType: .mov)
    let width = 320
    let height = 180
    let fps: Int32 = 30
    let videoInput = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
      ]
    )
    videoInput.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: videoInput,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ]
    )
    writer.add(videoInput)
    XCTAssertTrue(writer.startWriting())
    writer.startSession(atSourceTime: .zero)

    let frameCount = Int(durationSeconds * Double(fps))
    let writeQueue = DispatchQueue(label: "snapzy.tests.video-writer.\(UUID().uuidString)")
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      var nextFrame = 0
      videoInput.requestMediaDataWhenReady(on: writeQueue) {
        while videoInput.isReadyForMoreMediaData, nextFrame < frameCount {
          var pixelBuffer: CVPixelBuffer?
          let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
          )
          guard status == kCVReturnSuccess, let pb = pixelBuffer else {
            videoInput.markAsFinished()
            continuation.resume(throwing: NSError(domain: "ProNLETests", code: 1))
            return
          }
          CVPixelBufferLockBaseAddress(pb, [])
          if let base = CVPixelBufferGetBaseAddress(pb) {
            let byteCount = CVPixelBufferGetBytesPerRow(pb) * height
            let fillByte = UInt8(min(255, 40 + (nextFrame / Int(fps)) * 35))
            memset(base, Int32(fillByte), byteCount)
          }
          CVPixelBufferUnlockBaseAddress(pb, [])
          let pts = CMTime(value: Int64(nextFrame), timescale: fps)
          guard adaptor.append(pb, withPresentationTime: pts) else {
            videoInput.markAsFinished()
            continuation.resume(throwing: writer.error ?? NSError(domain: "ProNLETests", code: 2))
            return
          }
          nextFrame += 1
        }
        if nextFrame >= frameCount {
          videoInput.markAsFinished()
          continuation.resume()
        }
      }
    }
    await writer.finishWriting()
    XCTAssertEqual(writer.status, .completed, "Video writer error: \(String(describing: writer.error))")

    let composition = AVMutableComposition()
    let vAsset = AVURLAsset(url: videoOnlyURL)
    let aAsset = AVURLAsset(url: audioOnlyURL)
    let vDuration = try await vAsset.load(.duration)
    let aDuration = try await aAsset.load(.duration)
    let rawVTrack = try await vAsset.loadTracks(withMediaType: .video).first
    let rawATrack = try await aAsset.loadTracks(withMediaType: .audio).first
    let vTrack = try XCTUnwrap(rawVTrack)
    let aTrack = try XCTUnwrap(rawATrack)
    let compV = try XCTUnwrap(composition.addMutableTrack(
      withMediaType: .video,
      preferredTrackID: kCMPersistentTrackID_Invalid
    ))
    let compA = try XCTUnwrap(composition.addMutableTrack(
      withMediaType: .audio,
      preferredTrackID: kCMPersistentTrackID_Invalid
    ))
    try compV.insertTimeRange(CMTimeRange(start: .zero, duration: vDuration), of: vTrack, at: .zero)
    let audioDur = CMTimeMinimum(vDuration, aDuration)
    try compA.insertTimeRange(CMTimeRange(start: .zero, duration: audioDur), of: aTrack, at: .zero)

    let exporter = try XCTUnwrap(AVAssetExportSession(
      asset: composition,
      presetName: AVAssetExportPresetHighestQuality
    ))
    exporter.outputURL = outputURL
    exporter.outputFileType = .mov
    await exporter.export()
    XCTAssertEqual(exporter.status, .completed, "Fixture mux failed: \(String(describing: exporter.error))")
    try? FileManager.default.removeItem(at: videoOnlyURL)
    try? FileManager.default.removeItem(at: audioOnlyURL)
    return outputURL
  }

  /// Build a real audio file (`.caf` or `.m4a`) via `AVAudioFile` in a few milliseconds.
  private func makeTestAudioFile(name: String, durationSeconds: Double) async throws -> URL {
    let isM4A = name.lowercased().hasSuffix(".m4a")
    let pcmURL = isM4A
      ? tempDir.appendingPathComponent("pcm_\(UUID().uuidString).caf")
      : tempDir.appendingPathComponent(name)
    let finalURL = tempDir.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: pcmURL)
    try? FileManager.default.removeItem(at: finalURL)

    let sampleRate: Double = 44100
    let frameCount = AVAudioFrameCount(max(1, Int(durationSeconds * sampleRate)))
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
    buffer.frameLength = frameCount
    if let ch = buffer.floatChannelData?[0] {
      for i in 0 ..< Int(frameCount) {
        ch[i] = sin(2.0 * .pi * 440.0 * Float(i) / Float(sampleRate)) * 0.25
      }
    }
    let file = try AVAudioFile(forWriting: pcmURL, settings: format.settings)
    try file.write(from: buffer)

    if !isM4A {
      return pcmURL
    }

    let asset = AVURLAsset(url: pcmURL)
    let exporter = try XCTUnwrap(AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A))
    exporter.outputURL = finalURL
    exporter.outputFileType = .m4a
    await exporter.export()
    XCTAssertEqual(exporter.status, .completed, "M4A encode failed: \(String(describing: exporter.error))")
    try? FileManager.default.removeItem(at: pcmURL)
    return finalURL
  }

  // MARK: - Review Round 2 Regression Coverage

  func testCloseGapAndRemoveClip_rippleDetachedAudioZoomSpeedTextAndBookmarksWithUndo() async throws {
    let videoURL = try await makeTestMovieWithAudio(name: "ripple_all_tracks.mov", durationSeconds: 6.0)
    let voiceoverURL = try await makeTestAudioFile(name: "voiceover_after_gap.caf", durationSeconds: 1.2)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()
    defer { state.cancelPendingPerformanceWork() }

    // Split at 2.0s -> Clip 0 [0..2], Clip 1 [2..6], then push Clip 1 to activeStart = 4.0s (2.0s gap).
    let (_, secondClipId) = try XCTUnwrap(state.splitClip(atTimeline: 2.0))
    state.moveClipOnTimeline(id: secondClipId, toActiveStart: 4.0)
    XCTAssertEqual(state.placements[1].activeStart, 4.0, accuracy: 0.02)

    // Detach audio from Clip 1 (lands at 4.0s) and add a voiceover clip at 4.5s.
    let rawDetached = await state.detachAudio(fromClipId: secondClipId)
    let detached = try XCTUnwrap(rawDetached)
    XCTAssertEqual(detached.timelineStart, 4.0, accuracy: 0.02)
    let rawVoiceover = await state.addAudioClip(url: voiceoverURL, at: 4.5)
    let voiceover = try XCTUnwrap(rawVoiceover)
    XCTAssertEqual(voiceover.timelineStart, 4.5, accuracy: 0.02)

    // Add Zoom, Speed, Text Overlay, and Bookmark positioned on Clip 1 after the gap.
    let zoomId = state.addZoom(at: 5.0)
    let zoomBefore = try XCTUnwrap(state.zoomSegments.first(where: { $0.id == zoomId })).startTime
    let speedId = try XCTUnwrap(state.addSpeed(range: 6.2 ... 7.2, rate: 2.0))
    let textOverlay = try XCTUnwrap(state.addTextOverlay(text: "Chapter 2", at: 4.8, duration: 1.5))
    state.seek(to: CMTime(seconds: 5.2, preferredTimescale: 600))
    state.toggleBookmarkAtPlayhead()
    let initialBookmark = try XCTUnwrap(state.timelineBookmarks.first)
    XCTAssertEqual(initialBookmark, 5.2, accuracy: 0.02)

    // Close the 2.0s gap before Clip 1 -> every downstream track must shift left by 2.0s!
    state.closeGap(beforeClipIndex: 1)
    XCTAssertEqual(state.placements[1].activeStart, 2.0, accuracy: 0.02)
    let detachedClosed = try XCTUnwrap(state.audioClips.first(where: { $0.id == detached.id }))
    XCTAssertEqual(detachedClosed.timelineStart, 2.0, accuracy: 0.02)
    let voiceoverClosed = try XCTUnwrap(state.audioClips.first(where: { $0.id == voiceover.id }))
    XCTAssertEqual(voiceoverClosed.timelineStart, 2.5, accuracy: 0.02)
    let zoomClosed = try XCTUnwrap(state.zoomSegments.first(where: { $0.id == zoomId }))
    XCTAssertEqual(zoomClosed.startTime, zoomBefore - 2.0, accuracy: 0.02)
    let speedClosed = try XCTUnwrap(state.speedSegments.first(where: { $0.id == speedId }))
    XCTAssertEqual(speedClosed.startTime, 4.2, accuracy: 0.02)
    let textClosed = try XCTUnwrap(state.textOverlays.first(where: { $0.id == textOverlay.id }))
    XCTAssertEqual(textClosed.startTime, 2.8, accuracy: 0.02)
    let bookmarkClosed = try XCTUnwrap(state.timelineBookmarks.first)
    XCTAssertEqual(bookmarkClosed, 3.2, accuracy: 0.02)

    // Single Undo restores all 6 tracks to their pre-close positions.
    state.undo()
    XCTAssertEqual(state.placements[1].activeStart, 4.0, accuracy: 0.02)
    let detachedUndone = try XCTUnwrap(state.audioClips.first(where: { $0.id == detached.id }))
    XCTAssertEqual(detachedUndone.timelineStart, 4.0, accuracy: 0.02)
    let voiceoverUndone = try XCTUnwrap(state.audioClips.first(where: { $0.id == voiceover.id }))
    XCTAssertEqual(voiceoverUndone.timelineStart, 4.5, accuracy: 0.02)
    let zoomUndone = try XCTUnwrap(state.zoomSegments.first(where: { $0.id == zoomId }))
    XCTAssertEqual(zoomUndone.startTime, zoomBefore, accuracy: 0.02)
    let speedUndone = try XCTUnwrap(state.speedSegments.first(where: { $0.id == speedId }))
    XCTAssertEqual(speedUndone.startTime, 6.2, accuracy: 0.02)
    let textUndone = try XCTUnwrap(state.textOverlays.first(where: { $0.id == textOverlay.id }))
    XCTAssertEqual(textUndone.startTime, 4.8, accuracy: 0.02)
    let bookmarkUndone = try XCTUnwrap(state.timelineBookmarks.first)
    XCTAssertEqual(bookmarkUndone, 5.2, accuracy: 0.02)

    // Deleting Clip 0 (`0..2`) also shifts downstream audio, zoom, speed, text, and bookmarks left by 2.0s.
    state.closeGap(beforeClipIndex: 1)
    let firstClipId = state.clips[0].id
    state.removeClip(id: firstClipId)
    let voiceoverAfterRemove = try XCTUnwrap(state.audioClips.first(where: { $0.id == voiceover.id }))
    XCTAssertEqual(voiceoverAfterRemove.timelineStart, 0.5, accuracy: 0.02)
    let bookmarkAfterRemove = try XCTUnwrap(state.timelineBookmarks.first)
    XCTAssertEqual(bookmarkAfterRemove, 1.2, accuracy: 0.02)

    state.undo()
    XCTAssertEqual(state.clips.count, 2)
    let voiceoverRestored = try XCTUnwrap(state.audioClips.first(where: { $0.id == voiceover.id }))
    XCTAssertEqual(voiceoverRestored.timelineStart, 2.5, accuracy: 0.02)
  }

  func testSeekDuringReverseShuttle_leavesStateCleanlyPaused() async throws {
    let videoURL = try await makeTestMovieWithAudio(name: "reverse_shuttle_seek.mov", durationSeconds: 4.0)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()
    defer { state.cancelPendingPerformanceWork() }

    state.seek(to: CMTime(seconds: 3.0, preferredTimescale: 600))
    state.shuttleReverse()
    XCTAssertTrue(state.isPlaying)
    XCTAssertEqual(state.playbackState.shuttleRate, -1.0, accuracy: 0.01)
    XCTAssertNotNil(state.reverseShuttleTimer)

    // Any seek during reverse shuttle must cleanly exit reverse shuttle into paused state.
    state.seek(to: CMTime(seconds: 1.2, preferredTimescale: 600))
    XCTAssertFalse(state.isPlaying, "Seek during reverse shuttle must not leave isPlaying == true")
    XCTAssertEqual(state.playbackState.shuttleRate, 0, accuracy: 0.001)
    XCTAssertNil(state.reverseShuttleTimer)
    XCTAssertEqual(state.player.rate, 0, accuracy: 0.001)
    XCTAssertEqual(CMTimeGetSeconds(state.currentTime), 1.2, accuracy: 0.05)
  }

  func testAudioLaneMuteUndoVolumeBoostSpeedRateMixedDetachedAndSegmentDecodeClamps() async throws {
    let primaryURL = try await makeTestMovieWithAudio(name: "mixed_primary.mov", durationSeconds: 3.0)
    let insertedVideoURL = try await makeTestMovieWithAudio(name: "mixed_inserted.mov", durationSeconds: 2.0)
    let addedAudioURL = try await makeTestAudioFile(name: "boosted_sfx.caf", durationSeconds: 2.5)

    let state = VideoEditorState(url: primaryURL)
    await state.loadMetadata()
    defer { state.cancelPendingPerformanceWork() }

    XCTAssertFalse(state.hasUnsavedChanges)

    // 1. Lane mute records Undo and updates hasUnsavedChanges.
    state.toggleAudioLaneMute(0)
    XCTAssertTrue(state.mutedAudioLanes.contains(0))
    XCTAssertTrue(state.hasUnsavedChanges)
    state.undo()
    XCTAssertFalse(state.mutedAudioLanes.contains(0))
    XCTAssertFalse(state.hasUnsavedChanges)

    // 2. AddedAudioPlayer honors volume > 1.0 (up to 2.0 via AVAudioEngine) and speed segment rate (2.0x).
    let rawSfxClip = await state.addAudioClip(url: addedAudioURL, at: 0.0, preferredTrack: 1)
    let sfxClip = try XCTUnwrap(rawSfxClip)
    state.setAudioClipVolume(id: sfxClip.id, volume: 1.8)
    _ = state.addSpeed(range: 0.0 ... 2.0, rate: 2.0)
    state.seek(to: CMTime(seconds: 0.5, preferredTimescale: 600))
    state.addedAudioPlayer.play(at: 0.5, forceSeek: true)
    let previewAudio = try XCTUnwrap(state.addedAudioPlayer.previewStateForTesting(clipId: sfxClip.id))
    let hasHardwareAudioOutput = AVAudioEngine().mainMixerNode.outputFormat(forBus: 0).channelCount > 0
    if hasHardwareAudioOutput {
      XCTAssertEqual(previewAudio.volume, 1.8, accuracy: 0.02)
    } else {
      XCTAssertEqual(previewAudio.volume, 1.0, accuracy: 0.02)
    }
    XCTAssertEqual(previewAudio.rate, 2.0, accuracy: 0.02)
    state.addedAudioPlayer.pause()

    let peakUnity = try VideoEditorAddedAudioPlayer.renderBoostedPeakForTesting(
      url: addedAudioURL,
      volume: 1.0,
      rate: 2.0
    )
    let peakBoosted = try VideoEditorAddedAudioPlayer.renderBoostedPeakForTesting(
      url: addedAudioURL,
      volume: 1.8,
      rate: 2.0
    )
    XCTAssertGreaterThan(peakUnity, 0.05)
    XCTAssertEqual(Double(peakBoosted / peakUnity), 1.8, accuracy: 0.08)

    // 3. Mixed detached primary clip + non-detached inserted `.file` clip keeps AVPlayer unmuted on `.file` clip.
    let primaryClipId = try XCTUnwrap(state.clips.first?.id)
    _ = await state.detachAudio(fromClipId: primaryClipId)
    let rawInsertedId = await state.insertClip(url: insertedVideoURL, at: 1)
    let insertedId = try XCTUnwrap(rawInsertedId)
    let insertedPlacement = try XCTUnwrap(state.placements.first(where: { $0.clip.id == insertedId }))
    state.seek(to: CMTime(seconds: insertedPlacement.activeStart + 0.3, preferredTimescale: 600))
    XCTAssertFalse(
      state.shouldMutePreviewPlayer,
      "Non-detached inserted .file clip must keep AVPlayer unmuted even when primary audio is detached"
    )

    // 4. promoteCaptionToTextOverlay picks first free lane (T2 when T1 is occupied),
    //    and refuses cleanly (returns nil without overlapping T1) when T1..T6 are all busy.
    _ = state.addTextOverlay(text: "Existing T1", at: 0.2, duration: 2.0, preferredTrack: 0)
    let cap = CaptionSegment(sourceRange: 0.3 ... 1.5, text: "Promoted Cue")
    state.setCaptions(VideoEditorCaptions(segments: [cap]))
    let promoted = try XCTUnwrap(state.promoteCaptionToTextOverlay(captionId: cap.id))
    XCTAssertEqual(promoted.trackIndex, 1)

    for lane in 2 ..< TextTimelineLaneLayout.maxLanes {
      _ = state.addTextOverlay(text: "Fill T\(lane + 1)", at: 0.2, duration: 2.0, preferredTrack: lane)
    }
    let blockedCap = CaptionSegment(sourceRange: 0.4 ... 1.2, text: "All Lanes Busy")
    state.setCaptions(VideoEditorCaptions(segments: [blockedCap]))
    XCTAssertNil(
      state.promoteCaptionToTextOverlay(captionId: blockedCap.id),
      "promoteCaptionToTextOverlay must refuse instead of stacking onto occupied T1 when T1..T6 are busy"
    )
    let overflowOverlay = try XCTUnwrap(state.addTextOverlay(text: "No Overlap", at: 0.4, duration: 1.0))
    XCTAssertGreaterThanOrEqual(overflowOverlay.startTime, 1.5 - 0.02)

    // 5. moveAudioClipToAdjacentTrack skips occupied target lane instead of overlapping.
    state.moveAudioClipToAdjacentTrack(id: sfxClip.id, delta: -1)
    let sfxAfterBlockedMove = try XCTUnwrap(state.audioClips.first(where: { $0.id == sfxClip.id }))
    XCTAssertEqual(sfxAfterBlockedMove.trackIndex, 1, "Moving onto occupied A1 must be rejected cleanly")

    // 6. Font import: failed replacement of an existing custom family restores the previous valid font!
    let candidateTTFs: [URL] = [
      URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Tahoma.ttf"),
      URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Impact.ttf"),
      URL(fileURLWithPath: "/System/Library/Fonts/SFNSMono.ttf"),
      URL(fileURLWithPath: "/System/Library/Fonts/Geneva.ttf"),
    ]
    if let validSystemTTF = candidateTTFs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
      let slugName = "replace_guard_\(UUID().uuidString.prefix(6)).ttf"
      let validCopyURL = tempDir.appendingPathComponent(slugName)
      try FileManager.default.copyItem(at: validSystemTTF, to: validCopyURL)
      let rawFirstImportedId = await VideoEditorFontManager.shared.importFontFilesAsync(from: [validCopyURL])
      let firstImportedId = try XCTUnwrap(rawFirstImportedId)
      let installedDir = VideoEditorFontResolver.storageRootURL().appendingPathComponent(firstImportedId, isDirectory: true)
      defer { try? FileManager.default.removeItem(at: installedDir) }
      XCTAssertTrue(FileManager.default.fileExists(atPath: installedDir.appendingPathComponent(slugName).path))

      // Overwrite source file with corrupt bytes using the exact same slug and attempt replacement.
      let badSubdir = tempDir.appendingPathComponent("corrupt_same_slug", isDirectory: true)
      try FileManager.default.createDirectory(at: badSubdir, withIntermediateDirectories: true)
      let corruptSameSlugURL = badSubdir.appendingPathComponent(slugName)
      try Data("corrupt-font-payload".utf8).write(to: corruptSameSlugURL)
      let failedReplace = await VideoEditorFontManager.shared.importFontFilesAsync(from: [corruptSameSlugURL])
      XCTAssertNil(failedReplace)
      XCTAssertTrue(
        FileManager.default.fileExists(atPath: installedDir.appendingPathComponent(slugName).path),
        "Failed font replacement must restore the previous valid family directory"
      )
      XCTAssertTrue(VideoEditorFontManager.shared.isFontAvailable(firstImportedId))
    }

    let bogusFontURL = tempDir.appendingPathComponent("corrupt_review_font_\(UUID().uuidString.prefix(6)).ttf")
    try Data("not-a-valid-opentype-font".utf8).write(to: bogusFontURL)
    let importedFont = await VideoEditorFontManager.shared.importFontFilesAsync(from: [bogusFontURL])
    XCTAssertNil(importedFont)
    let fontRoot = VideoEditorFontResolver.storageRootURL()
    let strayEntries = (try? FileManager.default.contentsOfDirectory(atPath: fontRoot.path)) ?? []
    XCTAssertFalse(
      strayEntries.contains(where: {
        $0.contains("corrupt-review-font") || $0.hasPrefix(".staging-") || $0.hasPrefix(".backup-")
      }),
      "Failed font import must not leave staged or backup directories behind: \(strayEntries)"
    )

    // 7. ZoomSegment & SpeedSegment hostile Codable clamping.
    let hostileZoomJSON = """
    {
      "id": "\(UUID().uuidString)",
      "startTime": -25,
      "duration": 1e300,
      "zoomLevel": 1e9,
      "zoomCenter": [-5, 99],
      "zoomType": "manual",
      "followSpeed": 999,
      "focusMargin": -10,
      "isEnabled": true
    }
    """
    let decodedZoom = try JSONDecoder().decode(ZoomSegment.self, from: Data(hostileZoomJSON.utf8))
    XCTAssertEqual(decodedZoom.startTime, 0)
    XCTAssertEqual(decodedZoom.duration, ZoomSegment.maxDuration)
    XCTAssertEqual(decodedZoom.zoomLevel, ZoomSegment.maxZoomLevel)
    XCTAssertEqual(decodedZoom.zoomCenter, CGPoint(x: 0, y: 1))

    let hostileSpeedJSON = """
    {
      "id": "\(UUID().uuidString)",
      "startTime": -10,
      "duration": 1e300,
      "rate": 0,
      "isEnabled": true
    }
    """
    let decodedSpeed = try JSONDecoder().decode(SpeedSegment.self, from: Data(hostileSpeedJSON.utf8))
    XCTAssertEqual(decodedSpeed.startTime, 0)
    XCTAssertEqual(decodedSpeed.duration, SpeedSegment.maxDuration)
    XCTAssertEqual(decodedSpeed.rate, SpeedSegment.minRate)
  }

  func testShuttleJToLUnmutesPlayer_handoffMuteFollowsIncomingClip_andInsertedClipExportAppliesGlobalVolume() async throws {
    let primaryURL = try await makeTestMovieWithAudio(name: "round3_primary.mov", durationSeconds: 2.0)
    let insertedURL = try await makeTestMovieWithAudio(name: "round3_inserted.mov", durationSeconds: 2.0)

    let state = VideoEditorState(url: primaryURL)
    await state.loadMetadata()
    defer { state.cancelPendingPerformanceWork() }

    // 1. J -> L in non-speed path (after initial seek settles) must unmute AVPlayer immediately.
    state.seek(to: CMTime(seconds: 1.2, preferredTimescale: 600))
    try await Task.sleep(nanoseconds: 120_000_000)
    state.shuttleReverse()
    XCTAssertTrue(state.player.isMuted)
    XCTAssertEqual(state.playbackState.shuttleRate, -1.0, accuracy: 0.01)

    state.shuttleForward()
    XCTAssertTrue(state.isPlaying)
    XCTAssertEqual(state.playbackState.shuttleRate, 1.0, accuracy: 0.01)
    XCTAssertFalse(state.player.isMuted, "Pressing L directly from reverse shuttle J must unmute AVPlayer")
    state.shuttlePause()

    // 2. Natural clip handoff mute follows the INCOMING clip even while playhead is still on outgoing clip.
    let (_, secondPrimaryId) = try XCTUnwrap(state.splitClip(atTimeline: 1.0))
    let firstPrimaryId = state.clips[0].id
    _ = await state.detachAudio(fromClipId: firstPrimaryId)
    let rawInsertedId = await state.insertClip(url: insertedURL, at: 1)
    let insertedId = try XCTUnwrap(rawInsertedId)
    let insertedClip = try XCTUnwrap(state.clips.first(where: { $0.id == insertedId }))
    let trailingPrimaryClip = try XCTUnwrap(state.clips.first(where: { $0.id == secondPrimaryId }))

    // Playhead still at 0.5s (inside detached primary clip -> muted), handing off to non-detached `.file` clip:
    state.seek(to: CMTime(seconds: 0.5, preferredTimescale: 600))
    XCTAssertTrue(state.player.isMuted)
    state.resumeVideoPlayback(for: insertedClip)
    XCTAssertFalse(
      state.player.isMuted,
      "Handoff from detached primary clip to non-detached inserted .file clip must unmute AVPlayer immediately"
    )

    // Now simulate playhead inside non-detached `.file` clip, handing off to primary clip (whose audio runs on independent lane):
    let insertedStart = try XCTUnwrap(state.placements.first(where: { $0.clip.id == insertedId })?.activeStart)
    state.seek(to: CMTime(seconds: insertedStart + 0.3, preferredTimescale: 600))
    XCTAssertFalse(state.player.isMuted)
    state.resumeVideoPlayback(for: trailingPrimaryClip)
    XCTAssertTrue(
      state.player.isMuted,
      "Handoff from inserted .file clip back to primary clip with independent audio lane must mute AVPlayer immediately"
    )
    state.pause()

    // 3. Export with an inserted `.file` clip and non-default global `audioVolume` (`0.25`) applies the volume!
    let exportStateUnity = VideoEditorState(url: primaryURL)
    await exportStateUnity.loadMetadata()
    defer { exportStateUnity.cancelPendingPerformanceWork() }
    _ = await exportStateUnity.insertClip(url: insertedURL, at: 1)

    let unityOutURL = tempDir.appendingPathComponent("export_inserted_unity.mp4")
    try await VideoEditorExporter.exportTrimmed(state: exportStateUnity, to: unityOutURL) { _ in }

    let exportStateAttenuated = VideoEditorState(url: primaryURL)
    await exportStateAttenuated.loadMetadata()
    defer { exportStateAttenuated.cancelPendingPerformanceWork() }
    _ = await exportStateAttenuated.insertClip(url: insertedURL, at: 1)
    var quietSettings = exportStateAttenuated.exportSettings
    quietSettings.audioMode = .custom
    quietSettings.audioVolume = 0.25
    exportStateAttenuated.updateExportSettings(quietSettings)

    let quietOutURL = tempDir.appendingPathComponent("export_inserted_quiet.mp4")
    try await VideoEditorExporter.exportTrimmed(state: exportStateAttenuated, to: quietOutURL) { _ in }

    // Measure peak PCM amplitude inside the inserted `.file` clip span (`2.3s ... 3.7s`).
    let unityInsertedPeak = try await measureAudioPeak(in: unityOutURL, range: 2.3 ... 3.7)
    let quietInsertedPeak = try await measureAudioPeak(in: quietOutURL, range: 2.3 ... 3.7)
    XCTAssertGreaterThan(unityInsertedPeak, 0.05, "Inserted .file clip must be audible at unity volume")
    let ratio = quietInsertedPeak / unityInsertedPeak
    XCTAssertEqual(
      Double(ratio),
      0.25,
      accuracy: 0.10,
      "Export must apply global audioVolume (0.25) to inserted .file clips (got ratio \(ratio))"
    )
  }

  private func measureAudioPeak(in movieURL: URL, range: ClosedRange<TimeInterval>) async throws -> Float {
    let asset = AVURLAsset(url: movieURL)
    let rawTrack = try await asset.loadTracks(withMediaType: .audio).first
    let track = try XCTUnwrap(rawTrack)
    let reader = try AVAssetReader(asset: asset)
    reader.timeRange = CMTimeRange(
      start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
      duration: CMTime(seconds: range.upperBound - range.lowerBound, preferredTimescale: 600)
    )
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
      ]
    )
    reader.add(output)
    XCTAssertTrue(reader.startReading())

    var maxAbs: Float = 0
    while let sampleBuffer = output.copyNextSampleBuffer() {
      guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
      let byteCount = CMBlockBufferGetDataLength(block)
      guard byteCount >= MemoryLayout<Float>.size else { continue }
      var bytes = [UInt8](repeating: 0, count: byteCount)
      guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount, destination: &bytes) == kCMBlockBufferNoErr else {
        continue
      }
      bytes.withUnsafeBytes { raw in
        let floats = raw.bindMemory(to: Float.self)
        for sample in floats {
          maxAbs = max(maxAbs, abs(sample))
        }
      }
    }
    return maxAbs
  }
}
