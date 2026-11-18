//
//  VideoEditorStudioAgentTests.swift
//  SnapzyTests
//
//  Phase 6: Studio layers and captions in the saved session, the agent tools that
//  edit them, and the offline mock planner.
//

import Foundation
@testable import Snapzy
import XCTest

@MainActor
final class VideoEditorStudioAgentTests: XCTestCase {
  private var tempDirectory: URL!
  private var states: [VideoEditorState] = []

  override func setUp() {
    super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_StudioAgent_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDirectory)
    states = []
    super.tearDown()
  }

  /// Fixed ids, so values compare equal across calls.
  private let ids = [UUID(), UUID()]

  private func captions() -> VideoEditorCaptions {
    var value = VideoEditorCaptions(segments: [
      CaptionSegment(id: ids[0], sourceRange: 1 ... 3, text: "Hello there"),
      CaptionSegment(id: ids[1], sourceRange: 5 ... 7, text: "Second line"),
    ])
    value.settings.position = .top
    return value
  }

  // MARK: - Session

  func testEditStateKeepsStudioLayersAndOldManifestsStillDecode() throws {
    var cursor = VideoEditorCursorSettings.default
    cursor.scale = 1.5
    var camera = VideoEditorCameraSettings.default
    camera.shape = RecordingCameraShape.circle.rawValue
    let session = VideoEditorSessionData(
      sourceSnapshotURL: URL(fileURLWithPath: "/tmp/x.mov"),
      cursorSettings: cursor, cameraSettings: camera, captions: captions()
    )
    let data = try JSONEncoder().encode(PersistedVideoEditorEditState(sessionData: session))
    let decoded = try JSONDecoder().decode(PersistedVideoEditorEditState.self, from: data)
      .sessionData(sourceSnapshotURL: session.sourceSnapshotURL, recordingMetadata: nil)
    XCTAssertEqual(decoded.cursorSettings, cursor)
    XCTAssertEqual(decoded.cameraSettings, camera)
    XCTAssertEqual(decoded.captions, captions())

    // A manifest written before these fields existed.
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["cursorSettings"] = nil
    object["cameraSettings"] = nil
    object["captions"] = nil
    let old = try JSONDecoder().decode(
      PersistedVideoEditorEditState.self, from: JSONSerialization.data(withJSONObject: object)
    )
    XCTAssertNil(old.cursorSettings)
    XCTAssertNil(old.captions)
  }

  func testRestoredSessionBringsCaptionsBackAsTheCleanBaseline() async throws {
    let url = try await VideoEditorActivityFixture.makeVideoFile(in: tempDirectory, duration: 12, audio: true)
    let state = VideoEditorState(
      url: url,
      sessionData: VideoEditorSessionData(
        sourceSnapshotURL: url, clips: [TimelineClip(source: .primary, sourceDuration: 12)], captions: captions()
      )
    )
    states.append(state)
    await state.loadMetadata()
    XCTAssertEqual(state.captions, captions())
    XCTAssertFalse(state.hasUnsavedChanges)

    let snapshot = VideoEditorSessionData.snapshot(from: state, sourceSnapshotURL: url)
    XCTAssertEqual(snapshot.captions, captions())
    XCTAssertNil(snapshot.cursorSettings, "no editable cursor: nothing to save")
  }

  // MARK: - Agent tools

  private func makeToolbox() async throws -> (VideoEditorState, VideoEditorAgentToolbox) {
    let state = try await VideoEditorActivityFixture.makeState(in: tempDirectory, cursor: false)
    states.append(state)
    return (state, VideoEditorAgentToolbox(state: state))
  }

  private func call(_ toolbox: VideoEditorAgentToolbox, _ name: String, _ json: String = "{}") -> AgentToolResult {
    toolbox.execute(name: name, arguments: Data(json.utf8))
  }

  func testCursorAndCameraToolsExplainWhenTheRecordingCannotBeEdited() async throws {
    let (_, toolbox) = try await makeToolbox()
    XCTAssertTrue(call(toolbox, "set_cursor", #"{"visible": false}"#).text.contains("Studio"))
    XCTAssertTrue(call(toolbox, "set_camera", #"{"visible": false}"#).isError)
    let timeline = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(call(toolbox, "get_timeline").text.utf8)) as? [String: Any])
    XCTAssertNil(timeline["cursor"])
    XCTAssertNil(timeline["captions"])
  }

  func testEditCaptionChangesTextTimingAndStyleInOneUndoStep() async throws {
    let (state, toolbox) = try await makeToolbox()
    state.setCaptions(captions(), recordUndo: false)

    let timeline = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(call(toolbox, "get_timeline").text.utf8)) as? [String: Any])
    let listed = try XCTUnwrap((timeline["captions"] as? [String: Any])?["items"] as? [[String: Any]])
    XCTAssertEqual(listed.map { $0["id"] as? String }, ["t1", "t2"])
    XCTAssertEqual(listed[1]["start"] as? Double ?? 0, 5, accuracy: 0.01)

    toolbox.beginRun()
    XCTAssertFalse(call(toolbox, "edit_caption", #"{"id": "t1", "text": "Hi", "end": 4}"#).isError)
    XCTAssertFalse(call(toolbox, "edit_caption", #"{"id": "t2", "text": ""}"#).isError)
    XCTAssertFalse(call(toolbox, "edit_caption", #"{"position": "bottom", "show_on_video": false}"#).isError)
    XCTAssertTrue(call(toolbox, "edit_caption", #"{"text": "no id"}"#).isError)
    toolbox.finishRun()

    XCTAssertEqual(state.captions.segments.map(\.text), ["Hi"])
    XCTAssertEqual(state.captions.segments[0].end, 4, accuracy: 0.01)
    XCTAssertEqual(state.captions.settings.position, .bottom)
    XCTAssertFalse(state.captions.settings.isEnabled)

    state.undo()
    XCTAssertEqual(state.captions, captions())
  }

  // MARK: - Mock planner

  func testMockPlansCursorAndVietnameseCaptions() {
    let calls = VideoEditorAgentMockProvider.plan(for: "ẩn cursor, phóng to cursor 1.5x, thêm phụ đề tiếng Việt")
    XCTAssertEqual(calls.map(\.name), ["set_cursor", "set_cursor", "generate_captions"])
    XCTAssertTrue(calls[0].arguments.contains(#""visible":false"#))
    XCTAssertTrue(calls[1].arguments.contains(#""scale":1.5"#))
    XCTAssertTrue(calls[2].arguments.contains("vi-VN"))
  }
}
