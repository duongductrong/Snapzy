//
//  VideoEditorAgentAnalyzerTests.swift
//  SnapzyTests
//
//  Video agent perception (phase 4): silence from the audio, idle and motion from
//  the recorded cursor, their mapping onto an edited timeline, and the one-step
//  tools (`remove_silences`, `speed_up_idle`, `auto_zoom_activity`) plus the quick
//  action chips that run them without a model.
//
//  Fixture: 12 s video with a 16 kHz tone track — sound 0–2, 5–7, 10–12; silence
//  2–5 and 7–10 — and cursor samples: still 0–4, small circles 4–7, still 7–12
//  (circles start and end where the cursor rests).
//

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
@testable import Snapzy
import XCTest

@MainActor
final class VideoEditorAgentAnalyzerTests: XCTestCase {
  private var tempDirectory: URL!
  private var retained: [AnyObject] = []
  private let eps = 0.06

  override func setUp() {
    super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_VideoAnalyzer_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    retained = []
    super.tearDown()
  }

  // MARK: - Pure: silence

  func testSilences_findsQuietRunsAndIgnoresShortBlips() {
    // 0.05 s windows: 1 s loud, 2 s quiet with a 0.1 s blip in the middle, 1 s loud, 0.2 s quiet.
    var levels = [Float](repeating: -12, count: 20)
    levels += [Float](repeating: -90, count: 19) + [-15, -15] + [Float](repeating: -90, count: 19)
    levels += [Float](repeating: -12, count: 20) + [Float](repeating: -90, count: 4)
    let silences = VideoEditorAgentAnalyzer.silences(levels: levels, window: 0.05)
    XCTAssertEqual(silences.count, 1, "the 0.2 s tail is under the minimum span")
    XCTAssertEqual(silences[0].lowerBound, 1.0, accuracy: 0.001)
    XCTAssertEqual(silences[0].upperBound, 3.0, accuracy: 0.001)
  }

  func testSilenceThreshold_adaptsToNoiseFloor() {
    // Quiet room at -70, speech at -20: threshold sits between.
    let speech = [Float](repeating: -70, count: 50) + [Float](repeating: -20, count: 50)
    let threshold = VideoEditorAgentAnalyzer.silenceThreshold(levels: speech)
    XCTAssertGreaterThan(threshold, -70)
    XCTAssertLessThan(threshold, -20)
    // Constant music: no dynamics, only true silence would count.
    XCTAssertEqual(VideoEditorAgentAnalyzer.silenceThreshold(levels: [Float](repeating: -25, count: 100)), -50)
    // Nothing but hiss: all of it is silence.
    let hiss = [Float](repeating: -80, count: 100)
    XCTAssertEqual(VideoEditorAgentAnalyzer.silences(levels: hiss, window: 0.05).first?.upperBound ?? 0, 5, accuracy: 0.001)
  }

  // MARK: - Pure: cursor

  func testCursorSpans_stillAndMotion() {
    let points = VideoEditorActivityFixture.cursorSamples().map {
      VideoEditorAgentAnalyzer.Point(time: $0.time, point: $0.normalizedPoint)
    }
    let still = VideoEditorAgentAnalyzer.stillSpans(points, end: 12)
    XCTAssertEqual(still.count, 2)
    XCTAssertEqual(still[0].lowerBound, 0, accuracy: eps)
    XCTAssertEqual(still[0].upperBound, 4, accuracy: eps)
    XCTAssertEqual(still[1].lowerBound, 7, accuracy: eps)
    XCTAssertEqual(still[1].upperBound, 12, accuracy: eps)

    let motion = VideoEditorAgentAnalyzer.motionSpans(points)
    XCTAssertEqual(motion.count, 1)
    XCTAssertEqual(motion[0].range.lowerBound, 4, accuracy: eps)
    XCTAssertEqual(motion[0].range.upperBound, 7, accuracy: eps)
    XCTAssertLessThan(motion[0].bounds.width, 0.15)
    XCTAssertEqual(motion[0].bounds.midX, 0.2, accuracy: 0.02)
  }

  func testRangeMath() {
    XCTAssertEqual(VideoEditorAgentAnalyzer.subtract([0 ... 10], [2 ... 3, 8 ... 12]), [0 ... 2, 3 ... 8])
    XCTAssertEqual(VideoEditorAgentAnalyzer.intersect([0 ... 4, 6 ... 10], [3 ... 7]), [3 ... 4, 6 ... 7])
    XCTAssertEqual(VideoEditorAgentAnalyzer.intersect([0 ... 4], [3.9 ... 7]), [], "under the minimum span")
  }

