//
//  VideoEditorStudioAgentAdaptiveTests.swift
//  SnapzyTests
//
//  The agent on Studio recordings: the scene says what is editable, the new cursor,
//  camera and caption settings, hidden-camera ids, click zooms, clicks kept out of
//  idle stretches, camera overlap notes, caption add / remove / replace / translate,
//  quick actions and the mock planner.
//

import AVFoundation
import Foundation
@testable import Snapzy
import XCTest

@MainActor
final class VideoEditorStudioAgentAdaptiveTests: XCTestCase {
  private var tempDirectory: URL!
  private var states: [VideoEditorState] = []
  private var controllers: [VideoEditorAgentController] = []
  private var sidecars: [URL] = []

  override func setUp() {
    super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_StudioAdaptive_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDown() {
    for url in sidecars { try? FileManager.default.removeItem(at: url) }
    try? FileManager.default.removeItem(at: tempDirectory)
    states = []
    controllers = []
    super.tearDown()
  }

  // MARK: - Fixture

  /// Clicks: a burst at 2.0–2.4 s top right, one at 8.0 s lower left (each with its mouse-up).
  private static let clicks: [RecordedClick] = [
    RecordedClick(time: 2.0, button: .left, phase: .down, normalizedX: 0.8, normalizedY: 0.2),
    RecordedClick(time: 2.1, button: .left, phase: .up, normalizedX: 0.8, normalizedY: 0.2),
    RecordedClick(time: 2.4, button: .left, phase: .down, normalizedX: 0.82, normalizedY: 0.22),
    RecordedClick(time: 2.5, button: .left, phase: .up, normalizedX: 0.82, normalizedY: 0.22),
    RecordedClick(time: 8.0, button: .left, phase: .down, normalizedX: 0.3, normalizedY: 0.6),
    RecordedClick(time: 8.1, button: .left, phase: .up, normalizedX: 0.3, normalizedY: 0.6),
  ]

  /// The 12 s analyzer fixture as a Studio recording: cursor apart (with clicks) and a
  /// camera sidecar recorded bottom right (x and y 0.7–0.95).
  private func makeStudioState(camera: Bool = true) async throws -> VideoEditorState {
    let url = try await VideoEditorActivityFixture.makeVideoFile(in: tempDirectory, duration: 12, audio: true)
    var cameraSource: RecordingCameraSource?
    if camera {
      let copy = tempDirectory.appendingPathComponent("camera-\(UUID().uuidString).mov")
      try FileManager.default.copyItem(at: url, to: copy)
      let stored = try RecordingMetadataStore.storeSidecar(from: copy, kind: .camera)
      sidecars.append(stored)
      cameraSource = RecordingCameraSource(
        fileName: stored.lastPathComponent, naturalSize: CGSize(width: 64, height: 64), shape: "rectangle",
        normalizedFrame: CGRect(x: 0.7, y: 0.7, width: 0.25, height: 0.25), pointSize: CGSize(width: 100, height: 100)
      )
    }
    let metadata = RecordingMetadata(
      captureSize: CGSize(width: 64, height: 64), samplesPerSecond: 30,
      mouseSamples: VideoEditorActivityFixture.cursorSamples(),
      cursorCapture: RecordingCursorCapture(clicks: Self.clicks),
      isCursorBaked: false,
      cameraSource: cameraSource
    )
    let state = VideoEditorState(url: url, sessionData: VideoEditorSessionData(sourceSnapshotURL: url, recordingMetadata: metadata))
    states.append(state)
    await state.loadMetadata()
    return state
  }

  private func makePlainState() async throws -> VideoEditorState {
    let state = try await VideoEditorActivityFixture.makeState(in: tempDirectory)
    states.append(state)
    return state
  }

  private func call(_ toolbox: VideoEditorAgentToolbox, _ name: String, _ json: String = "{}") -> AgentToolResult {
    toolbox.execute(name: name, arguments: Data(json.utf8))
  }

  private func object(_ result: AgentToolResult, file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
    XCTAssertFalse(result.isError, result.text, file: file, line: line)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.text.utf8)) as? [String: Any], file: file, line: line)
  }

  private func captions(_ items: [(ClosedRange<TimeInterval>, String)]) -> VideoEditorCaptions {
    VideoEditorCaptions(segments: items.map { CaptionSegment(sourceRange: $0.0, text: $0.1) })
  }

  // MARK: - Scene

  func testSceneMarksStudioRecordingsAndCountsClicks() async throws {
    let state = try await makeStudioState()
    XCTAssertTrue(state.hasEditableCursor)
    XCTAssertTrue(state.hasEditableCamera)
    let scene = try XCTUnwrap(VideoEditorAgentToolbox(state: state).scene())
    XCTAssertTrue(scene.studio)
    XCTAssertEqual(scene.cursor?.clicks, 3, "mouse-downs only")
    XCTAssertEqual(scene.camera?.hidden, [])

    let plain = try await makePlainState()
    let plainScene = try XCTUnwrap(VideoEditorAgentToolbox(state: plain).scene())
    XCTAssertFalse(plainScene.studio)
    XCTAssertNil(plainScene.cursor)
  }

  // MARK: - Cursor

  func testSetCursorTakesThePanelsOtherSettings() async throws {
    let state = try await makeStudioState(camera: false)
    let toolbox = VideoEditorAgentToolbox(state: state)
    let alpha = state.cursorSettings.clickColor.alpha

    XCTAssertFalse(call(toolbox, "set_cursor", #"{"idle_delay": 9, "always_arrow": true, "click_color": "red", "click_volume": 1.5}"#).isError)
    XCTAssertEqual(state.cursorSettings.idleDelay, VideoEditorCursorSettings.idleDelayRange.upperBound)
    XCTAssertTrue(state.cursorSettings.alwaysUseArrow)
    XCTAssertEqual(state.cursorSettings.clickSoundVolume, 1)
    XCTAssertEqual(state.cursorSettings.clickColor.alpha, alpha, accuracy: 0.001, "a plain color keeps the effect's opacity")
    XCTAssertGreaterThan(state.cursorSettings.clickColor.red, state.cursorSettings.clickColor.blue)

    XCTAssertFalse(call(toolbox, "set_cursor", ##"{"click_color": "#00FF0080"}"##).isError)
    XCTAssertEqual(state.cursorSettings.clickColor.alpha, 0.5, accuracy: 0.01, "#RRGGBBAA spells its own opacity")
    XCTAssertTrue(call(toolbox, "set_cursor", #"{"click_color": "not a color"}"#).isError)
  }

  // MARK: - Camera

  func testHiddenStretchesHaveIdsAndCanBeShownOneByOne() async throws {
    let state = try await makeStudioState()
    let toolbox = VideoEditorAgentToolbox(state: state)
    XCTAssertFalse(call(toolbox, "set_camera", #"{"hide_start": 1, "hide_end": 2}"#).isError)
    XCTAssertFalse(call(toolbox, "set_camera", #"{"hide_start": 5, "hide_end": 6}"#).isError)
    let hidden = try XCTUnwrap(toolbox.scene()?.camera?.hidden)
    XCTAssertEqual(hidden.map(\.id), ["h1", "h2"])
    XCTAssertEqual(hidden[1].start, 5, accuracy: 0.01)

    XCTAssertFalse(call(toolbox, "set_camera", #"{"show_hidden": ["h1"]}"#).isError)
    XCTAssertEqual(state.cameraSettings.hiddenRanges.count, 1)
    XCTAssertEqual(state.cameraSettings.hiddenRanges[0].start, 5, accuracy: 0.01)
    XCTAssertTrue(call(toolbox, "set_camera", #"{"show_hidden": ["h9"]}"#).isError)
    XCTAssertFalse(call(toolbox, "set_camera", #"{"show_hidden": ["all"]}"#).isError)
    XCTAssertTrue(state.cameraSettings.hiddenRanges.isEmpty)
  }

  func testResetMatchesThePanelButtonAndLaterSettingsApplyOnTop() async throws {
    let state = try await makeStudioState()
    let toolbox = VideoEditorAgentToolbox(state: state)
    let recorded = state.cameraSettings
    XCTAssertFalse(call(toolbox, "set_camera", #"{"position": "top_left", "size": 0.4, "hide_start": 1, "hide_end": 2}"#).isError)
    XCTAssertNotEqual(state.cameraSettings, recorded)

    XCTAssertFalse(call(toolbox, "set_camera", #"{"reset": true}"#).isError)
    XCTAssertEqual(state.cameraSettings, VideoEditorCameraSettings.recorded(try XCTUnwrap(state.recordingMetadata?.cameraSource)))

    XCTAssertFalse(call(toolbox, "set_camera", #"{"reset": true, "mirrored": true, "position": "top-right"}"#).isError)
    XCTAssertTrue(state.cameraSettings.isMirrored)
    XCTAssertEqual(state.cameraSettings.center, CGPoint(x: 0.85, y: 0.15))
  }

  func testZoomUnderTheCameraGetsANoteAndHideDuringZoomsClearsIt() async throws {
    let state = try await makeStudioState()
    let toolbox = VideoEditorAgentToolbox(state: state)
    let zoom = try object(call(toolbox, "add_zoom", #"{"start": 4, "duration": 2, "center": [0.8, 0.8]}"#))
    XCTAssertNotNil(zoom["note"], "the camera sits bottom right")
    let clear = try object(call(toolbox, "add_zoom", #"{"start": 9, "duration": 1, "center": [0.3, 0.3]}"#))
    XCTAssertNil(clear["note"])

    let hidden = try object(call(toolbox, "set_camera", #"{"hide_during_zooms": true}"#))
    XCTAssertEqual(hidden["hidden_for_zooms"] as? Int, 2)
    let ranges = state.cameraSettings.hiddenRanges
    XCTAssertEqual(ranges.count, 2)
    XCTAssertEqual(ranges[0].start, 4, accuracy: 0.01)
    XCTAssertEqual(ranges[0].end, 6, accuracy: 0.01)

    let again = try object(call(toolbox, "update_zoom", #"{"id": "z1", "level": 2.5}"#))
    XCTAssertNil(again["note"], "the camera is hidden while this zoom plays")
  }

  func testCaptionsUnderTheCameraGetANote() async throws {
    let state = try await makeStudioState()
    let toolbox = VideoEditorAgentToolbox(state: state)
    state.setCaptions(captions([(1 ... 3, "Hello")]), recordUndo: false)
    let bottom = try object(call(toolbox, "edit_caption", #"{"text_size": 0.05}"#))
    XCTAssertNotNil(bottom["note"])
    let top = try object(call(toolbox, "edit_caption", #"{"position": "top"}"#))
    XCTAssertNil(top["note"])
  }

  // MARK: - Clicks

  func testClickZoomsLandOnEachBurstOfClicks() async throws {
    let state = try await makeStudioState(camera: false)
    let toolbox = VideoEditorAgentToolbox(state: state)
    let result = try object(await toolbox.execute(name: "auto_zoom_activity", argumentsJSON: #"{"source": "clicks"}"#))
    let added = try XCTUnwrap(result["added"] as? [[String: Any]])
    XCTAssertEqual(added.count, 2)
    XCTAssertEqual(added[0]["start"] as? Double ?? 0, 1.4, accuracy: 0.01)
    XCTAssertEqual(added[1]["start"] as? Double ?? 0, 7.4, accuracy: 0.01)
    let second = try XCTUnwrap(state.zoomSegments.sorted { $0.startTime < $1.startTime }.last)
    XCTAssertEqual(second.zoomType, .manual)
    XCTAssertEqual(second.zoomCenter.x, 0.3, accuracy: 0.01)
    XCTAssertEqual(second.zoomCenter.y, 0.6, accuracy: 0.01)

    // Default source is unchanged: motion zooms follow the mouse.
    let plain = try await makePlainState()
    let plainResult = await VideoEditorAgentToolbox(state: plain).execute(name: "auto_zoom_activity", argumentsJSON: "{}")
    XCTAssertFalse(plainResult.isError, plainResult.text)
    XCTAssertTrue(plain.zoomSegments.allSatisfy { $0.zoomType == .auto })
    let noClicks = await VideoEditorAgentToolbox(state: plain).execute(name: "auto_zoom_activity", argumentsJSON: #"{"source": "clicks"}"#)
    XCTAssertTrue(noClicks.isError)
    XCTAssertTrue(noClicks.text.contains("Studio"))
  }

  func testActivityListsClicksAndAClickIsNeverIdle() async throws {
    let state = try await makeStudioState(camera: false)
    let toolbox = VideoEditorAgentToolbox(state: state)
    let activity = try object(await toolbox.execute(name: "get_activity", argumentsJSON: "{}"))
    let clicks = try XCTUnwrap(activity["clicks"] as? [[String: Any]])
    XCTAssertEqual(clicks.map { $0["time"] as? Double }, [2.0, 2.4, 8.0])
    let spans = try XCTUnwrap(activity["spans"] as? [[String: Any]])
    let idleOverClick = spans.contains { span in
      span["kind"] as? String == "idle" && (span["start"] as? Double ?? 0) < 8.0 && (span["end"] as? Double ?? 0) > 8.0
    }
    XCTAssertFalse(idleOverClick)

    // Clicks follow the clip: cut 1–3 s and the 8 s click moves to 6 s.
    XCTAssertFalse(call(toolbox, "cut_range", #"{"start": 1, "end": 3}"#).isError)
    let moved = toolbox.timelineClicks(state)
    XCTAssertEqual(moved.map(\.time).last ?? 0, 6.0, accuracy: 0.01)
    XCTAssertEqual(moved.count, 1, "the 2.0 and 2.4 s clicks were cut")
  }

  func testClickBurstsSplitOnGapAndArea() {
    let clicks = [
      VideoEditorTimelineClick(time: 1, point: CGPoint(x: 0.1, y: 0.1)),
      VideoEditorTimelineClick(time: 1.5, point: CGPoint(x: 0.15, y: 0.1)),
      VideoEditorTimelineClick(time: 2, point: CGPoint(x: 0.9, y: 0.9)),
      VideoEditorTimelineClick(time: 6, point: CGPoint(x: 0.9, y: 0.9)),
    ]
    let bursts = VideoEditorAgentToolbox.clickBursts(clicks)
    XCTAssertEqual(bursts.map(\.count), [2, 1, 1])
    XCTAssertEqual(bursts[0].end, 1.5)
  }

  // MARK: - Captions

  func testAddRemoveAndReplaceCaptionsInOneUndoStep() async throws {
    let state = try await makePlainState()
    let toolbox = VideoEditorAgentToolbox(state: state)
    let original = captions([(1 ... 3, "We use snapsy daily"), (5 ... 7, "Snapsy, snapshot and SNAPSY")])
    state.setCaptions(original, recordUndo: false)
    _ = call(toolbox, "get_timeline")

    toolbox.beginRun()
    let added = try object(call(toolbox, "add_caption", #"{"start": 8, "end": 9.5, "text": "  Thanks for watching  "}"#))
    XCTAssertEqual(added["id"] as? String, "t3")
    XCTAssertTrue(call(toolbox, "add_caption", #"{"start": 2, "end": 4, "text": "overlaps t1"}"#).text.contains("t1"))

    let replaced = try object(call(toolbox, "replace_in_captions", #"{"find": "snapsy", "replace": "Snapzy"}"#))
    XCTAssertEqual(replaced["changed"] as? Int, 2)
    XCTAssertTrue(call(toolbox, "replace_in_captions", #"{"find": "nothing here", "replace": "x"}"#).isError)

    XCTAssertFalse(call(toolbox, "remove_captions", #"{"ids": ["t1"]}"#).isError)
    toolbox.finishRun()

    XCTAssertEqual(state.captions.segments.map(\.text), ["Snapzy, snapshot and Snapzy", "Thanks for watching"])
    state.undo()
    XCTAssertEqual(state.captions, original)
  }

  func testCaptionSearchKeepsWholeWordsAndAccents() throws {
    let regex = try VideoEditorAgentToolbox.captionSearch("phụ đề", matchCase: false, wholeWord: true)
    let text = "Thêm phụ đề, không phải phụ đềx"
    XCTAssertEqual(regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)), 1)
    let symbol = try VideoEditorAgentToolbox.captionSearch("C++", matchCase: true, wholeWord: true)
    XCTAssertEqual(symbol.numberOfMatches(in: "I like C++.", range: NSRange(location: 0, length: 11)), 1)
  }

  func testGetCaptionsPagesPastTheTimelineList() async throws {
    let state = try await makePlainState()
    let toolbox = VideoEditorAgentToolbox(state: state)
    let many = (0 ..< 100).map { index -> (ClosedRange<TimeInterval>, String) in
      let start = Double(index) * 0.11
      return (start ... start + 0.1, "c\(index)")
    }
    state.setCaptions(captions(many), recordUndo: false)
    let scene = try XCTUnwrap(toolbox.scene()?.captions)
    XCTAssertEqual(scene.items.count, VideoEditorAgentStudioTools.maximumListedCaptions)

    let page = try object(call(toolbox, "get_captions"))
    XCTAssertEqual((page["captions"] as? [Any])?.count, VideoEditorAgentStudioTools.maximumCaptionPage)
    let next = try XCTUnwrap(page["next_start"] as? Double)
    let rest = try object(call(toolbox, "get_captions", #"{"start": \#(next)}"#))
    XCTAssertEqual((rest["captions"] as? [[String: Any]])?.last?["text"] as? String, "c99")
  }

  func testTranslateCaptionsChecksItsInputBeforeTranslating() async throws {
    let state = try await makePlainState()
    let toolbox = VideoEditorAgentToolbox(state: state)
    let empty = await toolbox.execute(name: "translate_captions", argumentsJSON: #"{"language": "vi"}"#)
    XCTAssertTrue(empty.text.contains("generate_captions"))

    var english = captions([(1 ... 3, "Hello there, this is a test of captions")])
    english.settings.languageIdentifier = "en-US"
    state.setCaptions(english, recordUndo: false)
    let klingon = await toolbox.execute(name: "translate_captions", argumentsJSON: #"{"language": "klingon"}"#)
    XCTAssertTrue(klingon.isError)
    let same = await toolbox.execute(name: "translate_captions", argumentsJSON: #"{"language": "English"}"#)
    XCTAssertTrue(same.text.contains("already"))
    XCTAssertEqual(state.captions, english)

    // Text already translated to French while the speech language says English: the text decides.
    var french = captions([(1 ... 3, "Bonjour à tous, ceci est un essai des sous-titres en français")])
    french.settings.languageIdentifier = "en-US"
    state.setCaptions(french, recordUndo: false)
    let frenchAgain = await toolbox.execute(name: "translate_captions", argumentsJSON: #"{"language": "fr"}"#)
    XCTAssertTrue(frenchAgain.text.contains("already"), frenchAgain.text)
  }

  func testTranslationTargetsMatchTheAppsLanguages() {
    XCTAssertEqual(VideoEditorAgentStudioTools.translationTargets, TranslationLanguage.all.map(\.identifier))
    XCTAssertEqual(VideoEditorAgentStudioTools.translationTarget("vi-VN"), "vi")
    XCTAssertEqual(VideoEditorAgentStudioTools.translationTarget("Vietnamese"), "vi")
    XCTAssertEqual(VideoEditorAgentStudioTools.translationTarget("zh-TW"), "zh-Hant")
    XCTAssertEqual(VideoEditorAgentStudioTools.translationTarget("Chinese"), "zh-Hans")
    XCTAssertEqual(VideoEditorAgentStudioTools.translationTarget("JA"), "ja")
    XCTAssertNil(VideoEditorAgentStudioTools.translationTarget("klingon"))
  }

  func testTranslatorHandsRequestsToTheHostAndStopsOnCancel() async throws {
    let translator = VideoEditorCaptionTranslator()
    let vietnamese = try XCTUnwrap(TranslationLanguage.language(for: "vi"))
    let task = Task { try await translator.translate(["Hello"], sourceLanguage: "en-US", target: vietnamese, route: .apple) }
    await waitUntil { translator.request != nil }
    let request = try XCTUnwrap(translator.request)
    XCTAssertEqual(request.texts, ["Hello"])
    XCTAssertEqual(request.sourceLanguageIdentifier, "en-US")
    XCTAssertEqual(request.targetLanguageIdentifier, "vi")
    translator.complete(token: request.token, result: .success(BlockTranslationOutput(texts: ["Xin chào"], sourceLanguageIdentifier: "en")))
    let output = try await task.value
    XCTAssertEqual(output.texts, ["Xin chào"])
    XCTAssertNil(translator.request)

    let stopped = Task { try await translator.translate(["Bye"], sourceLanguage: nil, target: vietnamese, route: .apple) }
    await waitUntil { translator.request != nil }
    stopped.cancel()
    do {
      _ = try await stopped.value
      XCTFail("expected cancellation")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
    await waitUntil { translator.request == nil }
    XCTAssertNil(translator.request)

    do {
      _ = try await translator.translate(["x"], sourceLanguage: nil, target: vietnamese, route: .unavailable(.requiresMacOS15))
      XCTFail("expected an error")
    } catch {
      XCTAssertNotNil(VideoEditorCaptionTranslator.message(for: error))
    }
  }

  // MARK: - Quick actions & mock

  func testStudioQuickActionsOfferClickZoomsAndCaptions() async throws {
    let studio = makeController(try await makeStudioState(camera: false))
    XCTAssertEqual(studio.quickActions, [.removeSilences, .speedUpIdle, .clickZoom, .captions])

    let plain = try await makePlainState()
    let controller = makeController(plain)
    XCTAssertEqual(controller.quickActions, [.removeSilences, .speedUpIdle, .autoZoom, .captions])
    plain.setCaptions(captions([(1 ... 2, "Hi")]), recordUndo: false)
    XCTAssertEqual(controller.quickActions, [.removeSilences, .speedUpIdle, .autoZoom], "no chip once captions exist")
  }

  func testClickZoomQuickActionRunsWithoutAProvider() async throws {
    let state = try await makeStudioState(camera: false)
    let controller = makeController(state)
    controller.runQuickAction(.clickZoom)
    await waitUntil { !controller.isRunning }
    XCTAssertEqual(state.zoomSegments.count, 2)
    state.undo()
    XCTAssertTrue(state.zoomSegments.isEmpty)
  }

  func testMockPlansTheNewStudioTools() {
    let calls = VideoEditorAgentMockProvider.plan(
      for: #"dịch phụ đề sang tiếng Anh, thay "snapsy" bằng "snapzy" trong phụ đề, ẩn camera khi zoom, phóng to chỗ click"#
    )
    XCTAssertEqual(calls.map(\.name), ["translate_captions", "replace_in_captions", "set_camera", "auto_zoom_activity"])
    XCTAssertTrue(calls[0].arguments.contains(#""language":"en""#))
    XCTAssertTrue(calls[1].arguments.contains(#""find":"snapsy""#))
    XCTAssertTrue(calls[2].arguments.contains("hide_during_zooms"))
    XCTAssertTrue(calls[3].arguments.contains("clicks"))
    XCTAssertEqual(VideoEditorAgentMockProvider.plan(for: "xoá phụ đề").map(\.name), ["remove_captions"])
  }

  // MARK: - Helpers

  private func makeController(_ state: VideoEditorState) -> VideoEditorAgentController {
    let defaults = UserDefaults(suiteName: "SnapzyTests.StudioAdaptive.\(UUID().uuidString)")!
    let controller = VideoEditorAgentController(
      state: state,
      pacingEnabled: false,
      defaults: defaults,
      resolveProvider: { nil },
      confirmRemoteUse: { _ in XCTFail("quick actions never leave the Mac"); return false }
    )
    controllers.append(controller)
    return controller
  }

  private func waitUntil(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    for _ in 0 ..< 500 where !condition() {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertTrue(condition(), "condition not met in time", file: file, line: line)
  }
}
