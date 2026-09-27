//
//  VideoEditorSessionStoreTests.swift
//  SnapzyTests
//
//  Unit tests for non-destructive Video Editor session persistence.
//

import AVFoundation
import Combine
import CoreGraphics
import CoreVideo
import Foundation
import SwiftUI
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

  func testVideoEditorPlayback_reachesSequenceEndRewindsOnceAndReplays() async throws {
    let videoURL = try await makeVideoFile(named: "preview-end-rewind.mov", duration: 2)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    state.play()
    defer { state.pause() }

    // Wait until the playhead is clearly moving before observing the end rewind,
    // so the first poll cannot exit on the untouched zero playhead.
    let moveDeadline = Date().addingTimeInterval(5)
    while state.playbackState.currentTime.seconds < 0.5, Date() < moveDeadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertGreaterThanOrEqual(state.playbackState.currentTime.seconds, 0.5)

    let endDeadline = Date().addingTimeInterval(10)
    while state.isPlaying, Date() < endDeadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertFalse(state.isPlaying, "Reaching the end must pause the transport")
    XCTAssertEqual(
      state.playbackState.currentTime.seconds, 0, accuracy: 0.01,
      "Reaching the end must rewind the playhead to 0"
    )
    // A stale item-end notification for the old position must not restart
    // playback or move the parked playhead.
    try await Task.sleep(nanoseconds: 300_000_000)
    XCTAssertEqual(
      state.playbackState.currentTime.seconds, 0, accuracy: 0.01,
      "A stale item-end notification must not re-rewind a parked playhead"
    )
    XCTAssertFalse(state.isPlaying)

    // Replay: the playhead must not only start but keep advancing. A single
    // threshold poll can race the tick rate, so sample twice.
    state.play()
    let replayDeadline = Date().addingTimeInterval(6)
    while state.playbackState.currentTime.seconds < 0.8, Date() < replayDeadline {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertGreaterThanOrEqual(state.playbackState.currentTime.seconds, 0.8,
                                "Replay after the end rewind must keep advancing")
    XCTAssertTrue(state.isPlaying, "Replay must stay in the playing state")
    XCTAssertEqual(state.player.rate, 1, accuracy: 0.001)
  }

  func testVideoEditorPlayback_trimmedStartRewindsAndReplays() async throws {
    let videoURL = try await makeVideoFile(named: "trimmed-start-end-rewind.mov", duration: 2)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    let clip = try XCTUnwrap(state.clips.first)
    let trimStart = 0.5337  // Off the 600-tick grid, like a dragged trim handle.
    state.updateClip(id: clip.id, sourceStart: trimStart)
    state.play()

    let endDeadline = Date().addingTimeInterval(6)
    while state.isPlaying, Date() < endDeadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertFalse(state.isPlaying, "Playback should stop after the trimmed range ends")
    XCTAssertEqual(state.playbackState.currentTime.seconds, trimStart, accuracy: 0.08)

    state.play()
    let replayDeadline = Date().addingTimeInterval(2)
    while state.playbackState.currentTime.seconds < trimStart + 0.3, Date() < replayDeadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTAssertTrue(state.isPlaying, "Playback should resume after the first natural end")
    XCTAssertGreaterThanOrEqual(
      state.playbackState.currentTime.seconds,
      trimStart + 0.3,
      "Replay should advance from the trimmed start"
    )
  }

  func testVideoEditorPlayback_trimmedStartIgnoresStaleEndDuringRewind() async throws {
    let videoURL = try await makeVideoFile(named: "trimmed-start-stale-end.mov", duration: 2)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    let clip = try XCTUnwrap(state.clips.first)
    let trimStart = 0.5337
    state.updateClip(id: clip.id, sourceStart: trimStart)
    state.handlePlaybackTick(itemTime: 2)
    state.player.seek(
      to: CMTime(seconds: 1.95, preferredTimescale: 600),
      toleranceBefore: .zero,
      toleranceAfter: .zero,
      completionHandler: { _ in }
    )
    try await Task.sleep(nanoseconds: 150_000_000)
    state.play()

    let replayDeadline = Date().addingTimeInterval(3)
    while state.playbackState.currentTime.seconds < trimStart + 0.3, Date() < replayDeadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTAssertGreaterThanOrEqual(
      state.playbackState.currentTime.seconds,
      trimStart + 0.3,
      "A stale end notification must not trap replay at the trimmed start"
    )
  }

  func testSeek_offGridTrimPointsSnapInsideActiveMaterial() async throws {
    let videoURL = try await makeVideoFile(named: "off-grid-trim-snap.mov", duration: 2)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    let clip = try XCTUnwrap(state.clips.first)
    state.updateClip(id: clip.id, sourceStart: 0.5337, sourceEnd: 1.5337)

    // Rounding to the nearest 1/600 tick would land just outside either trim point,
    // on trimmed-out footage that the transport cannot seek to.
    state.seek(to: .zero)
    let start = state.playbackState.currentTime.seconds
    XCTAssertTrue(state.isPlayableMaterial(atSequence: start), "Snapped in-point \(start) must be playable")
    XCTAssertEqual(start, 0.5337, accuracy: 1.0 / 600)

    state.seek(to: CMTime(seconds: 2, preferredTimescale: 600))
    let end = state.playbackState.currentTime.seconds
    XCTAssertTrue(state.isPlayableMaterial(atSequence: end), "Snapped out-point \(end) must be playable")
    XCTAssertEqual(end, 1.5337, accuracy: 1.0 / 600)
  }

  func testVideoEditorPlayback_endTickParksAtZeroWithoutEndFlashAndReplayReanchors() async throws {
    let videoURL = try await makeVideoFile(named: "playback-end-reanchor.mov", duration: 2)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    state.seek(to: CMTime(seconds: 1.5, preferredTimescale: 600))
    state.play()
    XCTAssertEqual(state.playbackState.currentTime.seconds, 1.5, accuracy: 0.01)
    XCTAssertTrue(state.isPlaying)

    // The end tick must snap the playhead straight to 0 synchronously — the
    // parked end position must never flash onto the playhead first.
    state.handlePlaybackTick(itemTime: 2.0)
    XCTAssertEqual(state.playbackState.currentTime.seconds, 0, accuracy: 0.001,
                   "The end rewind must not publish the parked end position")
    XCTAssertFalse(state.isPlaying)

    // Wait for the rewind seek to land at 0, then simulate the field failure:
    // the transport slides back toward the item end while the playhead claims 0
    // (a rewind seek that never landed / was discarded by the timebase). The
    // raw seek parks out-of-band; one observer tick publishes its position,
    // after which the playhead is re-claimed as 0 with no further ticks.
    let landedDeadline = Date().addingTimeInterval(3)
    while abs(state.player.currentTime().seconds) > 0.05, Date() < landedDeadline {
      try await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTAssertEqual(state.player.currentTime().seconds, 0, accuracy: 0.05)
    state.player.seek(
      to: CMTime(seconds: 1.95, preferredTimescale: 600),
      toleranceBefore: .zero,
      toleranceAfter: .zero,
      completionHandler: { _ in }
    )
    try await Task.sleep(nanoseconds: 250_000_000)
    state.playbackState.setCurrentTime(.zero)

    // The user presses Play while the playhead claims 0 and the transport is
    // parked at the end. Playback must re-anchor to the playhead position
    // instead of looping end → rewind → parked.
    state.play()
    defer { state.pause() }
    XCTAssertLessThanOrEqual(state.playbackState.currentTime.seconds, 0.05,
                             "Play must re-anchor the parked transport to the playhead's claim")
    XCTAssertTrue(state.isPlaying)
    let replayDeadline = Date().addingTimeInterval(5)
    while state.playbackState.currentTime.seconds < 0.5, Date() < replayDeadline {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertGreaterThanOrEqual(state.playbackState.currentTime.seconds, 0.5,
                                "Replay must keep advancing after the re-anchor")
    XCTAssertEqual(state.player.rate, 1, accuracy: 0.001)
  }

  /// Field repro: playback runs to the item's TRUE end (main queue blocked from the
  /// start, so no tick can rewind first and the item genuinely plays to its end),
  /// then the rewind issues its zero-tolerance seek to 0. Replay must actually advance.
  func testVideoEditorPlayback_transportTrulyEndsThenRewindAndReplay() async throws {
    let videoURL = try await makeVideoFile(named: "playback-true-end.mov", duration: 2)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    state.seek(to: CMTime(seconds: 1.7, preferredTimescale: 600))
    state.play()
    defer { state.pause() }

    // Block the main queue immediately: the pending seek lands via the rate
    // controller's own queue, playback runs 1.7 → 2.0 (~0.3s wall time) and the
    // item genuinely plays to its end while ticks cannot intervene.
    let blockedUntil = Date().addingTimeInterval(1.2)
    while Date() < blockedUntil {}

    // Let the queued end notification + end tick process the rewind.
    let rewindDeadline = Date().addingTimeInterval(5)
    while !state.playbackState.currentTime.seconds.isZero, Date() < rewindDeadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertEqual(
      state.playbackState.currentTime.seconds, 0, accuracy: 0.01,
      "The playhead must claim 0 after the end rewind"
    )

    // The transport must have actually repositioned to the start too.
    let transportTime = state.player.currentTime().seconds
    XCTAssertLessThanOrEqual(
      transportTime, 0.1,
      "The rewind seek must reposition the transport to the start (item ended at \(transportTime))"
    )

    // Replay: pressing Play must actually move the video.
    state.play()
    let resumedDeadline = Date().addingTimeInterval(2)
    while state.player.rate == 0, Date() < resumedDeadline {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertEqual(state.player.rate, 1, accuracy: 0.001,
                   "Play must start the transport after the end rewind")
    let advancedDeadline = Date().addingTimeInterval(2)
    while state.player.currentTime().seconds < 0.5, Date() < advancedDeadline {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertGreaterThanOrEqual(state.player.currentTime().seconds, 0.5,
                                "Replay after a true end rewind must advance the transport")
  }

  /// Field repro with a trimmed in-point: the item genuinely plays to its end, then
  /// the rewind targets the trimmed start instead of 0. Replay must advance from there.
  func testVideoEditorPlayback_trimmedStartTransportTrulyEndsThenRewindAndReplay() async throws {
    let videoURL = try await makeVideoFile(named: "trimmed-start-true-end.mov", duration: 2)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    let clip = try XCTUnwrap(state.clips.first)
    let trimStart = 0.5337
    state.updateClip(id: clip.id, sourceStart: trimStart)
    state.seek(to: CMTime(seconds: 1.7, preferredTimescale: 600))
    state.play()
    defer { state.pause() }

    let blockedUntil = Date().addingTimeInterval(1.2)
    while Date() < blockedUntil {}

    let rewindDeadline = Date().addingTimeInterval(5)
    while abs(state.playbackState.currentTime.seconds - trimStart) > 0.01, Date() < rewindDeadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertEqual(state.playbackState.currentTime.seconds, trimStart, accuracy: 0.01)
    try await Task.sleep(nanoseconds: 300_000_000)
    let transportTime = state.player.currentTime().seconds
    XCTAssertEqual(
      transportTime, trimStart, accuracy: 0.1,
      "The rewind seek must reposition the transport to the trimmed start (at \(transportTime))"
    )

    state.play()
    let advancedDeadline = Date().addingTimeInterval(3)
    while state.playbackState.currentTime.seconds < trimStart + 0.5, Date() < advancedDeadline {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertTrue(state.isPlaying, "Replay after a true end rewind must keep playing")
    XCTAssertGreaterThanOrEqual(state.playbackState.currentTime.seconds, trimStart + 0.5,
                                "Replay after a true end rewind must advance from the trimmed start")
  }

  func testVideoEditorPreview_reachesCompositionEndRewindsOnceAndReplays() async throws {
    let videoURL = try await makeVideoFile(named: "preview-composition-end-rewind.mov", duration: 3)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    XCTAssertNotNil(state.addSpeed(range: 1 ... 2, rate: 8))
    try await waitForScaledPreview(state)
    state.seek(to: CMTime(seconds: 2.5, preferredTimescale: 600))
    try await waitForScaledPreview(state, at: 2.5)
    state.play()
    defer { state.pause() }

    let endDeadline = Date().addingTimeInterval(10)
    while state.isPlaying, Date() < endDeadline {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertFalse(state.isPlaying, "Reaching the composition end must pause the transport")
    XCTAssertEqual(state.playbackState.currentTime.seconds, 0, accuracy: 0.01,
                   "The composition end must rewind the playhead to 0")
    try await Task.sleep(nanoseconds: 300_000_000)
    XCTAssertEqual(state.playbackState.currentTime.seconds, 0, accuracy: 0.01,
                   "A stale end notification must not re-rewind the parked playhead")
    XCTAssertFalse(state.isPlaying)

    state.play()
    let replayDeadline = Date().addingTimeInterval(6)
    while state.playbackState.currentTime.seconds < 0.8, Date() < replayDeadline {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertGreaterThanOrEqual(state.playbackState.currentTime.seconds, 0.8,
                                "Replay after the composition end rewind must keep advancing")
    XCTAssertTrue(state.isPlaying)
    XCTAssertEqual(state.player.rate, 1, accuracy: 0.001)
  }

  // MARK: - Segment Interaction and Cache Regressions

  func testZoomGesture_manyUpdatesUndoAndRedoAsOneEdit() async throws {
    let videoURL = try await makeVideoFile(named: "zoom-gesture.mov", duration: 12)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()
    let id = state.addZoom(at: 3)
    let original = try XCTUnwrap(state.zoomSegments.first)
    state.markAsSaved()

    state.beginZoomEdit(id: id)
    for index in 1 ... 60 {
      state.updateZoom(id: id, startTime: 1 + Double(index) / 60, zoomLevel: 2 + CGFloat(index) / 60)
    }
    state.endZoomEdit(id: id)
    let final = try XCTUnwrap(state.zoomSegments.first)
    XCTAssertEqual(final.startTime, 2, accuracy: 0.0001)
    XCTAssertEqual(final.zoomLevel, 3, accuracy: 0.0001)
    XCTAssertTrue(state.canUndo)

    state.undo()
    XCTAssertEqual(state.zoomSegments, [original])
    XCTAssertFalse(state.canUndo, "One drag must consume only one undo entry")
    XCTAssertTrue(state.canRedo)
    state.redo()
    XCTAssertEqual(state.zoomSegments, [final])
    XCTAssertFalse(state.canRedo)
  }

  func testSpeedGesture_finalModelAndSequenceMapUseReleasedRange() async throws {
    let videoURL = try await makeVideoFile(named: "speed-gesture.mov", duration: 12)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()
    let id = try XCTUnwrap(state.addSpeed(range: 1 ... 3, rate: 2))
    let original = try XCTUnwrap(state.speedSegments.first)
    state.markAsSaved()
    let duration = state.sequenceDuration
    XCTAssertEqual(state.sequenceMap.outputDuration, duration - 1, accuracy: 0.0001)

    state.beginSpeedEdit(id: id)
    for index in 1 ... 60 {
      state.updateSpeed(id: id, rate: 4, startTime: 1 + Double(index) / 60, duration: 3)
    }
    state.endSpeedEdit(id: id)
    let final = try XCTUnwrap(state.speedSegments.first)
    XCTAssertEqual(final.startTime, 2, accuracy: 0.0001)
    XCTAssertEqual(final.duration, 3, accuracy: 0.0001)
    XCTAssertEqual(state.sequenceMap.outputDuration, duration - 2.25, accuracy: 0.0001)
    XCTAssertTrue(state.hasUnsavedChanges, "Dirty tracking must read the stored final value")

    state.undo()
    XCTAssertEqual(state.speedSegments, [original])
    XCTAssertEqual(state.sequenceMap.outputDuration, duration - 1, accuracy: 0.0001)
    XCTAssertFalse(state.canUndo)
    state.redo()
    XCTAssertEqual(state.speedSegments, [final])
    XCTAssertEqual(state.sequenceMap.outputDuration, duration - 2.25, accuracy: 0.0001)
  }

  func testSegmentNoOpGestures_doNotPublishOrCreateUndoEntries() async throws {
    let videoURL = try await makeVideoFile(named: "segment-noop.mov", duration: 12)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()
    let zoomID = state.addZoom(at: 3)
    let speedID = try XCTUnwrap(state.addSpeed(range: 6 ... 8, rate: 2))
    let zoom = try XCTUnwrap(state.zoomSegments.first)
    let speed = try XCTUnwrap(state.speedSegments.first)
    state.markAsSaved()
    var zoomPublications = 0
    var speedPublications = 0
    let zoomSubscription = state.$zoomSegments.dropFirst().sink { _ in zoomPublications += 1 }
    let speedSubscription = state.$speedSegments.dropFirst().sink { _ in speedPublications += 1 }
    defer {
      zoomSubscription.cancel()
      speedSubscription.cancel()
    }

    state.beginZoomEdit(id: zoomID)
    state.beginSpeedEdit(id: speedID)
    for _ in 0 ..< 60 {
      state.updateZoom(id: zoomID, startTime: zoom.startTime, duration: zoom.duration,
                       zoomLevel: zoom.zoomLevel, zoomCenter: zoom.zoomCenter)
      state.updateSpeed(id: speedID, rate: speed.rate, startTime: speed.startTime, duration: speed.duration)
    }
    state.endZoomEdit(id: zoomID)
    state.endSpeedEdit(id: speedID)

    XCTAssertEqual(zoomPublications, 0)
    XCTAssertEqual(speedPublications, 0)
    XCTAssertFalse(state.canUndo)
    XCTAssertFalse(state.hasUnsavedChanges)
  }

  func testSpeedRangeResolver_andCommittedRangeAgreeAtNeighbourBoundary() async throws {
    let videoURL = try await makeVideoFile(named: "speed-neighbour.mov", duration: 12)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()
    let editedID = try XCTUnwrap(state.addSpeed(range: 1 ... 3, rate: 2))
    _ = try XCTUnwrap(state.addSpeed(range: 5 ... 7, rate: 4))

    let resolved = try XCTUnwrap(state.resolvedSpeedSegment(id: editedID, startTime: 2, duration: 4))
    XCTAssertEqual(resolved.startTime, 2, accuracy: 0.0001)
    XCTAssertEqual(resolved.endTime, 5, accuracy: 0.0001)
    state.beginSpeedEdit(id: editedID)
    state.updateSpeed(id: editedID, startTime: 2, duration: 4)
    state.endSpeedEdit(id: editedID)
    XCTAssertEqual(state.speedSegments.first(where: { $0.id == editedID }), resolved)
  }

  func testExactAutoFocusPaths_useCapturedSettingsDespiteLaterEdits() async throws {
    let videoURL = try await makeVideoFile(named: "autofocus-snapshot.mov", duration: 12)
    let session = makeSessionData(sourceSnapshotURL: videoURL)
    let metadata = try XCTUnwrap(session.recordingMetadata)
    let state = VideoEditorState(url: videoURL, sessionData: session)
    await state.loadMetadata()
    let captured = state.zoomSegments
    let segment = try XCTUnwrap(captured.first)
    let expected = VideoEditorAutoFocusEngine.buildPath(from: metadata, segment: segment)
    XCTAssertFalse(expected.isEmpty)

    state.updateZoom(id: segment.id, zoomLevel: 4, followSpeed: 0.1, focusMargin: 0.1)
    let paths = await state.awaitExactAutoFocusPaths(for: captured, metadata: metadata)

    XCTAssertEqual(paths[segment.id], expected,
                   "Export must resolve the captured recipe, not the live editor's newest settings")
    XCTAssertNotEqual(state.zoomSegments, captured)
  }

  func testExportSnapshot_doesNotMixRecipeWhenEditorChangesDuringPreparation() async throws {
    let videoURL = try await makeVideoFile(named: "export-recipe.mov", duration: 12)
    let session = makeSessionData(sourceSnapshotURL: videoURL)
    let state = VideoEditorState(url: videoURL, sessionData: session)
    await state.loadMetadata()
    let originalZoom = try XCTUnwrap(state.zoomSegments.first)
    // Invalidate the settings key so preparation cannot reuse the restored path.
    state.updateZoom(id: originalZoom.id, followSpeed: 0.4)
    let capturedZooms = state.zoomSegments
    let capturedClips = state.clips
    let capturedSpeeds = state.speedSegments
    let capturedSettings = state.exportSettings
    let capturedMetadata = try XCTUnwrap(state.recordingMetadata)
    var preparationStarted = false
    let preparation = Task { @MainActor in
      preparationStarted = true
      // No actor suspension between the flag and prepareSnapshot's capture.
      return try await VideoEditorExporter.prepareSnapshot(for: state)
    }
    while !preparationStarted { await Task.yield() }

    state.updateZoom(id: originalZoom.id, zoomLevel: 4, followSpeed: 0.1)
    state.moveClip(id: capturedClips[0].id, toIndex: 1)
    state.updateSpeed(id: capturedSpeeds[0].id, rate: 8)
    state.exportSettings.quality = .low
    let snapshot = try await preparation.value

    XCTAssertEqual(snapshot.zoomSegments, capturedZooms)
    XCTAssertEqual(snapshot.clips, capturedClips)
    XCTAssertEqual(snapshot.speedSegments, capturedSpeeds)
    XCTAssertEqual(snapshot.exportSettings, capturedSettings)
    XCTAssertEqual(snapshot.autoFocusPath(for: capturedZooms[0]),
                   VideoEditorAutoFocusEngine.buildPath(from: capturedMetadata, segment: capturedZooms[0]))
    XCTAssertNotEqual(state.zoomSegments, capturedZooms)
    XCTAssertNotEqual(state.clips, capturedClips)
    XCTAssertNotEqual(state.speedSegments, capturedSpeeds)
  }

  func testCameraCache_matchesFreshMappingAfterReorderTrimAndUndo() async throws {
    let videoURL = try await makeVideoFile(named: "camera-layout.mov", duration: 12)
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 64, height: 64), samplesPerSecond: 10,
      mouseSamples: (0 ... 120).map { index in
        RecordedMouseSample(time: Double(index) / 10,
                            normalizedX: 0.2 + CGFloat(index) / 200,
                            normalizedY: 0.5, isInsideCapture: true)
      }
    )
    let zoom = ZoomSegment(startTime: 0, duration: 12, zoomLevel: 3, zoomType: .auto, followSpeed: 1)
    let clips = [
      TimelineClip(source: .primary, sourceDuration: 12, sourceStart: 0, sourceEnd: 6),
      TimelineClip(source: .primary, sourceDuration: 12, sourceStart: 6, sourceEnd: 12),
    ]
    let session = VideoEditorSessionData(sourceSnapshotURL: videoURL, recordingMetadata: metadata,
                                       clips: clips, zoomSegments: [zoom])
    let state = VideoEditorState(url: videoURL, sessionData: session)
    await state.loadMetadata()
    let expectedSource = VideoEditorAutoFocusEngine.buildPath(from: metadata, segment: zoom)
    let deadline = Date().addingTimeInterval(5)
    while state.autoFocusPath(for: zoom) != expectedSource, Date() < deadline {
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    XCTAssertEqual(state.autoFocusPath(for: zoom), expectedSource)
    func assertFreshCamera(file: StaticString = #filePath, line: UInt = #line) async throws {
      let freshPath = VideoEditorAutoFocusEngine.timelinePath(expectedSource,
                                                            placements: TimelineSequence.layout(state.clips))
      let times = [2.0, 4.0, 7.0, 10.0]
      let expected = times.map { time in
        VideoEditorAutoFocusEngine.resolvedCameraState(
          at: time, segments: state.zoomSegments, autoFocusPaths: [zoom.id: freshPath],
          transitionDuration: state.zoomTransitionDuration
        )
      }
      let deadline = Date().addingTimeInterval(5)
      while times.map({ state.cameraState(at: $0) }) != expected, Date() < deadline {
        try await Task.sleep(nanoseconds: 1_000_000)
      }
      for (time, fresh) in zip(times, expected) {
        XCTAssertEqual(state.cameraState(at: time), fresh, file: file, line: line)
      }
    }
    try await assertFreshCamera()
    let before = state.cameraState(at: 2)
    state.moveClip(id: clips[0].id, toIndex: 1)
    try await assertFreshCamera()
    XCTAssertNotEqual(state.cameraState(at: 2), before, "Reorder must not retain the previous mapped path")
    state.updateClip(id: clips[1].id, sourceStart: 8)
    try await assertFreshCamera()
    state.undo()
    try await assertFreshCamera()
    state.undo()
    try await assertFreshCamera()
    XCTAssertEqual(state.cameraState(at: 2), before)
  }

  func testClosingEditorDuringSpeedEdit_lateGestureEndDoesNotRestartWork() async throws {
    let videoURL = try await makeVideoFile(named: "closed-speed-gesture.mov", duration: 12)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()
    let id = try XCTUnwrap(state.addSpeed(range: 1 ... 3, rate: 2))
    try await waitForScaledPreview(state)
    state.pause()
    state.beginSpeedEdit(id: id)
    state.updateSpeed(id: id, rate: 8, startTime: 2, duration: 3)
    state.cancelPendingPerformanceWork()
    let parkedItem = state.player.currentItem
    let parkedEstimate = state.estimatedFileSize
    var estimatePublications = 0
    let subscription = state.$estimatedFileSize.dropFirst().sink { _ in estimatePublications += 1 }
    defer { subscription.cancel() }

    // SwiftUI may deliver onDisappear/onEnded after the window closes.
    state.endSpeedEdit(id: id)
    state.endSpeedTrackDrag()
    try await Task.sleep(nanoseconds: 400_000_000)

    XCTAssertTrue(state.player.currentItem === parkedItem,
                  "A delayed gesture end must not install a rebuilt preview after close")
    XCTAssertEqual(state.estimatedFileSize, parkedEstimate)
    XCTAssertEqual(estimatePublications, 0)
    XCTAssertFalse(state.isPlaying)
  }

  func testUndoDuringZoomGesture_ignoresHeldPointerTicksUntilGestureEnds() async throws {
    let videoURL = try await makeVideoFile(named: "zoom-undo-held-pointer.mov", duration: 12)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()
    let id = state.addZoom(at: 3)
    let original = try XCTUnwrap(state.zoomSegments.first)
    state.markAsSaved()
    state.beginZoomEdit(id: id)
    state.updateZoom(id: id, startTime: 2, zoomLevel: 3)
    let committed = try XCTUnwrap(state.zoomSegments.first)

    state.undo()
    state.updateZoom(id: id, startTime: 4, zoomLevel: 4)
    XCTAssertEqual(state.zoomSegments, [original])
    XCTAssertFalse(state.canUndo)
    XCTAssertTrue(state.canRedo, "A held-pointer tick must not erase the redo entry")
    state.redo()
    state.updateZoom(id: id, startTime: 5, zoomLevel: 5)
    XCTAssertEqual(state.zoomSegments, [committed])
    XCTAssertFalse(state.canRedo)
    state.endZoomEdit(id: id)

    state.beginZoomEdit(id: id)
    state.updateZoom(id: id, startTime: 3, zoomLevel: 4)
    state.endZoomEdit(id: id)
    XCTAssertEqual(state.zoomSegments.first?.startTime, 3)
    state.undo()
    XCTAssertEqual(state.zoomSegments, [committed], "The next gesture must create a normal undo entry")
    state.undo()
    XCTAssertEqual(state.zoomSegments, [original])
    XCTAssertFalse(state.canUndo, "Interrupted ticks and the late end must not create hidden undo entries")
  }

  func testUndoDuringSpeedGesture_ignoresHeldPointerTicksAndKeepsMappingConsistent() async throws {
    let videoURL = try await makeVideoFile(named: "speed-undo-held-pointer.mov", duration: 12)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()
    let id = try XCTUnwrap(state.addSpeed(range: 1 ... 3, rate: 2))
    let original = try XCTUnwrap(state.speedSegments.first)
    state.markAsSaved()
    let sequenceDuration = state.sequenceDuration
    state.beginSpeedEdit(id: id)
    state.updateSpeed(id: id, rate: 4, startTime: 2, duration: 3)
    let committed = try XCTUnwrap(state.speedSegments.first)

    state.undo()
    state.updateSpeed(id: id, rate: 8, startTime: 4, duration: 4)
    XCTAssertEqual(state.speedSegments, [original])
    XCTAssertEqual(state.sequenceMap.outputDuration, sequenceDuration - 1, accuracy: 0.0001)
    XCTAssertFalse(state.canUndo)
    XCTAssertTrue(state.canRedo)
    state.redo()
    state.updateSpeed(id: id, rate: 8, startTime: 5, duration: 4)
    XCTAssertEqual(state.speedSegments, [committed])
    XCTAssertEqual(state.sequenceMap.outputDuration, sequenceDuration - 2.25, accuracy: 0.0001)
    XCTAssertFalse(state.canRedo)
    state.endSpeedEdit(id: id)

    state.beginSpeedEdit(id: id)
    state.updateSpeed(id: id, rate: 8, startTime: 3)
    state.endSpeedEdit(id: id)
    XCTAssertEqual(state.speedSegments.first?.startTime, 3)
    state.undo()
    XCTAssertEqual(state.speedSegments, [committed])
    state.undo()
    XCTAssertEqual(state.speedSegments, [original])
    XCTAssertFalse(state.canUndo)
  }

  /// Runs real SwiftUI layout alongside model edits. Timings are diagnostic only:
  /// this replay does not generate pointer events or measure event-to-present latency.
  func testEditorHostingReplay_preservesFinalZoomAndSpeedValues() async throws {
    let videoURL = try await makeVideoFile(named: "editor-hosting-replay.mov", duration: 12)
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()
    let zoomID = state.addZoom(at: 3)
    let speedID = try XCTUnwrap(state.addSpeed(range: 6 ... 8, rate: 2))
    let host = NSHostingView(rootView: VideoEditorMainView(state: state))
    host.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    defer {
      window.contentView = nil
      state.pause()
    }
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    state.markAsSaved()
    state.beginZoomEdit(id: zoomID)
    state.beginSpeedEdit(id: speedID)
    var layoutTimes: [Double] = []
    for index in 1 ... 30 {
      let started = ProcessInfo.processInfo.systemUptime
      state.updateZoom(id: zoomID, startTime: 1 + Double(index) / 30, zoomLevel: 2 + CGFloat(index) / 30)
      state.updateSpeed(id: speedID, rate: 2 + Double(index) / 30, startTime: 6 + Double(index) / 30)
      await Task.yield()
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()
      layoutTimes.append((ProcessInfo.processInfo.systemUptime - started) * 1000)
    }
    state.endZoomEdit(id: zoomID)
    state.endSpeedEdit(id: speedID)
    host.layoutSubtreeIfNeeded()
    let sorted = layoutTimes.sorted()
    print("VideoEditor model + hosting replay, 30 ticks: p95=\(sorted[28]) ms, max=\(sorted[29]) ms")

    XCTAssertEqual(state.zoomSegments.first(where: { $0.id == zoomID })?.startTime, 2)
    XCTAssertEqual(state.speedSegments.first(where: { $0.id == speedID })?.startTime, 7)
    XCTAssertEqual(state.speedSegments.first(where: { $0.id == speedID })?.rate, 3)
    XCTAssertEqual(host.bounds.size, NSSize(width: 1280, height: 800))
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
