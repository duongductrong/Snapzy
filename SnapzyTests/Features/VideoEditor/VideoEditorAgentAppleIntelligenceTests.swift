//
//  VideoEditorAgentAppleIntelligenceTests.swift
//  SnapzyTests
//
//  Video Editor AI, phase 5: Apple Intelligence provider. Unit tests cover the
//  compact scene, argument helpers, prompt budget and the coarse cut / zoom /
//  speed / style / auto tools on the 12 s activity fixture. The live evaluation
//  runs only with SNAPZY_LIVE_AI=1 (xcodebuild: TEST_RUNNER_SNAPZY_LIVE_AI=1) on a
//  Mac with Apple Intelligence.
//

import CoreMedia
import Foundation
@testable import Snapzy
import XCTest

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class VideoEditorAgentAppleIntelligenceTests: XCTestCase {
  private var tempDirectory: URL!
  /// The toolbox holds its state weakly, as the editor window owns it.
  private var retained: [AnyObject] = []
  private let eps = 0.06

  override func setUp() {
    super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_VideoApple_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    retained = []
    super.tearDown()
  }

  private func makeToolbox() async throws -> (VideoEditorState, VideoEditorAgentToolbox) {
    let state = try await VideoEditorActivityFixture.makeState(in: tempDirectory)
    XCTAssertFalse(state.clips.isEmpty)
    let toolbox = VideoEditorAgentToolbox(state: state)
    retained += [state, toolbox]
    return (state, toolbox)
  }

  private func duration(_ state: VideoEditorState) -> Double {
    TimelineSequence.duration(state.clips)
  }

  // MARK: - Compact scene

  private func scene(clips: Int = 2, zooms: Int = 0) -> VideoEditorAgentScene {
    VideoEditorAgentScene(
      duration: 12,
      playableDuration: 12,
      outputDuration: 10.5,
      size: [1920, 1080],
      playhead: 3.25,
      clips: (1 ... clips).map { index in
        let start = Double(index - 1) * 2
        return .init(id: "c\(index)", start: start, end: start + 2, playsFrom: index == 1 ? 0.5 : start, playsTo: start + 2, source: "recording")
      },
      zooms: (0 ..< zooms).map { .init(id: "z\($0 + 1)", start: Double($0), end: Double($0) + 1, level: 2, center: nil, followMouse: true, enabled: true) },
      speeds: [.init(id: "s1", start: 6, end: 8, rate: 4, enabled: false)],
      background: .init(style: "bluePurple", padding: 40, shadow: 0.5, cornerRadius: 12, alignment: "center", aspectRatio: "original"),
      audio: .init(muted: false, tracks: [.init(name: "microphone", volume: 100)]),
      selection: .init(clip: nil, zoom: nil, speed: nil),
      hasMouseData: true
    )
  }

  func testCompactDescription_listsTimelineInShortLines() {
    let text = scene(zooms: 1).compactDescription(maximumItems: 10)
    XCTAssertTrue(text.contains("Video: 12s long, exports 10.5s, playhead at 3.25s. Audio: on. Recorded cursor: yes."), text)
    XCTAssertTrue(text.contains("Clips: c1 0–2 (plays 0.5–2); c2 2–4"), text)
    XCTAssertTrue(text.contains("Zooms: z1 0–1 2x follows mouse"), text)
    XCTAssertTrue(text.contains("Speeds: s1 6–8 4x off"), text)
    XCTAssertTrue(text.contains("Frame: background bluePurple, padding 40, corners 12, shadow 0.5."), text)
  }

  func testCompactDescription_keepsBudgetAndCountsTheRest() {
    let text = scene(clips: 12).compactDescription(maximumItems: 3)
    XCTAssertTrue(text.contains("c3 4–6"))
    XCTAssertFalse(text.contains("c4 "))
    XCTAssertTrue(text.contains("+9 more"))
    XCTAssertFalse(text.contains("Zooms:"), "empty lists are left out")
  }

  // MARK: - Argument helpers

  func testArguments_timesCentersAndIDs() {
    XCTAssertEqual(VideoEditorAgentAppleArguments.time("1:05") as? Double, 65)
    XCTAssertEqual(VideoEditorAgentAppleArguments.time(" 12 seconds") as? Double, 12)
    XCTAssertEqual(VideoEditorAgentAppleArguments.time("2.5") as? Double, 2.5)
    XCTAssertEqual(VideoEditorAgentAppleArguments.time("soon") as? String, "soon", "unreadable text goes to the toolbox, which explains")
    XCTAssertNil(VideoEditorAgentAppleArguments.time("none"))
    XCTAssertNil(VideoEditorAgentAppleArguments.time(nil))

    XCTAssertEqual(VideoEditorAgentAppleArguments.center("top left"), [0.25, 0.25])
    XCTAssertEqual(VideoEditorAgentAppleArguments.center("bottom-right"), [0.75, 0.75])
    XCTAssertEqual(VideoEditorAgentAppleArguments.center("center"), [0.5, 0.5])
    XCTAssertNil(VideoEditorAgentAppleArguments.center("mouse"))

    XCTAssertEqual(VideoEditorAgentAppleArguments.ids(["z1", " ", "none", "all"]), ["z1", "all"])
  }

  func testCompactActivity_keepsLongestSpansInOrderWithoutAreas() throws {
    let spans: [[String: Any]] = [
      ["kind": "speech", "start": 0.0, "end": 0.5],
      ["kind": "silence", "start": 0.5, "end": 4.0],
      ["kind": "motion", "start": 4.0, "end": 7.0, "area": [0.1, 0.1, 0.2, 0.2]],
      ["kind": "speech", "start": 7.0, "end": 7.4],
    ]
    let text = VideoEditorAgentAppleArguments.json(["audio": "all", "mouse": true, "spans": spans])
    let compact = VideoEditorAgentAppleArguments.compactActivity(text, maximumSpans: 2)
    let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(compact.utf8)) as? [String: Any])
    let kept = try XCTUnwrap(object["spans"] as? [[String: Any]])
    XCTAssertEqual(kept.map { $0["kind"] as? String }, ["silence", "motion"])
    XCTAssertNil(kept[1]["area"])
    XCTAssertEqual(object["omitted_short_spans"] as? Int, 2)
  }

  #if canImport(FoundationModels)

  private func makeSession() async throws -> (VideoEditorState, VideoEditorAgentToolbox, AgentSession) {
    guard #available(macOS 26.0, *) else { throw XCTSkip("FoundationModels needs macOS 26") }
    let (state, toolbox) = try await makeToolbox()
    toolbox.beginRun()
    let session = AgentSession(toolbox: toolbox, pacingEnabled: false, onToolCall: { _ in })
    retained.append(session)
    return (state, toolbox, session)
  }

  // MARK: - Prompt

  func testPrompt_compactSceneAndRecentHistory() async throws {
    guard #available(macOS 26.0, *) else { throw XCTSkip("FoundationModels needs macOS 26") }
    let history = (1 ... 5).map { AgentTurn(prompt: "prompt \($0)", reply: "reply \($0)") }
    let request = AgentRequest(prompt: "Cut 0:02 to 0:04", history: history, sceneJSON: "{}", scene: scene(clips: 6))

    let prompt = VideoEditorAgentAppleIntelligenceProvider.prompt(for: request, maximumItems: 2)
    XCTAssertTrue(prompt.hasPrefix("Scene:\nVideo: 12s long"))
    XCTAssertTrue(prompt.contains("+4 more"))
    XCTAssertFalse(prompt.contains("prompt 2"), "only the last 3 turns are sent")
    XCTAssertTrue(prompt.contains("prompt 3") && prompt.contains("reply 5"))
    XCTAssertTrue(prompt.hasSuffix("Request: Cut 0:02 to 0:04"))
  }

  // MARK: - Tools

  func testCutTool_removesEveryPartLatestFirst() async throws {
    guard #available(macOS 26.0, *) else { throw XCTSkip("FoundationModels needs macOS 26") }
    let (state, toolbox, session) = try await makeSession()
    let cut = VideoAppleCutTool(bridge: VideoAppleToolBridge(session: session))

    // Earliest first on purpose: the tool must still cut 6–8 before 1–2.
    let result = try await cut.call(arguments: VideoAppleCutTool.Arguments(GeneratedContent(properties: [
      "parts": [
        GeneratedContent(properties: ["start": "1", "end": "0:02"]),
        GeneratedContent(properties: ["start": "6", "end": "8 seconds"]),
      ],
    ])))
    XCTAssertFalse(result.contains("\"ok\":false"), result)
    XCTAssertEqual(duration(state), 9, accuracy: eps)
    XCTAssertEqual(state.currentTime.seconds, 1, accuracy: eps, "playhead shows the first cut")

    let summary = toolbox.finishRun()
    XCTAssertEqual(summary.changeCount, 2)
    state.undo()
    XCTAssertEqual(duration(state), 12, accuracy: eps, "one undo for the whole run")

    let empty = try await cut.call(arguments: VideoAppleCutTool.Arguments(GeneratedContent(properties: [
      "parts": [GeneratedContent(properties: ["start": "", "end": "2"])],
    ])))
    XCTAssertTrue(empty.contains("\"ok\":false"))
  }

  func testZoomTool_addChangeRemove() async throws {
    guard #available(macOS 26.0, *) else { throw XCTSkip("FoundationModels needs macOS 26") }
    let (state, _, session) = try await makeSession()
    let zoom = VideoAppleZoomTool(bridge: VideoAppleToolBridge(session: session))
    func run(_ properties: KeyValuePairs<String, any ConvertibleToGeneratedContent>) async throws -> String {
      try await zoom.call(arguments: VideoAppleZoomTool.Arguments(GeneratedContent(properties: properties)))
    }

    _ = try await run(["action": "add", "start": "0:02", "seconds": 3.0, "level": 2.5, "place": "top left"])
    _ = try await run(["action": "add", "start": "8", "place": "mouse"])
    XCTAssertEqual(state.zoomSegments.count, 2)
    let fixed = try XCTUnwrap(state.zoomSegments.first { abs($0.startTime - 2) < eps })
    XCTAssertEqual(fixed.endTime, 5, accuracy: eps)
    XCTAssertEqual(Double(fixed.zoomLevel), 2.5, accuracy: 0.01)
    XCTAssertEqual(fixed.zoomCenter.x, 0.25, accuracy: 0.01)
    XCTAssertEqual(fixed.zoomCenter.y, 0.25, accuracy: 0.01)
    XCTAssertEqual(state.zoomSegments.first { abs($0.startTime - 8) < eps }?.zoomType, .auto)

    let missing = try await run(["action": "add"])
    XCTAssertTrue(missing.contains("\"ok\":false"))

    _ = try await run(["action": "change", "ids": ["all"], "level": 3.0])
    XCTAssertTrue(state.zoomSegments.allSatisfy { abs(Double($0.zoomLevel) - 3) < 0.01 })

    _ = try await run(["action": "remove", "ids": ["all"]])
    XCTAssertTrue(state.zoomSegments.isEmpty)
  }

  func testSpeedTool_addRejectsOverlapAndRemoves() async throws {
    guard #available(macOS 26.0, *) else { throw XCTSkip("FoundationModels needs macOS 26") }
    let (state, _, session) = try await makeSession()
    let speed = VideoAppleSpeedTool(bridge: VideoAppleToolBridge(session: session))
    func run(_ properties: KeyValuePairs<String, any ConvertibleToGeneratedContent>) async throws -> String {
      try await speed.call(arguments: VideoAppleSpeedTool.Arguments(GeneratedContent(properties: properties)))
    }

    _ = try await run(["action": "add", "start": "2", "end": "5", "rate": 4.0])
    XCTAssertEqual(state.speedSegments.count, 1)
    XCTAssertEqual(state.speedSegments[0].rate, 4, accuracy: 0.01)

    let overlap = try await run(["action": "add", "start": "4", "end": "6", "rate": 2.0])
    XCTAssertTrue(overlap.contains("\"ok\":false"), overlap)

    _ = try await run(["action": "change", "ids": ["s1"], "rate": 6.0])
    XCTAssertEqual(state.speedSegments[0].rate, 6, accuracy: 0.01)

    _ = try await run(["action": "remove", "ids": ["all"]])
    XCTAssertTrue(state.speedSegments.isEmpty)
  }

  func testStyleTool_framesAndMutes() async throws {
    guard #available(macOS 26.0, *) else { throw XCTSkip("FoundationModels needs macOS 26") }
    let (state, _, session) = try await makeSession()
    let style = VideoAppleStyleTool(bridge: VideoAppleToolBridge(session: session))

    let result = try await style.call(arguments: VideoAppleStyleTool.Arguments(GeneratedContent(properties: [
      "background": "bluePurple", "padding": 40, "cornerRadius": 12, "muted": true,
    ])))
    XCTAssertFalse(result.contains("\"ok\":false"), result)
    XCTAssertEqual(state.backgroundPadding, 40)
    XCTAssertEqual(state.backgroundCornerRadius, 12)
    XCTAssertNotEqual(state.backgroundStyle, .none)
    XCTAssertEqual(state.exportSettings.audioMode, .mute)

    _ = try await style.call(arguments: VideoAppleStyleTool.Arguments(GeneratedContent(properties: ["background": "Gradient"])))
    XCTAssertEqual(state.backgroundStyle, .gradient(GradientPreset.allCases[0]), "a bare 'gradient' picks the first preset")

    let empty = try await style.call(arguments: VideoAppleStyleTool.Arguments(GeneratedContent(properties: [:])))
    XCTAssertTrue(empty.contains("\"ok\":false"))
  }

  func testAutoTool_runsOneStepToolsAndListsActivity() async throws {
    guard #available(macOS 26.0, *) else { throw XCTSkip("FoundationModels needs macOS 26") }
    let (state, _, session) = try await makeSession()
    let auto = VideoAppleAutoTool(bridge: VideoAppleToolBridge(session: session))
    func run(_ properties: KeyValuePairs<String, any ConvertibleToGeneratedContent>) async throws -> String {
      try await auto.call(arguments: VideoAppleAutoTool.Arguments(GeneratedContent(properties: properties)))
    }

    let activity = try await run(["action": "list_activity"])
    XCTAssertTrue(activity.contains("\"silence\""), activity)
    XCTAssertFalse(activity.contains("\"area\""))
    XCTAssertEqual(state.clips.count, 1, "listing changes nothing")

    _ = try await run(["action": "zoom_on_activity", "amount": 2.0])
    XCTAssertFalse(state.zoomSegments.isEmpty)

    _ = try await run(["action": "remove_silences"])
    XCTAssertLessThan(duration(state), 11)

    let bad = try await run(["action": "dance"])
    XCTAssertTrue(bad.contains("\"ok\":false"))
  }

  // MARK: - Live evaluation (opt-in)

  /// Standard video prompts against the real on-device model, on the activity fixture.
  /// Prints one line per prompt; fails only if the model errors out on half of them.
  func testLiveVideoPrompts() async throws {
    guard ProcessInfo.processInfo.environment["SNAPZY_LIVE_AI"] == "1" else {
      throw XCTSkip("Set SNAPZY_LIVE_AI=1 to call Apple Intelligence")
    }
    guard #available(macOS 26.0, *) else { throw XCTSkip("FoundationModels needs macOS 26") }
    guard SystemLanguageModel.default.availability == .available else {
      throw XCTSkip("Apple Intelligence is not available on this Mac")
    }

    typealias Check = (VideoEditorState) -> Bool
    let prompts: [(prompt: String, setup: String?, check: Check)] = [
      ("Tua 4x từ 0:06 đến 0:09, zoom 2x ở 0:02", nil, { state in
        state.speedSegments.contains { abs($0.rate - 4) < 0.01 } && !state.zoomSegments.isEmpty
      }),
      ("Cut 0:02 to 0:04", nil, { abs(TimelineSequence.duration($0.clips) - 10) < 0.2 }),
      ("Cắt các đoạn im lặng", nil, { TimelineSequence.duration($0.clips) < 11 }),
      ("Speed up the parts where I'm just waiting", nil, { !$0.speedSegments.isEmpty }),
      ("Zoom vào chỗ tôi thao tác chuột", nil, { $0.zoomSegments.contains { $0.zoomType == .auto } }),
      ("Nền gradient, padding 40, bo góc 12", nil, { $0.backgroundPadding >= 20 && $0.backgroundCornerRadius > 0 && $0.backgroundStyle != .none }),
      ("Mute the video", nil, { $0.exportSettings.audioMode == .mute }),
      ("Xoá hết zoom", #"{"start":3,"duration":2}"#, { state in
        state.zoomSegments.isEmpty && abs(TimelineSequence.duration(state.clips) - 12) < 0.01
      }),
      ("Remove all speed changes", #"{"start":2,"end":5,"rate":4}"#, { state in
        state.speedSegments.isEmpty && abs(TimelineSequence.duration(state.clips) - 12) < 0.01
      }),
    ]

    var passed = 0
    var errors = 0
    var lines: [String] = []
    func log(_ line: String) {
      print(line)
      lines.append(line)
    }
    for item in prompts {
      let (state, toolbox) = try await makeToolbox()
      if let setup = item.setup {
        let tool: VideoEditorAgentToolName = setup.contains("rate") ? .addSpeed : .addZoom
        _ = await toolbox.execute(name: tool.rawValue, argumentsJSON: setup)
      }
      toolbox.beginRun()
      var calls: [String] = []
      let session = AgentSession(toolbox: toolbox, pacingEnabled: false, onToolCall: { calls.append($0) })
      let request = AgentRequest(prompt: item.prompt, history: [], sceneJSON: "{}", scene: toolbox.scene())
      let started = Date()
      do {
        let reply = try await VideoEditorAgentAppleIntelligenceProvider().run(request, session: session)
        let summary = toolbox.finishRun()
        let ok = item.check(state)
        passed += ok ? 1 : 0
        let speeds = state.speedSegments.map { String(format: "%.1f-%.1f@%.0f", $0.startTime, $0.endTime, $0.rate) }.joined(separator: ",")
        let zooms = state.zoomSegments.map { String(format: "%.1f-%.1f", $0.startTime, $0.endTime) }.joined(separator: ",")
        log("[live-ai-video] \(ok ? "PASS" : "MISS") \(String(format: "%.1fs", Date().timeIntervalSince(started))) “\(item.prompt)” → \(summary.changeCount) changes, duration \(String(format: "%.2f", TimelineSequence.duration(state.clips))) speeds[\(speeds)] zooms[\(zooms)] calls: \(calls.joined(separator: ",")) “\(reply)”")
      } catch {
        _ = toolbox.finishRun()
        errors += 1
        log("[live-ai-video] ERROR “\(item.prompt)” → \(error)")
      }
    }
    log("[live-ai-video] \(passed)/\(prompts.count) passed, \(errors) errors")
    let report = lines.joined(separator: "\n")
    try? report.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snapzy-live-ai-video.log"), atomically: true, encoding: .utf8)
    add(XCTAttachment(string: report))
    XCTAssertLessThan(errors, prompts.count / 2)
  }

  #endif
}
