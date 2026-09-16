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

  func testVideoEditorPreview_appliesSpeedRateAtPlayhead() async throws {
    let videoURL = try await makeVideoFile(named: "preview-speed.mov")
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    XCTAssertNotNil(state.addSpeed(range: 0 ... 2, rate: 4))
    XCTAssertEqual(state.currentPreviewRate(at: .zero), 4, accuracy: 0.001)

    state.play()
    defer { state.pause() }

    for _ in 0 ..< 20 where state.player.timeControlStatus != .playing {
      try await Task.sleep(nanoseconds: 25_000_000)
    }

    XCTAssertEqual(state.player.timeControlStatus, .playing)
    XCTAssertEqual(state.player.rate, 4, accuracy: 0.001)
    XCTAssertEqual(state.player.defaultRate, 4, accuracy: 0.001)
    if let timebase = state.player.currentItem?.timebase {
      XCTAssertEqual(CMTimebaseGetRate(timebase), 4, accuracy: 0.1)
    } else {
      XCTFail("Expected the preview player item to have a timebase")
    }
  }

  func testVideoEditorPreview_updatesRateWhenPlayheadEntersSpeedSegment() async throws {
    let videoURL = try await makeVideoFile(named: "preview-speed-transition.mov")
    let state = VideoEditorState(url: videoURL)
    await state.loadMetadata()

    XCTAssertNotNil(state.addSpeed(range: 1 ... 2, rate: 4))
    state.play()
    defer { state.pause() }

    let deadline = Date().addingTimeInterval(3)
    while state.playbackState.currentTime.seconds < 1.05, Date() < deadline {
      try await Task.sleep(nanoseconds: 25_000_000)
    }

    XCTAssertGreaterThanOrEqual(state.playbackState.currentTime.seconds, 1.05)
    XCTAssertEqual(state.player.rate, 4, accuracy: 0.001)
    XCTAssertEqual(state.player.defaultRate, 4, accuracy: 0.001)
  }

  // MARK: - Helpers

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

  private func makeVideoFile(named name: String) async throws -> URL {
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
    for index in 0 ..< 40 {
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
