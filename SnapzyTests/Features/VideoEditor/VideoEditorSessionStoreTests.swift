//
//  VideoEditorSessionStoreTests.swift
//  SnapzyTests
//
//  Unit tests for non-destructive Video Editor session persistence.
//

import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
@testable import Snapzy
import XCTest

@MainActor
final class VideoEditorSessionStoreTests: XCTestCase {
  private var tempDirectory: URL!
  private var sessionsDirectory: URL!
  private var sourceDirectory: URL!
  private var store: VideoEditorSessionStore!

  override func setUp() {
    super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_VideoEditorSessionStore_\(UUID().uuidString)", isDirectory: true)
    sessionsDirectory = tempDirectory.appendingPathComponent("VideoEditorSessions", isDirectory: true)
    sourceDirectory = tempDirectory.appendingPathComponent("Sources", isDirectory: true)
    try? FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    store = VideoEditorSessionStore(rootDirectory: sessionsDirectory)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDirectory)
    store = nil
    tempDirectory = nil
    sessionsDirectory = nil
    sourceDirectory = nil
    super.tearDown()
  }

  func testPersistAndLoad_roundTripsTimelineEffectsAndRecordingMetadata() throws {
    let targetURL = try writeFile(named: "rendered.mov", contents: "rendered output")
    let masterURL = try writeFile(named: "master.mov", contents: "unrendered master")
    let sessionData = makeSessionData(sourceSnapshotURL: masterURL)

    XCTAssertTrue(store.persist(sessionData, for: targetURL))

    let loaded = try XCTUnwrap(store.load(for: targetURL))
    XCTAssertEqual(loaded.clips, sessionData.clips)
    XCTAssertEqual(loaded.zoomSegments, sessionData.zoomSegments)
    XCTAssertEqual(loaded.speedSegments, sessionData.speedSegments)
    XCTAssertEqual(loaded.backgroundStyle, sessionData.backgroundStyle)
    XCTAssertEqual(loaded.backgroundPadding, sessionData.backgroundPadding)
    XCTAssertEqual(loaded.backgroundShadowIntensity, sessionData.backgroundShadowIntensity)
    XCTAssertEqual(loaded.backgroundCornerRadius, sessionData.backgroundCornerRadius)
    XCTAssertEqual(loaded.backgroundAlignment, sessionData.backgroundAlignment)
    XCTAssertEqual(loaded.backgroundAspectRatio, sessionData.backgroundAspectRatio)
    XCTAssertEqual(loaded.exportSettings, sessionData.exportSettings)
    XCTAssertEqual(loaded.isMuted, sessionData.isMuted)
    XCTAssertEqual(loaded.recordingMetadata?.mouseSamples, sessionData.recordingMetadata?.mouseSamples)
    XCTAssertEqual(
      loaded.recordingMetadata?.audioSourceTrackRoles,
      sessionData.recordingMetadata?.audioSourceTrackRoles
    )

    XCTAssertEqual(loaded.sourceSnapshotURL.lastPathComponent, "source.mov")
    XCTAssertNotEqual(loaded.sourceSnapshotURL, masterURL)
    XCTAssertEqual(
      try Data(contentsOf: loaded.sourceSnapshotURL),
      try Data(contentsOf: masterURL)
    )
    XCTAssertEqual(loaded.recordingMetadata?.audioSourceURL, loaded.sourceSnapshotURL)
  }

  func testLoad_returnsNilWhenRenderedSourceSignatureChanges() throws {
    let targetURL = try writeFile(named: "rendered.mov", contents: "rendered output")
    let masterURL = try writeFile(named: "master.mov", contents: "unrendered master")
    XCTAssertTrue(store.persist(makeSessionData(sourceSnapshotURL: masterURL), for: targetURL))
    XCTAssertNotNil(store.load(for: targetURL))

    try writeFile(at: targetURL, contents: "a changed rendered output")

    XCTAssertNil(store.load(for: targetURL))
  }

  func testPreparedSourceSnapshot_survivesReplacementAndMovesToCommittedPackage() async throws {
    let targetURL = try writeFile(named: "rendered.mov", contents: "original capture")
    let originalContents = try Data(contentsOf: targetURL)
    let prepared = try await store.prepareSourceSnapshot(from: targetURL, for: targetURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.sourceURL.path))

    try writeFile(at: targetURL, contents: "newly rendered capture")
    let sessionData = makeSessionData(sourceSnapshotURL: prepared.sourceURL)

    XCTAssertTrue(
      store.persist(
        sessionData,
        for: targetURL,
        preparedSourceDirectory: prepared.directoryURL
      )
    )

    let loaded = try XCTUnwrap(store.load(for: targetURL))
    XCTAssertEqual(try Data(contentsOf: loaded.sourceSnapshotURL), originalContents)
    XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.directoryURL.path))
    XCTAssertTrue(
      loaded.sourceSnapshotURL.path.hasPrefix(sessionDirectory(for: targetURL).path)
    )
  }

  func testMoveSession_rekeysPackageAndKeepsSourceSnapshot() throws {
    let targetURL = try writeFile(named: "rendered.mov", contents: "rendered output")
    let destinationURL = sourceDirectory.appendingPathComponent("exported.mov")
    let masterURL = try writeFile(named: "master.mov", contents: "unrendered master")
    let sessionData = makeSessionData(sourceSnapshotURL: masterURL)

    XCTAssertTrue(store.persist(sessionData, for: targetURL))
    try FileManager.default.moveItem(at: targetURL, to: destinationURL)

    XCTAssertTrue(store.moveSession(from: targetURL, to: destinationURL))
    XCTAssertNil(store.load(for: targetURL))
    let loaded = try XCTUnwrap(store.load(for: destinationURL))
    XCTAssertEqual(loaded.clips, sessionData.clips)
    XCTAssertEqual(try Data(contentsOf: loaded.sourceSnapshotURL), Data("unrendered master".utf8))
    XCTAssertFalse(FileManager.default.fileExists(atPath: sessionDirectory(for: targetURL).path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: sessionDirectory(for: destinationURL).path))
  }

  func testCleanup_removesInactivePackagesButKeepsActiveMatchingPackage() throws {
    let activeURL = try writeFile(named: "active.mov", contents: "active")
    let inactiveURL = try writeFile(named: "inactive.mov", contents: "inactive")
    let activeMasterURL = try writeFile(named: "active-master.mov", contents: "active master")
    let inactiveMasterURL = try writeFile(named: "inactive-master.mov", contents: "inactive master")

    XCTAssertTrue(store.persist(makeSessionData(sourceSnapshotURL: activeMasterURL), for: activeURL))
    XCTAssertTrue(store.persist(makeSessionData(sourceSnapshotURL: inactiveMasterURL), for: inactiveURL))

    store.cleanup(keepingMediaFilePaths: [activeURL.path])

    XCTAssertNotNil(store.load(for: activeURL))
    XCTAssertFalse(FileManager.default.fileExists(atPath: sessionDirectory(for: inactiveURL).path))
  }

  func testVideoEditorState_restoresCutTimelineZoomAndSpeedFromSession() async throws {
    let videoURL = try await makeVideoFile(named: "restorable.mov")
    let assetDuration = try await AVAsset(url: videoURL).load(.duration)
    let duration = CMTimeGetSeconds(assetDuration)
    let firstClip = TimelineClip(
      source: .primary,
      sourceDuration: duration,
      sourceStart: 0,
      sourceEnd: duration / 2,
      slotStart: 0,
      slotEnd: duration / 2
    )
    let secondClip = TimelineClip(
      source: .primary,
      sourceDuration: duration,
      sourceStart: duration / 2,
      sourceEnd: duration,
      slotStart: duration / 2,
      slotEnd: duration
    )
    let zoom = ZoomSegment(startTime: 0.5, duration: 1, zoomLevel: 2.5)
    let speed = SpeedSegment(startTime: 1.5, duration: 1, rate: 4)
    var exportSettings = ExportSettings()
    exportSettings.quality = .medium
    exportSettings.audioMode = .mute
    let sessionData = VideoEditorSessionData(
      sourceSnapshotURL: videoURL,
      clips: [firstClip, secondClip],
      zoomSegments: [zoom],
      speedSegments: [speed],
      backgroundStyle: .gradient(.greenBlue),
      backgroundPadding: 20,
      exportSettings: exportSettings,
      isMuted: true
    )

    let state = VideoEditorState(url: videoURL, sessionData: sessionData)
    await state.loadMetadata()

    XCTAssertEqual(state.clips, [firstClip, secondClip])
    XCTAssertEqual(state.zoomSegments, [zoom])
    XCTAssertEqual(state.speedSegments, [speed])
    XCTAssertEqual(state.backgroundStyle, .gradient(.greenBlue))
    XCTAssertEqual(state.backgroundPadding, 20)
    XCTAssertEqual(state.exportSettings.quality, .medium)
    XCTAssertTrue(state.isMuted)
    XCTAssertFalse(state.hasUnsavedChanges)
  }

  func testVideoEditorPreview_usesScaledCompositionAtPlayhead() async throws {
    let videoURL = try await makeVideoFile(named: "preview-speed.mov")
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    XCTAssertNotNil(state.addSpeed(range: 0 ... 2, rate: 4))
    XCTAssertEqual(state.currentPreviewRate(at: .zero), 4, accuracy: 0.001)
    try await waitForScaledPreview(state)

    state.play()
    defer { state.pause() }

    for _ in 0 ..< 20 where state.player.timeControlStatus != .playing {
      try await Task.sleep(nanoseconds: 25_000_000)
    }

    XCTAssertEqual(state.player.timeControlStatus, .playing)
    XCTAssertEqual(state.player.rate, 1, accuracy: 0.001)
    XCTAssertEqual(state.player.defaultRate, 1, accuracy: 0.001)
    XCTAssertEqual(state.sequenceMap.outputDuration, 2.5, accuracy: 0.05)
    let start = state.currentTime.seconds
    try await Task.sleep(nanoseconds: 150_000_000)
    XCTAssertGreaterThan(state.currentTime.seconds - start, 0.3,
                         "The scaled composition must advance the authored 4x portion")
    if let timebase = state.player.currentItem?.timebase {
      XCTAssertEqual(CMTimebaseGetRate(timebase), 1, accuracy: 0.1)
    } else {
      XCTFail("Expected the preview player item to have a timebase")
    }
  }

  func testVideoEditorPreview_entersSpeedSegmentWithOneXTransport() async throws {
    let videoURL = try await makeVideoFile(named: "preview-speed-transition.mov")
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    XCTAssertNotNil(state.addSpeed(range: 1 ... 2, rate: 4))
    try await waitForScaledPreview(state)
    state.play()
    defer { state.pause() }

    let deadline = Date().addingTimeInterval(3)
    while state.playbackState.currentTime.seconds < 1.05, Date() < deadline {
      try await Task.sleep(nanoseconds: 25_000_000)
    }

    XCTAssertGreaterThanOrEqual(state.playbackState.currentTime.seconds, 1.05)
    XCTAssertEqual(state.currentPreviewRate(at: state.currentTime), 4, accuracy: 0.001)
    XCTAssertEqual(state.player.rate, 1, accuracy: 0.001)
    XCTAssertEqual(state.player.defaultRate, 1, accuracy: 0.001)
  }

  func testVideoEditorPreview_continuesThroughSpeedBoundariesWithZoomConfigured() async throws {
    let videoURL = try await makeVideoFile(
      named: "preview-speed-boundaries-with-zoom.mov",
      duration: 119
    )
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    _ = state.addZoom(at: 47.5)
    XCTAssertNotNil(state.addSpeed(range: 25 ... 75, rate: 8))
    state.seek(to: CMTime(seconds: 24.8, preferredTimescale: 600))
    try await waitForScaledPreview(state, at: 24.8)
    XCTAssertEqual(state.player.currentTime().seconds, 24.8, accuracy: 0.05)

    var furthestPlayerTime = state.player.currentTime().seconds
    var playbackRewound = false
    func recordPlayerTime() {
      let playerTime = state.player.currentTime().seconds
      if playerTime < furthestPlayerTime - 0.02 {
        playbackRewound = true
      }
      furthestPlayerTime = max(furthestPlayerTime, playerTime)
    }

    state.play()
    defer { state.pause() }

    let startDeadline = Date().addingTimeInterval(2)
    while state.currentTime.seconds < 25.1,
          state.isPlaying,
          Date() < startDeadline
    {
      recordPlayerTime()
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    recordPlayerTime()

    XCTAssertTrue(state.isPlaying, "Playback stopped at the speed segment start")
    XCTAssertEqual(state.player.rate, 1, accuracy: 0.001)
    XCTAssertGreaterThanOrEqual(state.currentTime.seconds, 25.1)

    let endDeadline = Date().addingTimeInterval(8)
    while state.currentTime.seconds < 75.1, state.isPlaying, Date() < endDeadline {
      recordPlayerTime()
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    recordPlayerTime()

    XCTAssertTrue(state.isPlaying, "Playback stopped at the speed segment end")
    XCTAssertGreaterThanOrEqual(state.currentTime.seconds, 75.1)
    XCTAssertEqual(state.player.rate, 1, accuracy: 0.001)
    XCTAssertFalse(playbackRewound, "Playback must not seek backward and replay frames at a speed boundary")

    state.togglePlayback()
    XCTAssertFalse(state.isPlaying, "Space/play control should report the paused state")
    state.togglePlayback()
    XCTAssertTrue(state.isPlaying, "Space/play control should resume the preview")

    let resumedFrom = state.currentTime.seconds
    let resumeDeadline = Date().addingTimeInterval(1)
    while state.currentTime.seconds <= resumedFrom + 0.05, Date() < resumeDeadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertGreaterThan(state.currentTime.seconds, resumedFrom + 0.05)
    XCTAssertEqual(state.player.rate, 1, accuracy: 0.001)
  }

  func testVideoEditorPreview_userSeekSupersedesPendingClipHandoff() async throws {
    let videoURL = try await makeVideoFile(named: "preview-handoff-user-seek.mov")
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    state.seek(to: CMTime(seconds: 2, preferredTimescale: 600))
    state.splitAtPlayhead()
    XCTAssertEqual(state.clips.count, 2)

    state.seek(to: CMTime(seconds: 1.9, preferredTimescale: 600))
    state.play()
    // Trigger the outgoing clip's end transition, then immediately override its
    // asynchronous seek with a user seek back into the first clip.
    state.handlePlaybackTick(itemTime: 2)
    state.seek(to: CMTime(seconds: 0.5, preferredTimescale: 600))
    state.play()
    defer { state.pause() }

    let deadline = Date().addingTimeInterval(2)
    while state.playbackState.currentTime.seconds < 0.7, Date() < deadline {
      try await Task.sleep(nanoseconds: 20_000_000)
    }

    XCTAssertGreaterThan(state.playbackState.currentTime.seconds, 0.6)
  }

  func testVideoEditorPreview_userSeekIntoHandoffDestinationSupersedesPendingHandoff() async throws {
    let videoURL = try await makeVideoFile(named: "preview-handoff-destination-seek.mov")
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    state.seek(to: CMTime(seconds: 2, preferredTimescale: 600))
    state.splitAtPlayhead()
    XCTAssertEqual(state.clips.count, 2)

    state.seek(to: CMTime(seconds: 1.9, preferredTimescale: 600))
    state.play()
    state.handlePlaybackTick(itemTime: 2)
    state.seek(to: CMTime(seconds: 2.4, preferredTimescale: 600))
    state.play()
    defer { state.pause() }

    let deadline = Date().addingTimeInterval(2)
    while state.playbackState.currentTime.seconds < 2.55,
          state.isPlaying,
          Date() < deadline
    {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTAssertTrue(state.isPlaying, "A stale handoff completion must not pause a newer seek")
    XCTAssertGreaterThan(state.playbackState.currentTime.seconds, 2.5)
  }

  func testVideoEditorPreview_continuesFromLatestPositionWhenTickCrossesSpeedBoundary() async throws {
    let videoURL = try await makeVideoFile(named: "preview-speed-boundary.mov", duration: 119)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    XCTAssertNotNil(state.addSpeed(range: 23 ... 76, rate: 8))
    state.seek(to: CMTime(seconds: 75, preferredTimescale: 600))
    try await waitForScaledPreview(state, at: 75)

    state.play()
    defer { state.pause() }

    // A delayed callback reports output time; the editor maps it back to the
    // structural playhead without seeking the composed player backward.
    state.handlePlaybackTick(itemTime: state.sequenceMap.toOutput(91))

    XCTAssertEqual(state.playbackState.currentTime.seconds, 91, accuracy: 0.01)
    XCTAssertEqual(state.currentPreviewRate(at: state.currentTime), 1, accuracy: 0.001)
    XCTAssertTrue(state.isPlaying, "A delayed tick must not turn playback into Pause")
    // The synthetic tick changes the displayed playhead only; actual transport
    // time remains at its position in the scaled composition.
  }

  func testVideoEditorPreview_continuesPastSpeedBoundaryInsideTrimmedClip() async throws {
    let videoURL = try await makeVideoFile(named: "preview-trimmed-speed-boundary.mov", duration: 119)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    let clipId = try XCTUnwrap(state.clips.first?.id)
    state.updateClip(id: clipId, sourceEnd: 80)
    XCTAssertNotNil(state.addSpeed(range: 23 ... 76, rate: 8))
    state.seek(to: CMTime(seconds: 75, preferredTimescale: 600))
    try await waitForScaledPreview(state, at: 75)
    state.play()
    defer { state.pause() }

    // The active clip ends at 1:20; the tick at 1:17 is just beyond the 1:16
    // speed edge and must continue at normal rate without replaying the edge.
    state.handlePlaybackTick(itemTime: state.sequenceMap.toOutput(77))

    XCTAssertEqual(state.playbackState.currentTime.seconds, 77, accuracy: 0.01)
    XCTAssertEqual(state.currentPreviewRate(at: state.currentTime), 1, accuracy: 0.001)
    XCTAssertTrue(state.isPlaying)
  }

  func testVideoEditorPreview_doesNotRunPastFastSpeedEndWhenMainQueueIsBusy() async throws {
    let videoURL = try await makeVideoFile(named: "preview-busy-speed-end.mov", duration: 12)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    XCTAssertNotNil(state.addSpeed(range: 1 ... 2, rate: 8))
    state.seek(to: CMTime(seconds: 1.2, preferredTimescale: 600))
    try await waitForScaledPreview(state, at: 1.2)

    state.play()
    defer { state.pause() }
    let playbackDeadline = Date().addingTimeInterval(2)
    while previewSequenceTime(state) < 1.25, Date() < playbackDeadline {
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    XCTAssertEqual(state.player.rate, 1, accuracy: 0.001)

    // Playback uses the scaled media timeline even while UI work blocks main.
    let blockedUntil = Date().addingTimeInterval(0.4)
    while Date() < blockedUntil {}

    XCTAssertLessThan(previewSequenceTime(state), 3,
                      "The material after the 8x segment must not be skipped")
    XCTAssertEqual(state.player.rate, 1, accuracy: 0.001)
  }

  func testVideoEditorPreview_speedEndKeepsPlayingNextSecondsAtNormalRate() async throws {
    let videoURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("docs/attachments/pin-drag-macos-27-demo.mp4")
    let segmentEnd = 5.0
    let seekTime = 0.8
    XCTAssertTrue(FileManager.default.fileExists(atPath: videoURL.path))
    for rate in [4.0, 8.0] {
      let state = VideoEditorState(url: videoURL)
      await state.loadMetadata()
      XCTAssertNotNil(state.addSpeed(range: 1 ... segmentEnd, rate: rate))
      state.seek(to: CMTime(seconds: seekTime, preferredTimescale: 600))

      let seekDeadline = Date().addingTimeInterval(8)
      let expectedOutputTime = state.sequenceMap.toOutput(seekTime)
      while (!(state.player.currentItem?.asset is AVComposition)
             || abs(state.player.currentTime().seconds - expectedOutputTime) > 0.05),
            Date() < seekDeadline {
        try await Task.sleep(nanoseconds: 5_000_000)
      }
      XCTAssertTrue(state.player.currentItem?.asset is AVComposition)
      XCTAssertEqual(state.player.currentTime().seconds, expectedOutputTime, accuracy: 0.05)
      state.play()

      let boundaryDeadline = Date().addingTimeInterval(5)
      while state.sequenceMap.toSequence(state.player.currentTime().seconds) < segmentEnd,
            Date() < boundaryDeadline {
        try await Task.sleep(nanoseconds: 2_000_000)
      }
      let boundaryWallTime = ProcessInfo.processInfo.systemUptime
      let boundarySourceTime = state.sequenceMap.toSequence(state.player.currentTime().seconds)
      let rateAtBoundary = state.player.rate

      var samples = [String]()
      for _ in 0 ..< 10 {
        try await Task.sleep(nanoseconds: 50_000_000)
        samples.append(String(format: "%.2f:%.2f@%.1f/%.1f",
                              ProcessInfo.processInfo.systemUptime - boundaryWallTime,
                              state.sequenceMap.toSequence(state.player.currentTime().seconds),
                              state.player.rate,
                              state.player.defaultRate))
      }
      let afterSourceTime = state.sequenceMap.toSequence(state.player.currentTime().seconds)
      let wallElapsed = ProcessInfo.processInfo.systemUptime - boundaryWallTime
      let sourceElapsed = afterSourceTime - boundarySourceTime
      state.pause()

      XCTAssertEqual(rateAtBoundary, 1, accuracy: 0.001)
      XCTAssertLessThan(boundarySourceTime, segmentEnd + 0.25,
                        "The first frame after the edge must not skip material; samples=\(samples)")
      XCTAssertEqual(sourceElapsed, wallElapsed, accuracy: 0.2,
                     "After a \(rate)x segment, the next seconds must run at 1x; samples=\(samples)")
    }
  }

  func testVideoEditorPreview_rebuildsAfterSpeedEditAndReturnsToSourcePlayback() async throws {
    let videoURL = try await makeVideoFile(named: "preview-speed-edit.mov", duration: 12)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()
    let speedID = try XCTUnwrap(state.addSpeed(range: 1 ... 4, rate: 4))
    state.seek(to: CMTime(seconds: 1.2, preferredTimescale: 600))
    try await waitForScaledPreview(state, at: 1.2)
    state.play()
    defer { state.pause() }

    let firstItem = state.player.currentItem
    state.updateSpeed(id: speedID, rate: 8)
    let rebuildDeadline = Date().addingTimeInterval(5)
    while (state.player.currentItem === firstItem || state.player.rate == 0),
          Date() < rebuildDeadline {
      try await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTAssertTrue(state.isPlaying)
    XCTAssertTrue(state.player.currentItem?.asset is AVComposition)
    XCTAssertEqual(state.player.rate, 1, accuracy: 0.001)
    XCTAssertEqual(state.sequenceMap.outputDuration, 9.375, accuracy: 0.05)

    state.removeSpeed(id: speedID)
    let sourceDeadline = Date().addingTimeInterval(5)
    while (state.player.currentItem?.asset is AVComposition || state.player.rate == 0),
          Date() < sourceDeadline {
      try await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTAssertTrue(state.isPlaying)
    XCTAssertFalse(state.player.currentItem?.asset is AVComposition)
    XCTAssertEqual(state.player.rate, 1, accuracy: 0.001)
  }

  func testVideoEditorPreview_seekOutOfFastSpeedResumesAtSelectedPosition() async throws {
    let videoURL = try await makeVideoFile(named: "preview-seek-out-of-speed.mov", duration: 12)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    XCTAssertNotNil(state.addSpeed(range: 1 ... 2, rate: 8))
    state.seek(to: CMTime(seconds: 1.2, preferredTimescale: 600))
    try await waitForScaledPreview(state, at: 1.2)
    state.play()
    defer { state.pause() }
    let playDeadline = Date().addingTimeInterval(2)
    while state.player.rate == 0, Date() < playDeadline {
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    XCTAssertEqual(state.player.rate, 1, accuracy: 0.001)

    state.seek(to: CMTime(seconds: 3, preferredTimescale: 600))
    let blockedUntil = Date().addingTimeInterval(0.4)
    while Date() < blockedUntil {}

    XCTAssertTrue(state.isPlaying)
    XCTAssertLessThan(previewSequenceTime(state), 4.5,
                      "A seek outside the speed range must land at the selected position")
    XCTAssertEqual(state.player.rate, 1, accuracy: 0.001)
  }

  func testVideoEditorPreview_crossesClipSeamAfterFastSpeedWithoutSkipping() async throws {
    let videoURL = try await makeVideoFile(named: "preview-handoff-out-of-speed.mov", duration: 12)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()
    state.seek(to: CMTime(seconds: 2, preferredTimescale: 600))
    state.splitAtPlayhead()
    XCTAssertEqual(state.clips.count, 2)

    XCTAssertNotNil(state.addSpeed(range: 1 ... 2, rate: 8))
    state.seek(to: CMTime(seconds: 1.2, preferredTimescale: 600))
    try await waitForScaledPreview(state, at: 1.2)
    state.play()
    defer { state.pause() }
    let playDeadline = Date().addingTimeInterval(2)
    while previewSequenceTime(state) < 2.1, Date() < playDeadline {
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    XCTAssertGreaterThan(previewSequenceTime(state), 2.1,
                         "The scaled preview must cross the split without a handoff seek")

    let blockedUntil = Date().addingTimeInterval(0.4)
    while Date() < blockedUntil {}

    XCTAssertTrue(state.isPlaying)
    XCTAssertLessThan(previewSequenceTime(state), 3.5,
                      "The clip after the speed region must continue at 1x")
    XCTAssertEqual(state.player.rate, 1, accuracy: 0.001)
  }

  func testVideoEditorPreview_playDuringPendingSeekStartsWithoutMainQueueCompletion() async throws {
    let videoURL = try await makeVideoFile(named: "preview-play-during-seek.mov", duration: 12)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    XCTAssertNotNil(state.addSpeed(range: 1 ... 2, rate: 8))
    try await waitForScaledPreview(state)
    state.seek(to: CMTime(seconds: 3, preferredTimescale: 600))
    XCTAssertEqual(state.player.rate, 0, accuracy: 0.001,
                   "The transport must stay parked while the new position is pending")
    state.play()
    if abs(state.player.currentTime().seconds - state.sequenceMap.toOutput(3)) > 0.05 {
      XCTAssertEqual(state.player.rate, 0, accuracy: 0.001,
                     "Play must not render frames from the old position")
    }
    let blockedUntil = Date().addingTimeInterval(0.4)
    while Date() < blockedUntil {}
    defer { state.pause() }

    XCTAssertTrue(state.isPlaying)
    XCTAssertGreaterThan(previewSequenceTime(state), 3.15,
                         "Play must resume after the seek even while UI completion is delayed")
    XCTAssertEqual(state.player.rate, 1, accuracy: 0.001)
  }

  // MARK: - Helpers

  private func waitForScaledPreview(
    _ state: VideoEditorState,
    at timelineTime: Double? = nil
  ) async throws {
    let deadline = Date().addingTimeInterval(5)
    while !(state.player.currentItem?.asset is AVComposition), Date() < deadline {
      try await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTAssertTrue(state.player.currentItem?.asset is AVComposition)
    if let timelineTime,
       let sequenceTime = state.playbackSequenceTime(atTimeline: timelineTime) {
      let outputTime = state.sequenceMap.toOutput(sequenceTime)
      while abs(state.player.currentTime().seconds - outputTime) > 0.05,
            Date() < deadline {
        try await Task.sleep(nanoseconds: 5_000_000)
      }
      XCTAssertEqual(state.player.currentTime().seconds, outputTime, accuracy: 0.05)
    }
  }

  private func previewSequenceTime(_ state: VideoEditorState) -> Double {
    state.sequenceMap.toSequence(state.player.currentTime().seconds)
  }

  private func makeSessionData(sourceSnapshotURL: URL) -> VideoEditorSessionData {
    let firstClipId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let secondClipId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let zoomId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    let speedId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    let clips = [
      TimelineClip(
        id: firstClipId,
        source: .primary,
        sourceDuration: 12,
        sourceStart: 1,
        sourceEnd: 4,
        slotStart: 0,
        slotEnd: 5
      ),
      TimelineClip(
        id: secondClipId,
        source: .primary,
        sourceDuration: 12,
        sourceStart: 6,
        sourceEnd: 10,
        slotStart: 5,
        slotEnd: 12
      ),
    ]
    let zoom = ZoomSegment(
      id: zoomId,
      startTime: 1.5,
      duration: 2.25,
      zoomLevel: 2.75,
      zoomCenter: CGPoint(x: 0.25, y: 0.8),
      zoomType: .auto,
      followSpeed: 0.7,
      focusMargin: 0.35
    )
    let speed = SpeedSegment(id: speedId, startTime: 6, duration: 2, rate: 4)
    let metadata = RecordingMetadata(
      coordinateSpace: .topLeftNormalized,
      captureSize: CGSize(width: 1_920, height: 1_080),
      samplesPerSecond: 60,
      mouseSamples: [
        RecordedMouseSample(time: 0, normalizedX: 0.2, normalizedY: 0.3, isInsideCapture: true),
        RecordedMouseSample(time: 1, normalizedX: 0.8, normalizedY: 0.7, isInsideCapture: true),
      ],
      audioSourceURL: sourceSnapshotURL,
      audioSourceTrackRoles: [.systemAudio, .microphone],
      audioSourceTracks: [
        RecordingAudioSourceTrack(trackID: 1, role: .systemAudio),
        RecordingAudioSourceTrack(trackID: 2, role: .microphone),
      ]
    )

    var exportSettings = ExportSettings()
    exportSettings.quality = .medium
    exportSettings.dimensionPreset = .ratio1x1
    exportSettings.audioMode = .custom
    exportSettings.audioVolume = 0.8
    exportSettings.systemAudioVolume = 0.5
    exportSettings.microphoneAudioVolume = 1.25

    return VideoEditorSessionData(
      sourceSnapshotURL: sourceSnapshotURL,
      recordingMetadata: metadata,
      clips: clips,
      zoomSegments: [zoom],
      speedSegments: [speed],
      backgroundStyle: .gradient(.bluePurple),
      backgroundPadding: 24,
      backgroundShadowIntensity: 0.65,
      backgroundCornerRadius: 18,
      backgroundAlignment: .bottomRight,
      backgroundAspectRatio: .ratio16x9,
      exportSettings: exportSettings,
      isMuted: true
    )
  }

  private func writeFile(named name: String, contents: String) throws -> URL {
    let url = sourceDirectory.appendingPathComponent(name)
    try writeFile(at: url, contents: contents)
    return url
  }

  private func writeFile(at url: URL, contents: String) throws {
    try Data(contents.utf8).write(to: url, options: .atomic)
  }

  private func makeVideoFile(named name: String, duration: TimeInterval = 4) async throws -> URL {
    let url = sourceDirectory.appendingPathComponent(name)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 64,
        AVVideoHeightKey: 64,
      ]
    )
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferWidthKey as String: 64,
        kCVPixelBufferHeightKey as String: 64,
      ]
    )
    writer.add(input)
    guard writer.startWriting() else {
      throw writer.error ?? NSError(domain: "VideoEditorSessionStoreTests", code: 1)
    }
    writer.startSession(atSourceTime: .zero)

    let frameRate: Int32 = 10
    let frameCount = Int(duration * Double(frameRate))
    for index in 0 ..< frameCount {
      while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 1_000_000)
      }

      var pixelBuffer: CVPixelBuffer?
      let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        64,
        64,
        kCVPixelFormatType_32BGRA,
        nil,
        &pixelBuffer
      )
      guard status == kCVReturnSuccess, let pixelBuffer else {
        throw NSError(domain: "VideoEditorSessionStoreTests", code: 2)
      }
      guard adaptor.append(
        pixelBuffer,
        withPresentationTime: CMTime(value: Int64(index), timescale: frameRate)
      ) else {
        throw writer.error ?? NSError(domain: "VideoEditorSessionStoreTests", code: 3)
      }
    }

    input.markAsFinished()
    try await withCheckedThrowingContinuation { continuation in
      writer.finishWriting {
        if writer.status == .completed {
          continuation.resume()
        } else {
          continuation.resume(throwing: writer.error ?? NSError(domain: "VideoEditorSessionStoreTests", code: 4))
        }
      }
    }
    return url
  }

  private func sessionDirectory(for sourceURL: URL) -> URL {
    let normalizedPath = VideoEditorSessionStore.normalizedPath(for: sourceURL)
    return sessionsDirectory.appendingPathComponent(
      VideoEditorSessionStore.pathHash(for: normalizedPath),
      isDirectory: true
    )
  }
}