  func testTimelineSpans_followCutsAndTrims() throws {
    // Source 0–12, cut 2–5 out: clip A plays 0–2, clip B source 5–12 at timeline 2–9.
    let clip = TimelineClip(source: .primary, sourceDuration: 12)
    let cut = try XCTUnwrap(VideoEditorTimelineCut.cut([clip], range: 2 ... 5))
    let placements = TimelineSequence.layout(cut.clips)
    let mapped = VideoEditorAgentAnalyzer.timelineSpans([1 ... 3, 7 ... 10], placements: placements)
    XCTAssertEqual(mapped.count, 2)
    XCTAssertEqual(mapped[0].lowerBound, 1, accuracy: 0.001)
    XCTAssertEqual(mapped[0].upperBound, 2, accuracy: 0.001, "source 2–3 was cut")
    XCTAssertEqual(mapped[1].lowerBound, 4, accuracy: 0.001)
    XCTAssertEqual(mapped[1].upperBound, 7, accuracy: 0.001)

    // A split joins back up; trimmed footage is dropped.
    var trimmed = TimelineClip(source: .primary, sourceDuration: 12, sourceStart: 0, sourceEnd: 6, slotStart: 0, slotEnd: 6)
    let tail = TimelineClip(source: .primary, sourceDuration: 12, sourceStart: 6, sourceEnd: 12)
    trimmed.sourceStart = 1
    let joined = VideoEditorAgentAnalyzer.timelineSpans([0 ... 8], placements: TimelineSequence.layout([trimmed, tail]))
    XCTAssertEqual(joined, [1 ... 8])
  }

  // MARK: - Analysis of a real file

  func testAnalyze_fixtureFindsSilenceIdleAndMotion() async throws {
    let state = try await makeState()
    let activity = try await VideoEditorAgentAnalyzer().activity(for: state)
    XCTAssertEqual(activity.audio, .all)
    XCTAssertEqual(activity.silences.count, 2)
    XCTAssertEqual(activity.silences[0].lowerBound, 2, accuracy: eps)
    XCTAssertEqual(activity.silences[0].upperBound, 5, accuracy: eps)
    XCTAssertEqual(activity.silences[1].lowerBound, 7, accuracy: eps)
    XCTAssertEqual(activity.silences[1].upperBound, 10, accuracy: eps)
    XCTAssertTrue(activity.hasMouseData)
    // No microphone track: a still cursor is idle whatever the system sound does.
    XCTAssertEqual(activity.idle.count, 2)
    XCTAssertEqual(activity.motion.count, 1)
  }

  func testAnalyzer_cachesPerSource() async throws {
    let state = try await makeState()
    let analyzer = VideoEditorAgentAnalyzer()
    XCTAssertNil(analyzer.cachedActivity(for: state))
    let first = try await analyzer.activity(for: state)
    XCTAssertEqual(analyzer.cachedActivity(for: state), first)
  }

  // MARK: - Tools

  private func call(_ toolbox: VideoEditorAgentToolbox, _ name: String, _ json: String = "{}") async -> [String: Any] {
    let result = await toolbox.execute(name: name, argumentsJSON: json)
    XCTAssertFalse(result.isError, "\(name) failed: \(result.text)")
    return (try? JSONSerialization.jsonObject(with: Data(result.text.utf8))) as? [String: Any] ?? [:]
  }

