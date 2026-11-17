//
//  VideoEditorAgentControllerTests.swift
//  SnapzyTests
//
//  Video Editor AI prompt, phase 3: the run loop behind the dock (submit, stop,
//  result, one-step undo, conversation, consent scope) with a scripted provider,
//  plus the debug mock's planning and the unsaved-changes fix for frame layout.
//

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
@testable import Snapzy
import XCTest

@MainActor
final class VideoEditorAgentControllerTests: XCTestCase {
  private var tempDirectory: URL!
  private var retained: [AnyObject] = []
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUp() {
    super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_VideoAgentController_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    suiteName = "VideoEditorAgentControllerTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDirectory)
    defaults.removePersistentDomain(forName: suiteName)
    retained = []
    super.tearDown()
  }

  /// Calls a fixed list of tools; can wait on a gate to test Stop mid-run.
  private final class ScriptedProvider: AgentProvider {
    let displayName = "Scripted"
    let symbolName = "hammer"
    var calls: [(String, String)]
    var reply = "Done."
    var error: Error?
    var destination: AgentRemoteDestination?
    var gate: CheckedContinuation<Void, Never>?
    var waitsAfterFirstCall = false
    private(set) var requests: [AgentRequest] = []
    private(set) var results: [AgentToolResult] = []

    var remoteDestination: AgentRemoteDestination? { destination }

    init(calls: [(String, String)]) {
      self.calls = calls
    }

    func run(_ request: AgentRequest, session: AgentSession) async throws -> String {
      requests.append(request)
      for (index, call) in calls.enumerated() {
        results.append(try await session.callTool(call.0, arguments: call.1))
        if index == 0, waitsAfterFirstCall {
          await withCheckedContinuation { gate = $0 }
          try Task.checkCancellation()
        }
      }
      if let error { throw error }
      return reply
    }
  }

