//
//  VideoEditorAgentToolboxTests.swift
//  SnapzyTests
//
//  Video Editor agent tools: each tool, clamping, short ids, one undo step per
//  run, and cut_range with effects following the cut. The pure cut math is
//  covered without a player.
//

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
@testable import Snapzy
import XCTest

@MainActor
final class VideoEditorAgentToolboxTests: XCTestCase {
  private var tempDirectory: URL!
  /// The toolbox holds its state weakly, as the editor window owns it.
  private var states: [VideoEditorState] = []
  private let eps = 0.011

  override func setUp() {
    super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_VideoAgent_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    states = []
    super.tearDown()
  }

  // MARK: - Cut math

  private func primary(_ duration: TimeInterval) -> TimelineClip {
    TimelineClip(source: .primary, sourceDuration: duration)
  }

  func testCut_insideOneClipSplitsAndKeepsFirstID() throws {
    let clip = primary(10)
    let result = try XCTUnwrap(VideoEditorTimelineCut.cut([clip], range: 2 ... 5))
    XCTAssertEqual(result.clips.count, 2)
    XCTAssertEqual(result.clips[0].id, clip.id)
    XCTAssertEqual(result.clips[0].slotEnd, 2, accuracy: 0.0001)
    XCTAssertEqual(result.clips[1].slotStart, 5, accuracy: 0.0001)
    XCTAssertEqual(result.removed, [2 ... 5])
    XCTAssertEqual(TimelineSequence.duration(result.clips), 7, accuracy: 0.0001)
  }

  func testCut_acrossTwoClipsTrimsBothEdges() throws {
    let a = TimelineClip(source: .primary, sourceDuration: 10, sourceStart: 0, sourceEnd: 4)
    let b = TimelineClip(source: .primary, sourceDuration: 10, sourceStart: 4, sourceEnd: 10)
    let result = try XCTUnwrap(VideoEditorTimelineCut.cut([a, b], range: 3 ... 6))
    XCTAssertEqual(result.clips.map(\.id), [a.id, b.id])
    XCTAssertEqual(result.clips[0].sourceEnd, 3, accuracy: 0.0001)
    XCTAssertEqual(result.clips[1].sourceStart, 6, accuracy: 0.0001)
    XCTAssertEqual(result.removed, [3 ... 6])
  }

  func testCut_dropsSliverAndReportsIt() throws {
    let result = try XCTUnwrap(VideoEditorTimelineCut.cut([primary(10)], range: 0.05 ... 4))
    XCTAssertEqual(result.clips.count, 1)
    XCTAssertEqual(result.removed, [0 ... 4])
  }

  func testCut_wholeSequenceIsRejected() {
    XCTAssertNil(VideoEditorTimelineCut.cut([primary(10)], range: 0 ... 10))
  }

  func testShifted_movesShortensAndDrops() {
    let removed: [ClosedRange<TimeInterval>] = [2 ... 5]
    XCTAssertEqual(VideoEditorTimelineCut.shifted(start: 6, end: 8, removing: removed, minDuration: 0.5), 3 ... 5)
    XCTAssertEqual(VideoEditorTimelineCut.shifted(start: 1, end: 4, removing: removed, minDuration: 0.5), 1 ... 2)
    XCTAssertNil(VideoEditorTimelineCut.shifted(start: 2.5, end: 4.5, removing: removed, minDuration: 0.5))
    XCTAssertEqual(VideoEditorTimelineCut.shifted(start: 0, end: 1, removing: removed, minDuration: 0.5), 0 ... 1)
  }

  // MARK: - Time parsing

  func testTimeParsing() {
    XCTAssertEqual(VideoEditorAgentTime.parse("75"), 75)
    XCTAssertEqual(VideoEditorAgentTime.parse("1:15.5"), 75.5)
    XCTAssertEqual(VideoEditorAgentTime.parse("1:02:03"), 3723)
    XCTAssertEqual(VideoEditorAgentTime.parse("12s"), 12)
    XCTAssertNil(VideoEditorAgentTime.parse("1:75"))
    XCTAssertNil(VideoEditorAgentTime.parse("soon"))
  }

  // MARK: - Toolbox

  private func makeToolbox(duration: TimeInterval = 12) async throws -> (VideoEditorState, VideoEditorAgentToolbox) {
    let url = try await makeVideoFile(duration: duration)
    let state = VideoEditorState(url: url)
    await state.loadMetadata()
    XCTAssertFalse(state.clips.isEmpty)
    states.append(state)
    return (state, VideoEditorAgentToolbox(state: state))
  }