  func testGetActivity_listsSpansOnTheTimeline() async throws {
    let state = try await makeState()
    let toolbox = VideoEditorAgentToolbox(state: state)
    let payload = await call(toolbox, "get_activity", #"{"start": 1, "end": 9}"#)
    XCTAssertEqual(payload["audio"] as? String, "all")
    XCTAssertEqual(payload["mouse"] as? Bool, true)
    let spans = try XCTUnwrap(payload["spans"] as? [[String: Any]])
    let kinds = Set(spans.compactMap { $0["kind"] as? String })
    XCTAssertEqual(kinds, ["silence", "speech", "idle", "motion"])
    XCTAssertTrue(spans.allSatisfy { ($0["start"] as? Double ?? -1) >= 1 && ($0["end"] as? Double ?? 99) <= 9 })
    let motion = try XCTUnwrap(spans.first { $0["kind"] as? String == "motion" })
    XCTAssertEqual((motion["area"] as? [Double])?.count, 4)
    // Read-only: no undo entry.
    XCTAssertNil(state.lastUndoEntry)
  }

  func testRemoveSilences_cutsLatestFirstAsOneUndoStep() async throws {
    let state = try await makeState()
    let zoom = state.addZoom(at: 11)
    state.updateZoom(id: zoom, startTime: 10.5, duration: 1)
    let toolbox = VideoEditorAgentToolbox(state: state)
    toolbox.beginRun()
    let payload = await call(toolbox, "remove_silences")
    let summary = toolbox.finishRun()

    XCTAssertEqual(payload["cuts"] as? Int, 2)
    // Each 3 s pause keeps 0.25 s on both sides → 2.5 s removed per pause.
    XCTAssertEqual(payload["removed_seconds"] as? Double ?? 0, 5, accuracy: 0.1)
    XCTAssertEqual(CMTimeGetSeconds(state.timelineDuration), 7, accuracy: 0.1)
    XCTAssertEqual(summary.changeCount, 2)
    // The zoom stayed on its footage: 10.5 − 5.
    XCTAssertEqual(state.zoomSegments.first?.startTime ?? 0, 5.5, accuracy: 0.1)

    state.undo()
    XCTAssertEqual(CMTimeGetSeconds(state.timelineDuration), 12, accuracy: 0.01)
    XCTAssertEqual(state.zoomSegments.first?.startTime ?? 0, 10.5, accuracy: 0.01)
  }

  func testRemoveSilences_respectsMinDurationAndRange() async throws {
    let state = try await makeState()
    let toolbox = VideoEditorAgentToolbox(state: state)
    let longOnly = await call(toolbox, "remove_silences", #"{"min_duration": 4}"#)
    XCTAssertEqual(longOnly["cuts"] as? Int, 0)
    XCTAssertNotNil(longOnly["note"])

    let early = await call(toolbox, "remove_silences", #"{"end": "0:06", "padding": 0}"#)
    XCTAssertEqual(early["cuts"] as? Int, 1)
    XCTAssertEqual(CMTimeGetSeconds(state.timelineDuration), 9, accuracy: 0.1)
  }

  func testRemoveSilences_afterAnEarlierCutUsesTheNewTimeline() async throws {
    let state = try await makeState()
    let toolbox = VideoEditorAgentToolbox(state: state)
    _ = await call(toolbox, "cut_range", #"{"start": 0, "end": 1}"#)
    _ = await call(toolbox, "remove_silences", #"{"padding": 0}"#)
    // 12 − 1 − 3 − 3.
    XCTAssertEqual(CMTimeGetSeconds(state.timelineDuration), 5, accuracy: 0.1)
  }

  func testSpeedUpIdle_addsBlocksAroundExistingOnes() async throws {
    let state = try await makeState()
    _ = state.addSpeed(range: 7.5 ... 10, rate: 2)
    let toolbox = VideoEditorAgentToolbox(state: state)
    let payload = await call(toolbox, "speed_up_idle", #"{"rate": 6}"#)
    let added = try XCTUnwrap(payload["added"] as? [[String: Any]])
    // 0.3–3.7, and 7.3–11.7 minus the 7.5–10 block → 10–11.7 (7.3–7.5 is too short).
    XCTAssertEqual(added.count, 2)
    XCTAssertEqual(state.speedSegments.count, 3)
    XCTAssertTrue(state.speedSegments.filter { $0.rate == 6 }.allSatisfy { $0.endTime <= 7.5 || $0.startTime >= 10 - 0.001 })
  }

  func testAutoZoomActivity_zoomsOnFocusedWorkAndSkipsExistingZooms() async throws {
    let state = try await makeState()
    let toolbox = VideoEditorAgentToolbox(state: state)
    let payload = await call(toolbox, "auto_zoom_activity", #"{"level": 2.5}"#)
    let added = try XCTUnwrap(payload["added"] as? [[String: Any]])
    XCTAssertEqual(added.count, 1)
    let zoom = try XCTUnwrap(state.zoomSegments.first)
    XCTAssertEqual(zoom.zoomType, .auto)
    XCTAssertEqual(Double(zoom.zoomLevel), 2.5, accuracy: 0.01)
    XCTAssertLessThanOrEqual(zoom.startTime, 4)
    XCTAssertGreaterThanOrEqual(zoom.endTime, 7)

    let again = await call(toolbox, "auto_zoom_activity")
    XCTAssertEqual((again["added"] as? [Any])?.count, 0)
  }

  func testOneStepTools_explainMissingData() async throws {
    let state = try await makeState(audio: false, cursor: false)
    let toolbox = VideoEditorAgentToolbox(state: state)
    for name in ["remove_silences", "speed_up_idle", "auto_zoom_activity"] {
      let result = await toolbox.execute(name: name, argumentsJSON: "{}")
      XCTAssertTrue(result.isError, name)
    }
    let activity = await call(toolbox, "get_activity")
    XCTAssertEqual((activity["spans"] as? [Any])?.count, 0)
    XCTAssertNotNil(activity["note"])
  }

  // MARK: - Quick actions

  private func makeController(
    _ state: VideoEditorState,
    layout: VideoEditorAILayout = .sidebar
  ) -> VideoEditorAgentController {
    let defaults = UserDefaults(suiteName: "SnapzyTests.VideoAnalyzer.\(UUID().uuidString)")!
    defaults.set(layout.rawValue, forKey: PreferencesKeys.videoEditorAILayout)
    let controller = VideoEditorAgentController(
      state: state,
      pacingEnabled: false,
      defaults: defaults,
      resolveProvider: { nil },
      confirmRemoteUse: { _ in XCTFail("quick actions never leave the Mac"); return false }
    )
    retained.append(controller)
    return controller
  }

  private func waitUntil(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    for _ in 0 ..< 500 where !condition() {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertTrue(condition(), "condition not met in time", file: file, line: line)
  }

  func testQuickActions_matchTheVideosData() async throws {
    // Dock layout: chips sit over an empty, idle prompt and hide once the user types.
    let full = makeController(try await makeState(), layout: .dock)
    XCTAssertEqual(full.quickActions, [.removeSilences, .speedUpIdle, .autoZoom])
    XCTAssertFalse(full.showsQuickActions, "only over an open prompt")
    full.presentPrompt()
    XCTAssertTrue(full.showsQuickActions)
    full.draft = "cut"
    XCTAssertFalse(full.showsQuickActions)

    // Sidebar layout (default): chips live in the empty transcript, so typing doesn't hide them.
    let panel = makeController(try await makeState())
    panel.presentPrompt()
    panel.draft = "cut"
    XCTAssertTrue(panel.showsQuickActions)

    let silent = makeController(try await makeState(audio: false, cursor: false))
    XCTAssertEqual(silent.quickActions, [])
  }

  func testQuickAction_runsWithoutProviderAsOneUndoStep() async throws {
    let state = try await makeState()
    let controller = makeController(state)
    controller.runQuickAction(.removeSilences)
    XCTAssertTrue(controller.isRunning)
    await waitUntil { !controller.isRunning }

    XCTAssertEqual(CMTimeGetSeconds(state.timelineDuration), 7, accuracy: 0.1)
    guard case .finished(let message, let count) = controller.notice else {
      return XCTFail("expected a finished notice, got \(String(describing: controller.notice))")
    }
    XCTAssertEqual(count, 2)
    XCTAssertTrue(message.contains("2"), message)
    XCTAssertTrue(controller.turns.isEmpty, "quick actions are not conversation turns")
    XCTAssertTrue(controller.canUndoLastRun)

    controller.undoLastRun()
    XCTAssertEqual(CMTimeGetSeconds(state.timelineDuration), 12, accuracy: 0.01)
  }

  func testMockMapsSilenceAndIdlePrompts() {
    #if DEBUG
    XCTAssertEqual(VideoEditorAgentMockProvider.plan(for: "Cắt các đoạn im lặng").map(\.name), ["remove_silences"])
    XCTAssertEqual(VideoEditorAgentMockProvider.plan(for: "speed up idle parts 6x").map(\.name), ["speed_up_idle"])
    XCTAssertEqual(VideoEditorAgentMockProvider.plan(for: "auto zoom on activity").map(\.name), ["auto_zoom_activity"])
    XCTAssertEqual(VideoEditorAgentMockProvider.plan(for: "mute the video").map(\.name), ["set_audio"])
    #endif
  }

  // MARK: - Live evaluation (opt-in)

  /// Phase 4 prompts through a real agent CLI and the whole controller path (consent, bridge,
  /// `snapzy mcp`, analyzer): `SNAPZY_LIVE_CLI="opencode|opencode-go/deepseek-v4.1-flash"`
  /// (xcodebuild: prefix `TEST_RUNNER_`).
  func testLiveActivityPrompts() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let spec = environment["SNAPZY_LIVE_CLI"] else {
      throw XCTSkip("Set SNAPZY_LIVE_CLI=\"opencode|<model>\" to run a real agent CLI")
    }
    let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
    let kind = try XCTUnwrap(AnnotateAgentCLIKind(rawValue: parts[0]))
    guard FileManager.default.isExecutableFile(atPath: AgentCLIProvider.helperPath) else {
      throw XCTSkip("No embedded snapzy helper at \(AgentCLIProvider.helperPath)")
    }
    let socket = (NSTemporaryDirectory() as NSString).appendingPathComponent("snapzy-live-activity-\(getpid()).sock")
    setenv("SNAPZY_SOCKET", socket, 1)
    CLIServer.shared.stop()
    defer {
      CLIServer.shared.stop()
      unsetenv("SNAPZY_SOCKET")
    }
    let defaults = UserDefaults(suiteName: "SnapzyTests.VideoAnalyzerLive.\(UUID().uuidString)")!
    if parts.count > 1 { defaults.set(parts[1], forKey: kind.modelDefaultsKey) }

    let prompts: [(String, (VideoEditorState) -> Bool)] = [
      ("Cắt các đoạn im lặng", { abs(TimelineSequence.duration($0.clips) - 7) < 0.6 }),
      ("Remove the pauses longer than 2 seconds, keep no padding", { abs(TimelineSequence.duration($0.clips) - 6) < 0.6 }),
      ("Tua nhanh 6x những đoạn tôi ngồi chờ", { state in
        state.speedSegments.count >= 2 && state.speedSegments.allSatisfy { abs($0.rate - 6) < 0.01 }
      }),
      ("Zoom vào chỗ tôi thao tác chuột", { state in
        state.zoomSegments.contains { $0.zoomType == .auto && $0.startTime <= 4.5 && $0.endTime >= 6.5 }
      }),
      ("When do I talk in this video? Just answer, don't edit.", { $0.clips.count == 1 && $0.zoomSegments.isEmpty && $0.speedSegments.isEmpty }),
    ]

    var passed = 0
    var errors = 0
    var lines: [String] = []
    func log(_ line: String) {
      print(line)
      lines.append(line)
    }
    let only = environment["SNAPZY_LIVE_CLI_ONLY"].flatMap(Int.init)
    for (index, (prompt, check)) in prompts.enumerated() where only == nil || only == index + 1 {
      let state = try await makeState()
      let provider = AgentCLIProvider(kind: kind, defaults: defaults)
      let controller = VideoEditorAgentController(
        state: state, pacingEnabled: false, defaults: defaults,
        resolveProvider: { provider }, confirmRemoteUse: { _ in true }
      )
      retained.append(controller)
      let started = Date()
      controller.draft = prompt
      controller.submit()
      for _ in 0 ..< 1800 where controller.isRunning || controller.isConfirmingRemoteUse {
        try? await Task.sleep(nanoseconds: 100_000_000)
      }
      let elapsed = String(format: "%.1fs", Date().timeIntervalSince(started))
      switch controller.notice {
      case .finished(let message, let count):
        let ok = check(state)
        passed += ok ? 1 : 0
        let speeds = state.speedSegments.map { String(format: "%.1f-%.1f@%.0f", $0.startTime, $0.endTime, $0.rate) }.joined(separator: ",")
        let zooms = state.zoomSegments.map { String(format: "%.1f-%.1f %@", $0.startTime, $0.endTime, $0.zoomType == .auto ? "auto" : "manual") }.joined(separator: ",")
        log("[live-activity] \(ok ? "PASS" : "MISS") \(elapsed) “\(prompt)” → \(count) changes, undo=\(controller.canUndoLastRun) duration \(String(format: "%.2f", TimelineSequence.duration(state.clips))) speeds[\(speeds)] zooms[\(zooms)] “\(message)”")
      default:
        errors += 1
        log("[live-activity] ERROR \(elapsed) “\(prompt)” → \(String(describing: controller.notice))")
        controller.stop()
      }
    }
    let total = only == nil ? prompts.count : 1
    log("[live-activity] \(kind.displayName) \(parts.count > 1 ? parts[1] : "default"): \(passed)/\(total) passed, \(errors) errors")
    let report = lines.joined(separator: "\n")
    try? report.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snapzy-live-activity.log"), atomically: true, encoding: .utf8)
    add(XCTAttachment(string: report))
    XCTAssertEqual(errors, 0)
    XCTAssertEqual(AgentBridge.shared.openCount, 0)
  }

  // MARK: - Fixture

  private func makeState(audio: Bool = true, cursor: Bool = true) async throws -> VideoEditorState {
    let state = try await VideoEditorActivityFixture.makeState(in: tempDirectory, audio: audio, cursor: cursor)
    XCTAssertFalse(state.clips.isEmpty)
    XCTAssertEqual(state.hasMouseTrackingData, cursor)
    XCTAssertEqual(state.audioTrackRoles.isEmpty, !audio)
    retained.append(state)
    return state
  }
}