  private let speedCall = ("add_speed", #"{"start":2,"end":6,"rate":4}"#)
  private let zoomCall = ("add_zoom", #"{"start":1,"level":2}"#)

  private func makeState(duration: TimeInterval = 12) async throws -> VideoEditorState {
    let state = VideoEditorState(url: try await makeVideoFile(duration: duration))
    await state.loadMetadata()
    XCTAssertFalse(state.clips.isEmpty)
    retained.append(state)
    return state
  }

  private func makeController(
    _ state: VideoEditorState,
    provider: AgentProvider?,
    confirm: (@MainActor (AgentRemoteDestination) async -> Bool)? = nil
  ) -> VideoEditorAgentController {
    let controller = VideoEditorAgentController(
      state: state,
      pacingEnabled: false,
      defaults: defaults,
      resolveProvider: { provider },
      confirmRemoteUse: confirm ?? { _ in XCTFail("unexpected consent prompt"); return false }
    )
    retained.append(controller)
    return controller
  }

  private func waitUntil(
    _ condition: @MainActor () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    for _ in 0 ..< 400 where !condition() {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertTrue(condition(), "condition not met in time", file: file, line: line)
  }

  // MARK: - Runs

  func testSubmitRunsProviderAsOneUndoStep() async throws {
    let state = try await makeState()
    let provider = ScriptedProvider(calls: [speedCall, zoomCall])
    let controller = makeController(state, provider: provider)

    controller.draft = "  speed it up  "
    controller.submit()
    XCTAssertTrue(controller.isRunning)
    XCTAssertEqual(controller.draft, "")
    await waitUntil { !controller.isRunning }

    XCTAssertEqual(provider.requests.first?.prompt, "speed it up")
    XCTAssertNil(provider.requests.first?.image)
    XCTAssertTrue(provider.requests.first?.sceneJSON.contains("\"clips\"") ?? false)
    XCTAssertEqual(state.speedSegments.count, 1)
    XCTAssertEqual(state.zoomSegments.count, 1)
    XCTAssertEqual(controller.notice, .finished(message: "Done.", changeCount: 2))
    XCTAssertEqual(controller.turns.count, 1)
    XCTAssertTrue(controller.canUndoLastRun)
    guard case .group(let actions)? = state.lastUndoEntry else {
      return XCTFail("expected one grouped undo entry, got \(String(describing: state.lastUndoEntry))")
    }
    XCTAssertEqual(actions.count, 2)

    controller.undoLastRun()
    XCTAssertTrue(state.speedSegments.isEmpty)
    XCTAssertTrue(state.zoomSegments.isEmpty)
    XCTAssertTrue(controller.turns.isEmpty)
    XCTAssertNil(controller.notice)
    XCTAssertFalse(controller.canUndoLastRun)
  }

  func testUndoIsWithdrawnOnceTheUserEdits() async throws {
    let state = try await makeState()
    let controller = makeController(state, provider: ScriptedProvider(calls: [speedCall]))
    controller.draft = "speed"
    controller.submit()
    await waitUntil { !controller.isRunning }
    XCTAssertTrue(controller.canUndoLastRun)

    state.addZoom(at: 8)
    XCTAssertFalse(controller.canUndoLastRun)
  }

  func testStopKeepsChangesAndOffersUndo() async throws {
    let state = try await makeState()
    let provider = ScriptedProvider(calls: [speedCall, zoomCall])
    provider.waitsAfterFirstCall = true
    let controller = makeController(state, provider: provider)

    controller.draft = "go"
    controller.submit()
    await waitUntil { provider.gate != nil }
    XCTAssertEqual(controller.phase, .acting)
    // A run's changes are not on the undo stack yet: ⌘Z mid-run does nothing.
    state.undo()
    XCTAssertEqual(state.speedSegments.count, 1)

    controller.stop()
    provider.gate?.resume()
    XCTAssertFalse(controller.isRunning)
    XCTAssertEqual(controller.notice, .stopped(changeCount: 1))
    XCTAssertFalse(state.isUndoGroupOpen)
    XCTAssertTrue(controller.canUndoLastRun)
    try? await Task.sleep(nanoseconds: 50_000_000)
    // The provider's late call bounced: the zoom never landed.
    XCTAssertTrue(state.zoomSegments.isEmpty)

    controller.undoLastRun()
    XCTAssertTrue(state.speedSegments.isEmpty)
  }

  func testUndoingAStoppedRunKeepsTheEarlierTurn() async throws {
    let state = try await makeState()
    let provider = ScriptedProvider(calls: [zoomCall])
    let controller = makeController(state, provider: provider)
    controller.draft = "first"
    controller.submit()
    await waitUntil { !controller.isRunning }
    XCTAssertEqual(controller.turns.count, 1)

    provider.calls = [speedCall, zoomCall]
    provider.waitsAfterFirstCall = true
    controller.draft = "second"
    controller.submit()
    await waitUntil { provider.gate != nil }
    controller.stop()
    provider.gate?.resume()
    controller.undoLastRun()
    XCTAssertTrue(state.speedSegments.isEmpty)
    XCTAssertEqual(state.zoomSegments.count, 1, "the first run's zoom stays")
    XCTAssertEqual(controller.turns.map(\.prompt), ["first"])
  }

  func testPlainKeyShortcutsStandDownWhilePromptIsOpen() async throws {
    let state = try await makeState()
    let controller = makeController(state, provider: nil)
    XCTAssertTrue(controller.allowsPlainKeyShortcuts)
    controller.presentPrompt()
    XCTAssertFalse(controller.allowsPlainKeyShortcuts)
    controller.dismissPrompt()
    XCTAssertTrue(controller.allowsPlainKeyShortcuts)
  }

  func testProviderErrorIsShownAndChangesStayUndoable() async throws {
    let state = try await makeState()
    let provider = ScriptedProvider(calls: [speedCall])
    provider.error = AgentProviderError.needsSetup("Install OpenCode")
    let controller = makeController(state, provider: provider)

    controller.draft = "go"
    controller.submit()
    await waitUntil { !controller.isRunning }
    XCTAssertEqual(controller.notice, .failed(message: "Install OpenCode", offersSettings: true))
    XCTAssertTrue(controller.canUndoLastRun)
    XCTAssertTrue(controller.turns.isEmpty)
  }

  func testNoProviderAsksForSetup() async throws {
    let state = try await makeState()
    let controller = makeController(state, provider: nil)
    controller.draft = "go"
    controller.submit()
    XCTAssertFalse(controller.isRunning)
    XCTAssertEqual(controller.notice, .failed(message: L10n.VideoEditorAI.notConfigured, offersSettings: true))
    XCTAssertEqual(controller.draft, "go", "the prompt is kept for after setup")
  }

  func testExportingRefusesToRun() async throws {
    let state = try await makeState()
    let provider = ScriptedProvider(calls: [speedCall])
    let controller = makeController(state, provider: provider)
    state.isExporting = true
    controller.draft = "go"
    controller.submit()
    state.isExporting = false
    XCTAssertFalse(controller.isRunning)
    XCTAssertTrue(provider.requests.isEmpty)
    XCTAssertEqual(controller.notice, .failed(message: L10n.VideoEditorAI.busy, offersSettings: false))
  }

  func testFollowUpCarriesHistoryAndNewConversationForgetsIt() async throws {
    let state = try await makeState()
    let provider = ScriptedProvider(calls: [zoomCall])
    let controller = makeController(state, provider: provider)

    controller.draft = "first"
    controller.submit()
    await waitUntil { !controller.isRunning }
    controller.draft = "second"
    controller.submit()
    await waitUntil { !controller.isRunning }
    XCTAssertEqual(provider.requests.last?.history.map(\.prompt), ["first"])

    controller.startNewConversation()
    XCTAssertFalse(controller.hasConversation)
  }

  // MARK: - Consent

  func testRemoteProviderAsksOnceWithVideoScope() async throws {
    let state = try await makeState()
    let provider = ScriptedProvider(calls: [zoomCall])
    let destination = AgentRemoteDestination(id: "endpoint:test", name: "Test", host: "example.test")
    provider.destination = destination
    // Agreeing for Annotate (no scope) does not cover video.
    AgentRemoteConsent(defaults: defaults).record(destination)
    var asked = 0
    let controller = makeController(state, provider: provider) { _ in
      asked += 1
      return true
    }

    controller.draft = "zoom"
    controller.submit()
    await waitUntil { !provider.requests.isEmpty && !controller.isRunning }
    XCTAssertEqual(asked, 1)
    XCTAssertTrue(AgentRemoteConsent(defaults: defaults, scope: VideoEditorAgentController.consentScope).has(destination))

    controller.draft = "again"
    controller.submit()
    await waitUntil { provider.requests.count == 2 && !controller.isRunning }
    XCTAssertEqual(asked, 1)
  }

  func testDeclinedConsentSendsNothing() async throws {
    let state = try await makeState()
    let provider = ScriptedProvider(calls: [zoomCall])
    provider.destination = AgentRemoteDestination(id: "cli:opencode", name: "OpenCode", host: "OpenCode", kind: .agentCLI)
    let controller = makeController(state, provider: provider) { _ in false }

    controller.draft = "zoom"
    controller.submit()
    await waitUntil { !controller.isConfirmingRemoteUse }
    XCTAssertTrue(provider.requests.isEmpty)
    XCTAssertEqual(controller.draft, "zoom")
  }

  // MARK: - Prompt

  func testShortcutOpensRefocusesAndCloses() async throws {
    let state = try await makeState()
    let controller = makeController(state, provider: nil)
    controller.handleShortcut(isFieldEditing: false)
    XCTAssertTrue(controller.isPromptPresented)
    let request = controller.promptFocusRequest
    controller.handleShortcut(isFieldEditing: false)
    XCTAssertTrue(controller.isPromptPresented)
    XCTAssertGreaterThan(controller.promptFocusRequest, request)
    controller.handleShortcut(isFieldEditing: true)
    XCTAssertFalse(controller.isPromptPresented)
  }

  func testEscapeClearsDraftThenCloses() async throws {
    let state = try await makeState()
    let controller = makeController(state, provider: nil)
    controller.presentPrompt()
    controller.draft = "abc"
    controller.handleEscape()
    XCTAssertEqual(controller.draft, "")
    XCTAssertTrue(controller.isPromptPresented)
    controller.handleEscape()
    XCTAssertFalse(controller.isPromptPresented)
  }

  // MARK: - Mock planning

  func testMockPlansTheMVPPrompt() {
    let calls = VideoEditorAgentMockProvider.plan(for: "Tua 4x từ 0:10 đến 0:30, zoom 2x ở 0:05")
    XCTAssertEqual(calls.map(\.name), ["add_speed", "add_zoom"])
    XCTAssertEqual(json(calls[0].arguments)["rate"] as? Double, 4)
    XCTAssertEqual(json(calls[0].arguments)["start"] as? Double, 10)
    XCTAssertEqual(json(calls[0].arguments)["end"] as? Double, 30)
    XCTAssertEqual(json(calls[1].arguments)["start"] as? Double, 5)
    XCTAssertEqual(json(calls[1].arguments)["level"] as? Double, 2)
  }

  func testMockCutsLatestFirst() {
    let calls = VideoEditorAgentMockProvider.plan(for: "cut 0:02 to 0:04 and cut 0:08-0:09; background padding 20")
    XCTAssertEqual(calls.map(\.name), ["cut_range", "cut_range", "set_background"])
    XCTAssertEqual(calls[0].time, 8)
    XCTAssertEqual(calls[1].time, 2)
    XCTAssertEqual(json(calls[2].arguments)["padding"] as? Double, 20)
  }

  func testMockRunEditsTheTimeline() async throws {
    let state = try await makeState(duration: 32)
    let mock = VideoEditorAgentMockProvider()
    mock.thinkingDelay = 0
    let controller = makeController(state, provider: mock)
    controller.draft = "Tua 4x từ 0:10 đến 0:30, zoom 2x ở 0:05"
    controller.submit()
    await waitUntil { !controller.isRunning }
    XCTAssertEqual(state.speedSegments.first?.rate ?? 0, 4, accuracy: 0.001)
    XCTAssertEqual(state.zoomSegments.first?.zoomLevel ?? 0, 2, accuracy: 0.001)
    XCTAssertEqual(controller.notice, .finished(message: "Mock agent made 2 changes.", changeCount: 2))
  }

  // MARK: - Unsaved changes

  func testFrameLayoutCountsAsUnsavedChange() async throws {
    let state = try await makeState()
    state.markAsSaved()
    state.backgroundAspectRatio = .ratio16x9
    await waitUntil { state.hasUnsavedChanges }
    state.backgroundAspectRatio = .auto
    await waitUntil { !state.hasUnsavedChanges }
    state.backgroundAlignment = .topLeft
    await waitUntil { state.hasUnsavedChanges }
  }

  // MARK: - Live evaluation (opt-in)

  /// Runs the MVP prompts through a real agent CLI and the whole controller path
  /// (consent, bridge, `snapzy mcp`, one undo step per prompt):
  /// `SNAPZY_LIVE_CLI="opencode|opencode-go/deepseek-v4.1-flash"` (xcodebuild: prefix `TEST_RUNNER_`).
  func testLiveVideoPrompts() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let spec = environment["SNAPZY_LIVE_CLI"] else {
      throw XCTSkip("Set SNAPZY_LIVE_CLI=\"opencode|<model>\" to run a real agent CLI")
    }
    let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
    let kind = try XCTUnwrap(AnnotateAgentCLIKind(rawValue: parts[0]))
    guard FileManager.default.isExecutableFile(atPath: AgentCLIProvider.helperPath) else {
      throw XCTSkip("No embedded snapzy helper at \(AgentCLIProvider.helperPath)")
    }
    // Never touch the socket of a Snapzy that is running on this Mac.
    let socket = (NSTemporaryDirectory() as NSString).appendingPathComponent("snapzy-live-video-\(getpid()).sock")
    setenv("SNAPZY_SOCKET", socket, 1)
    CLIServer.shared.stop()
    defer {
      CLIServer.shared.stop()
      unsetenv("SNAPZY_SOCKET")
    }
    if parts.count > 1 { defaults.set(parts[1], forKey: kind.modelDefaultsKey) }

    let prompts: [(String, (VideoEditorState) -> Bool)] = [
      ("Tua 4x từ 0:10 đến 0:30, zoom 2x ở 0:05", { state in
        state.speedSegments.contains { abs($0.rate - 4) < 0.01 && abs($0.startTime - 10) < 0.6 && abs($0.endTime - 30) < 0.6 }
          && state.zoomSegments.contains { abs($0.zoomLevel - 2) < 0.01 && abs($0.startTime - 5) < 0.6 }
      }),
      ("Cắt bỏ đoạn từ 0:02 đến 0:04", { abs(TimelineSequence.duration($0.clips) - 38) < 0.3 }),
      ("Nền gradient, padding 40, bo góc 12", { $0.backgroundPadding == 40 && $0.backgroundCornerRadius == 12 && $0.backgroundStyle != .none }),
      ("Mute the video", { $0.exportSettings.audioMode == .mute }),
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
      let state = try await makeState(duration: 40)
      let provider = AgentCLIProvider(kind: kind, defaults: defaults)
      let controller = makeController(state, provider: provider) { _ in true }
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
        let speeds = state.speedSegments.map { "\($0.startTime)-\($0.endTime)@\($0.rate)" }.joined(separator: ",")
        let zooms = state.zoomSegments.map { "\($0.startTime)x\($0.zoomLevel)" }.joined(separator: ",")
        log("[live-video] \(ok ? "PASS" : "MISS") \(elapsed) “\(prompt)” → \(count) changes, undo=\(controller.canUndoLastRun) speeds[\(speeds)] zooms[\(zooms)] duration \(TimelineSequence.duration(state.clips)) “\(message)”")
      default:
        errors += 1
        log("[live-video] ERROR \(elapsed) “\(prompt)” → \(String(describing: controller.notice))")
        controller.stop()
      }
    }
    let total = only == nil ? prompts.count : 1
    log("[live-video] \(kind.displayName) \(parts.count > 1 ? parts[1] : "default"): \(passed)/\(total) passed, \(errors) errors")
    let report = lines.joined(separator: "\n")
    try? report.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snapzy-live-video.log"), atomically: true, encoding: .utf8)
    add(XCTAttachment(string: report))
    XCTAssertEqual(errors, 0)
    XCTAssertEqual(AgentBridge.shared.openCount, 0)
  }

  // MARK: - Helpers

  private func json(_ text: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
  }

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