  @discardableResult
  private func call(
    _ toolbox: VideoEditorAgentToolbox,
    _ name: String,
    _ json: String = "{}",
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> [String: Any] {
    let result = toolbox.execute(name: name, arguments: Data(json.utf8))
    XCTAssertFalse(result.isError, "\(name) failed: \(result.text)", file: file, line: line)
    return (try? JSONSerialization.jsonObject(with: Data(result.text.utf8))) as? [String: Any] ?? [:]
  }

  private func error(_ toolbox: VideoEditorAgentToolbox, _ name: String, _ json: String) -> String {
    let result = toolbox.execute(name: name, arguments: Data(json.utf8))
    XCTAssertTrue(result.isError, "\(name) should fail: \(result.text)")
    return result.text
  }

  func testCatalogMatchesToolNames() {
    XCTAssertEqual(VideoEditorAgentToolCatalog.all.map(\.name), VideoEditorAgentToolName.allCases.map(\.rawValue))
    for spec in VideoEditorAgentToolCatalog.all {
      XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(spec.parametersJSON.utf8)), spec.name)
    }
  }

  func testGetTimeline_listsClipWithShortID() async throws {
    let (_, toolbox) = try await makeToolbox()
    let timeline = call(toolbox, "get_timeline")
    let clips = try XCTUnwrap(timeline["clips"] as? [[String: Any]])
    XCTAssertEqual(clips.first?["id"] as? String, "c1")
    XCTAssertEqual(timeline["duration"] as? Double ?? 0, 12, accuracy: 0.11)
    XCTAssertEqual(timeline["has_mouse_data"] as? Bool, false)
  }

  func testRun_isOneUndoStep() async throws {
    let (state, toolbox) = try await makeToolbox()
    toolbox.beginRun()
    call(toolbox, "add_speed", #"{"start": "0:01", "end": 3, "rate": 4}"#)
    call(toolbox, "add_zoom", #"{"start": 5, "duration": 2, "level": 2.5, "center": [0.2, 0.3]}"#)
    call(toolbox, "set_background", #"{"style": "bluePurple", "corner_radius": 12}"#)
    call(toolbox, "split", #"{"time": 8}"#)
    let summary = toolbox.finishRun()

    XCTAssertEqual(summary.changeCount, 4)
    XCTAssertNotNil(summary.undoEntry)
    XCTAssertEqual(state.lastUndoEntry, summary.undoEntry)
    XCTAssertEqual(state.speedSegments.count, 1)
    XCTAssertEqual(state.zoomSegments.first?.zoomType, .manual)
    XCTAssertEqual(state.zoomSegments.first?.zoomCenter.x ?? 0, 0.2, accuracy: 0.001)
    XCTAssertEqual(state.backgroundStyle, .gradient(.bluePurple))
    XCTAssertEqual(state.backgroundPadding, 24, "picking a background gives the frame room, like the panel")
    XCTAssertEqual(state.clips.count, 2)

    state.undo()
    XCTAssertTrue(state.speedSegments.isEmpty)
    XCTAssertTrue(state.zoomSegments.isEmpty)
    XCTAssertEqual(state.backgroundStyle, .none)
    XCTAssertEqual(state.backgroundPadding, 0)
    XCTAssertEqual(state.clips.count, 1)
    XCTAssertFalse(state.canUndo)

    state.redo()
    XCTAssertEqual(state.speedSegments.count, 1)
    XCTAssertEqual(state.zoomSegments.count, 1)
    XCTAssertEqual(state.backgroundCornerRadius, 12)
    XCTAssertEqual(state.clips.count, 2)
  }

  func testRun_readOnlyLeavesNoUndoEntry() async throws {
    let (state, toolbox) = try await makeToolbox()
    toolbox.beginRun()
    call(toolbox, "get_timeline")
    call(toolbox, "seek", #"{"time": 3}"#)
    let summary = toolbox.finishRun()
    XCTAssertNil(summary.undoEntry)
    XCTAssertFalse(state.canUndo)
    XCTAssertEqual(state.currentTime.seconds, 3, accuracy: 0.05)
  }

  func testUndoIsIgnoredWhileRunIsOpen() async throws {
    let (state, toolbox) = try await makeToolbox()
    toolbox.beginRun()
    call(toolbox, "add_speed", #"{"start": 1, "end": 3, "rate": 2}"#)
    state.undo()
    XCTAssertEqual(state.speedSegments.count, 1)
    toolbox.finishRun()
    state.undo()
    XCTAssertTrue(state.speedSegments.isEmpty)
  }

  func testCutRange_shiftsEffectsAndUndoesInOneStep() async throws {
    let (state, toolbox) = try await makeToolbox()
    toolbox.beginRun()
    call(toolbox, "add_zoom", #"{"start": 8, "duration": 2}"#)       // after the cut
    call(toolbox, "add_zoom", #"{"start": 3, "duration": 1.5}"#)     // inside the cut
    call(toolbox, "add_speed", #"{"start": 1, "end": 4, "rate": 2}"#) // crosses the start
    toolbox.finishRun()
    let zoomsBefore = state.zoomSegments
    let speedsBefore = state.speedSegments
    let clipsBefore = state.clips

    toolbox.beginRun()
    let payload = call(toolbox, "cut_range", #"{"start": 2, "end": 5}"#)
    toolbox.finishRun()

    XCTAssertEqual(payload["removed_seconds"] as? Double ?? 0, 3, accuracy: eps)
    XCTAssertEqual(state.timelineDuration.seconds, 9, accuracy: 0.11)
    XCTAssertEqual(payload["zooms_removed"] as? [String], ["z2"])
    XCTAssertEqual(state.zoomSegments.count, 1)
    XCTAssertEqual(state.zoomSegments[0].startTime, 5, accuracy: eps)
    XCTAssertEqual(state.speedSegments.count, 1)
    XCTAssertEqual(state.speedSegments[0].startTime, 1, accuracy: eps)
    XCTAssertEqual(state.speedSegments[0].endTime, 2, accuracy: eps)

    state.undo()
    XCTAssertEqual(state.clips, clipsBefore)
    XCTAssertEqual(Set(state.zoomSegments), Set(zoomsBefore))
    XCTAssertEqual(state.speedSegments, speedsBefore)
  }

  func testCutRange_withoutShiftLeavesEffects() async throws {
    let (state, toolbox) = try await makeToolbox()
    call(toolbox, "add_zoom", #"{"start": 8, "duration": 2}"#)
    call(toolbox, "cut_range", #"{"start": 2, "end": 5, "shift_effects": false}"#)
    XCTAssertEqual(state.zoomSegments.first?.startTime ?? 0, 8, accuracy: eps)
  }

  func testCutRange_rejectsWholeVideoAndTimesPastTheEnd() async throws {
    let (_, toolbox) = try await makeToolbox()
    XCTAssertTrue(error(toolbox, "cut_range", #"{"start": 0, "end": 12}"#).contains("whole video"))
    XCTAssertTrue(error(toolbox, "cut_range", #"{"start": 2, "end": "1:00"}"#).contains("after the end"))
  }

  func testClipTools_splitMoveTrimDelete() async throws {
    let (state, toolbox) = try await makeToolbox()
    call(toolbox, "get_timeline")
    let split = call(toolbox, "split", #"{"time": 4}"#)
    XCTAssertEqual(split["clips"] as? [String], ["c1", "c2"])
    let second = state.clips[1].id

    call(toolbox, "move_clip", #"{"clip": "c2", "position": 1}"#)
    XCTAssertEqual(state.clips[0].id, second)

    let trimmed = call(toolbox, "trim_clip", #"{"clip": "c2", "start": 1}"#)
    XCTAssertEqual(trimmed["plays_from"] as? Double ?? 0, 1, accuracy: eps)
    XCTAssertTrue(error(toolbox, "trim_clip", #"{"clip": "c2", "end": 11}"#).contains("inside the clip"))

    call(toolbox, "delete_clip", #"{"clip": "c1"}"#)
    XCTAssertEqual(state.clips.map(\.id), [second])
    XCTAssertTrue(error(toolbox, "delete_clip", #"{"clip": "c2"}"#).contains("only clip"))
    XCTAssertTrue(error(toolbox, "delete_clip", #"{"clip": "c9"}"#).contains("get_timeline"))
  }

  func testClamping() async throws {
    let (state, toolbox) = try await makeToolbox()
    let zoom = call(toolbox, "add_zoom", #"{"start": 1, "duration": 0.1, "level": 10}"#)
    XCTAssertEqual(zoom["level"] as? Double, Double(ZoomSegment.maxZoomLevel))
    XCTAssertEqual(state.zoomSegments[0].duration, ZoomSegment.minDuration, accuracy: eps)

    let speed = call(toolbox, "add_speed", #"{"start": 5, "end": 7, "rate": 100}"#)
    XCTAssertEqual(speed["rate"] as? Double, SpeedSegment.maxRate)

    call(toolbox, "update_zoom", #"{"id": "z1", "center": [50, 25]}"#)
    XCTAssertEqual(state.zoomSegments[0].zoomCenter.x, 0.5, accuracy: 0.001, "percent centers are read as 0…1")

    call(toolbox, "set_background", #"{"padding": 999, "shadow": 5}"#)
    XCTAssertEqual(state.backgroundPadding, 300)
    XCTAssertEqual(state.backgroundShadowIntensity, 1)
  }

  func testSpeedOverlapSaysWhereThereIsRoom() async throws {
    let (_, toolbox) = try await makeToolbox()
    call(toolbox, "add_speed", #"{"start": 2, "end": 6, "rate": 2}"#)
    let message = error(toolbox, "add_speed", #"{"start": 5, "end": 8, "rate": 4}"#)
    XCTAssertTrue(message.contains("s1"), message)
    XCTAssertTrue(message.contains("0:06.0"), message)
    call(toolbox, "update_speed", #"{"id": "s1", "end": "0:04", "rate": 3}"#)
    call(toolbox, "remove_speed", #"{"ids": ["all"]}"#)
  }

  func testZoomFollowMouseNeedsMouseData() async throws {
    let (_, toolbox) = try await makeToolbox()
    XCTAssertTrue(error(toolbox, "add_zoom", #"{"start": 1, "follow_mouse": true}"#).contains("mouse"))
  }

  func testAudioAndUnknownToolAndBadArguments() async throws {
    let (_, toolbox) = try await makeToolbox()
    XCTAssertTrue(error(toolbox, "set_audio", #"{"muted": true}"#).contains("no audio"))
    XCTAssertTrue(error(toolbox, "export", "{}").contains("Unknown tool"))
    XCTAssertTrue(error(toolbox, "seek", #"{"time": "later"}"#).contains("m:ss.s"))
    XCTAssertTrue(error(toolbox, "set_background", #"{"aspect_ratio": "7:5"}"#).contains("aspect_ratio"))
  }

  func testAspectRatioAndAlignment() async throws {
    let (state, toolbox) = try await makeToolbox()
    call(toolbox, "set_background", #"{"aspect_ratio": "16x9", "alignment": "topLeft"}"#)
    XCTAssertEqual(state.backgroundAspectRatio, .ratio16x9)
    XCTAssertEqual(state.backgroundAlignment, .topLeft)
    state.undo()
    XCTAssertEqual(state.backgroundAspectRatio, .auto)
    XCTAssertEqual(state.backgroundAlignment, .center)
  }

  func testChangeLimitPerRun() async throws {
    let (_, toolbox) = try await makeToolbox()
    toolbox.beginRun()
    for index in 0 ..< VideoEditorAgentToolbox.maximumChangesPerRun {
      call(toolbox, "set_background", "{\"padding\": \(index % 2 == 0 ? 10 : 20)}")
    }
    XCTAssertTrue(error(toolbox, "set_background", #"{"padding": 30}"#).contains("limit"))
    toolbox.finishRun()
  }

  func testRefusesWhileExporting() async throws {
    let (state, toolbox) = try await makeToolbox()
    state.isExporting = true
    XCTAssertTrue(error(toolbox, "get_timeline", "{}").contains("exporting"))
    state.isExporting = false
  }

  // MARK: - Fixture

  private func makeVideoFile(duration: TimeInterval) async throws -> URL {
    let url = tempDirectory.appendingPathComponent("agent-\(UUID().uuidString).mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: 64,
      AVVideoHeightKey: 64,
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
      kCVPixelBufferWidthKey as String: 64,
      kCVPixelBufferHeightKey as String: 64,
    ])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? NSError(domain: "VideoAgentTests", code: 1) }
    writer.startSession(atSourceTime: .zero)

    let frameRate: Int32 = 10
    for index in 0 ..< Int(duration * Double(frameRate)) {
      while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 1_000_000)
      }
      var buffer: CVPixelBuffer?
      CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
      guard let buffer else { throw NSError(domain: "VideoAgentTests", code: 2) }
      guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: frameRate)) else {
        throw writer.error ?? NSError(domain: "VideoAgentTests", code: 3)
      }
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? NSError(domain: "VideoAgentTests", code: 4) }
    return url
  }
}
