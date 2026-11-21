//
//  VideoEditorAgentVisionTests.swift
//  SnapzyTests
//
//  Video agent phase 6: frames and on-screen text (`get_frame`, `find_on_screen`,
//  `add_zoom(text:)`), speech (`get_transcript`, engine stubbed), and how tool
//  images reach providers (endpoint user message, `snapzy mcp` bridge).
//
//  Text fixture: 10 s, 640×360, white. "Snapzy Demo" top left the whole time;
//  "Deploy" from 4 s on, centered near (0.75, 0.78). Real Vision OCR reads it.
//

import AppKit
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
@testable import Snapzy
import SnapzyCLIProtocol
import XCTest

@MainActor
final class VideoEditorAgentVisionTests: XCTestCase {
  private var tempDirectory: URL!
  private var retained: [AnyObject] = []

  override func setUp() {
    super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_VideoVision_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    retained = []
    super.tearDown()
  }

  // MARK: - Pure: matching & sampling

  func testBestMatch_prefersExactLabelAndNarrowsBoxToWords() {
    let lines = [
      VideoEditorScreenText(text: "Click Deploy to ship it", box: CGRect(x: 0.1, y: 0.1, width: 0.46, height: 0.05)),
      VideoEditorScreenText(text: "Deploy", box: CGRect(x: 0.7, y: 0.8, width: 0.1, height: 0.04)),
    ]
    let exact = VideoEditorAgentVision.bestMatch("deploy", in: lines)
    XCTAssertEqual(exact?.line, "Deploy")
    XCTAssertEqual(exact!.box.minX, 0.7, accuracy: 0.001)
    XCTAssertEqual(exact!.box.width, 0.1, accuracy: 0.001)

    // Only inside a sentence: the box covers the word, not the whole line.
    let narrowed = VideoEditorAgentVision.bestMatch("DEPLOY", in: [lines[0]])
    XCTAssertNotNil(narrowed)
    XCTAssertEqual(narrowed!.box.minX, 0.1 + 0.46 * 6 / 23, accuracy: 0.001)
    XCTAssertEqual(narrowed!.box.width, 0.46 * 6 / 23, accuracy: 0.001)

    // Accents and spacing don't matter; absent text doesn't match.
    let accented = [VideoEditorScreenText(text: "Cài đặt", box: CGRect(x: 0, y: 0, width: 0.2, height: 0.1))]
    XCTAssertNotNil(VideoEditorAgentVision.bestMatch("cai dat", in: accented))
    XCTAssertNotNil(VideoEditorAgentVision.bestMatch("caidat", in: accented))
    XCTAssertNil(VideoEditorAgentVision.bestMatch("settings", in: accented))
    XCTAssertNil(VideoEditorAgentVision.bestMatch("  ", in: lines))
  }

  func testBestMatch_wholeWordBeatsInsideAWord() {
    let lines = [
      VideoEditorScreenText(text: "Cookbook", box: CGRect(x: 0, y: 0, width: 0.2, height: 0.05)),
      VideoEditorScreenText(text: "Click OK now", box: CGRect(x: 0.5, y: 0.5, width: 0.3, height: 0.05)),
    ]
    XCTAssertEqual(VideoEditorAgentVision.bestMatch("ok", in: lines)?.line, "Click OK now")
    XCTAssertEqual(VideoEditorAgentVision.bestMatch("ok", in: [lines[0]])?.line, "Cookbook", "still found when nothing better")
  }

  func testSpeechLocale_normalizesSeparatorsAndDropsExtensions() {
    XCTAssertEqual(VideoEditorAgentToolbox.speechLocale("vi_VN").identifier.replacingOccurrences(of: "_", with: "-"), "vi-VN")
    XCTAssertFalse(VideoEditorAgentToolbox.speechLocale(nil).identifier.contains("@"))
  }

  func testSampleTimes_spreadAcrossFootageWithCap() {
    let short = VideoEditorAgentVision.sampleTimes(spans: [0 ... 10], window: 0 ... 10)
    XCTAssertEqual(short.count, 10, "1 s apart on a short video")
    XCTAssertEqual(short.first!, 0.05, accuracy: 0.001)

    let long = VideoEditorAgentVision.sampleTimes(spans: [0 ... 600], window: 0 ... 600)
    XCTAssertLessThanOrEqual(long.count, VideoEditorAgentVision.maximumSamples)
    XCTAssertGreaterThan(long.count, VideoEditorAgentVision.maximumSamples - 2)

    // Gaps (trimmed footage) are skipped; a span shorter than a step still gets its middle.
    let gapped = VideoEditorAgentVision.sampleTimes(spans: [0 ... 3, 5 ... 5.4], window: 0 ... 10)
    XCTAssertFalse(gapped.contains { $0 > 3 && $0 < 5 })
    XCTAssertTrue(gapped.contains { abs($0 - 5.2) < 0.001 })
    // Window narrows it.
    XCTAssertTrue(VideoEditorAgentVision.sampleTimes(spans: [0 ... 10], window: 6 ... 8).allSatisfy { $0 >= 6 && $0 <= 8 })
  }

  func testTranscriptPhrases_breakOnPausesSentencesAndLength() {
    let words: [VideoEditorTranscriptWord] = [
      .init(start: 0.0, duration: 0.3, text: "Open"),
      .init(start: 0.4, duration: 0.3, text: "settings."),
      .init(start: 0.8, duration: 0.3, text: "Then"),
      .init(start: 1.2, duration: 0.3, text: "deploy"),
      .init(start: 3.0, duration: 0.3, text: "Done"),
    ]
    let phrases = VideoEditorAgentTranscriber.phrases(words)
    XCTAssertEqual(phrases.map(\.text), ["Open settings.", "Then deploy", "Done"])
    XCTAssertEqual(phrases[1].range.lowerBound, 0.8, accuracy: 0.001)
    XCTAssertEqual(phrases[1].range.upperBound, 1.5, accuracy: 0.001)

    let long = (0 ..< 40).map { VideoEditorTranscriptWord(start: Double($0) * 0.5, duration: 0.4, text: "word") }
    XCTAssertTrue(VideoEditorAgentTranscriber.phrases(long, maxLength: 5).allSatisfy {
      $0.range.upperBound - $0.range.lowerBound <= 5.001
    })
  }

  // MARK: - Catalog

  func testCatalog_mediaToolsAreReadOnlyAndAddZoomTakesText() throws {
    for tool in [VideoEditorAgentToolName.getFrame, .findOnScreen, .getTranscript] {
      XCTAssertTrue(tool.isReadOnly, tool.rawValue)
      XCTAssertTrue(tool.readsMedia, tool.rawValue)
      XCTAssertTrue(VideoEditorAgentToolCatalog.all.contains { $0.name == tool.rawValue }, tool.rawValue)
    }
    let addZoom = try XCTUnwrap(VideoEditorAgentToolCatalog.all.first { $0.name == "add_zoom" })
    let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(addZoom.parametersJSON.utf8)) as? [String: Any])
    XCTAssertNotNil((schema["properties"] as? [String: Any])?["text"])
    XCTAssertNil(schema["required"], "start is optional when text is given")
  }

  // MARK: - Frames & on-screen text (real OCR)

  func testGetFrame_returnsImageAndTextWithBoxes() async throws {
    let (state, toolbox) = try await makeTextToolbox()

    let later = await toolbox.execute(name: "get_frame", argumentsJSON: #"{"time": 6}"#)
    XCTAssertFalse(later.isError, later.text)
    XCTAssertNotNil(later.image, "vision providers get the frame")
    XCTAssertEqual(later.image?.mimeType, "image/jpeg")
    let payload = try json(later)
    let lines = try XCTUnwrap(payload["text"] as? [[String: Any]])
    let deploy = try XCTUnwrap(lines.first { ($0["text"] as? String)?.localizedCaseInsensitiveContains("deploy") == true })
    let box = try XCTUnwrap(deploy["box"] as? [Double])
    XCTAssertEqual(box[0] + box[2] / 2, TextFixture.deployCenter.x, accuracy: 0.08)
    XCTAssertEqual(box[1] + box[3] / 2, TextFixture.deployCenter.y, accuracy: 0.08)
    XCTAssertEqual(payload["size"] as? [Int], [640, 360])

    let early = try json(await toolbox.execute(name: "get_frame", argumentsJSON: #"{"time": "0:01"}"#))
    let earlyText = (early["text"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: " ")
    XCTAssertFalse(earlyText.localizedCaseInsensitiveContains("deploy"))
    XCTAssertTrue(earlyText.localizedCaseInsensitiveContains("snapzy"))

    // Nothing changed: read-only.
    XCTAssertTrue(state.zoomSegments.isEmpty)
    XCTAssertEqual(toolbox.finishRun().changeCount, 0)
  }

  func testFindOnScreen_reportsFirstAppearanceNarrowedDown() async throws {
    let (_, toolbox) = try await makeTextToolbox()
    let result = await toolbox.execute(name: "find_on_screen", argumentsJSON: #"{"text": "deploy"}"#)
    XCTAssertFalse(result.isError, result.text)
    let matches = try XCTUnwrap(try json(result)["matches"] as? [[String: Any]])
    XCTAssertEqual(matches.count, 1)
    let start = try XCTUnwrap(matches[0]["start"] as? Double)
    XCTAssertEqual(start, TextFixture.deployAppears, accuracy: VideoEditorAgentVision.refinePrecision + 0.15)
    XCTAssertGreaterThanOrEqual(matches[0]["end"] as? Double ?? 0, 9)
    let center = try XCTUnwrap(matches[0]["center"] as? [Double])
    XCTAssertEqual(center[0], TextFixture.deployCenter.x, accuracy: 0.08)
    XCTAssertEqual(center[1], TextFixture.deployCenter.y, accuracy: 0.08)

    let missing = try json(await toolbox.execute(name: "find_on_screen", argumentsJSON: #"{"text": "Publish"}"#))
    XCTAssertEqual((missing["matches"] as? [Any])?.count, 0)
    XCTAssertTrue((missing["note"] as? String ?? "").localizedCaseInsensitiveContains("snapzy"), "suggests text that is there")

    let windowed = try json(await toolbox.execute(name: "find_on_screen", argumentsJSON: #"{"text": "deploy", "end": 3}"#))
    XCTAssertEqual((windowed["matches"] as? [Any])?.count, 0, "before it appears")
  }

  func testAddZoomOnText_startsWhenItAppearsCenteredOnIt() async throws {
    let (state, toolbox) = try await makeTextToolbox()
    let result = await toolbox.execute(name: "add_zoom", argumentsJSON: #"{"text": "Deploy", "level": 2.5}"#)
    XCTAssertFalse(result.isError, result.text)
    let zoom = try XCTUnwrap(state.zoomSegments.first)
    XCTAssertEqual(state.zoomSegments.count, 1)
    XCTAssertEqual(zoom.startTime, TextFixture.deployAppears, accuracy: VideoEditorAgentVision.refinePrecision + 0.15)
    XCTAssertEqual(zoom.zoomType, .manual)
    XCTAssertEqual(zoom.zoomLevel, 2.5, accuracy: 0.001)
    XCTAssertEqual(zoom.zoomCenter.x, TextFixture.deployCenter.x, accuracy: 0.08)
    XCTAssertEqual(zoom.zoomCenter.y, TextFixture.deployCenter.y, accuracy: 0.08)
    let payload = try json(result)
    XCTAssertEqual(payload["id"] as? String, "z1")
    XCTAssertNotNil(payload["found"])

    let summary = toolbox.finishRun()
    XCTAssertEqual(summary.changeCount, 1)
    XCTAssertNotNil(summary.undoEntry)
    state.undo()
    XCTAssertTrue(state.zoomSegments.isEmpty, "one undo removes it")
  }

  func testAddZoomOnText_missingTextFailsWithWhatIsOnScreen() async throws {
    let (state, toolbox) = try await makeTextToolbox()
    let result = await toolbox.execute(name: "add_zoom", argumentsJSON: #"{"text": "Publish"}"#)
    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.text.contains("Publish"))
    XCTAssertTrue(result.text.localizedCaseInsensitiveContains("snapzy"), result.text)
    XCTAssertTrue(state.zoomSegments.isEmpty)

    // No start and no text: says what is missing.
    let bare = await toolbox.execute(name: "add_zoom", argumentsJSON: #"{"level": 2}"#)
    XCTAssertTrue(bare.isError)
    XCTAssertTrue(bare.text.contains("start"), bare.text)
    XCTAssertEqual(toolbox.finishRun().changeCount, 0)
  }

  func testFindOnScreen_followsCutsOnTheTimeline() async throws {
    let (state, toolbox) = try await makeTextToolbox()
    let cut = await toolbox.execute(name: "cut_range", argumentsJSON: #"{"start": 1, "end": 3}"#)
    XCTAssertFalse(cut.isError)
    let found = try json(await toolbox.execute(name: "find_on_screen", argumentsJSON: #"{"text": "deploy"}"#))
    let matches = try XCTUnwrap(found["matches"] as? [[String: Any]])
    let start = try XCTUnwrap(matches.first?["start"] as? Double)
    XCTAssertEqual(start, TextFixture.deployAppears - 2, accuracy: VideoEditorAgentVision.refinePrecision + 0.15)
    _ = toolbox.finishRun()
    _ = state
  }

  // MARK: - Transcript (engine stubbed)

  func testGetTranscript_mapsPhrasesOntoTheEditedTimeline() async throws {
    let words: [VideoEditorTranscriptWord] = [
      .init(start: 0.2, duration: 0.5, text: "Hello"),
      .init(start: 0.8, duration: 0.5, text: "there."),
      .init(start: 5.2, duration: 0.6, text: "Now"),
      .init(start: 5.9, duration: 0.6, text: "deploy."),
      .init(start: 10.5, duration: 0.5, text: "Bye."),
    ]
    let calls = Counter()
    let transcriber = VideoEditorAgentTranscriber(engine: transcriptEngine { locale in
      calls.increment()
      XCTAssertEqual(locale.identifier.replacingOccurrences(of: "_", with: "-"), "vi-VN")
      return words
    })
    let (state, toolbox) = try await makeActivityToolbox(transcriber: transcriber)

    // Cut 2–5: speech after it slides 3 s left.
    let cut = await toolbox.execute(name: "cut_range", argumentsJSON: #"{"start": 2, "end": 5}"#)
    XCTAssertFalse(cut.isError)
    let result = await toolbox.execute(name: "get_transcript", argumentsJSON: #"{"language": "vi_VN"}"#)
    XCTAssertFalse(result.isError, result.text)
    let phrases = try XCTUnwrap(try json(result)["phrases"] as? [[String: Any]])
    XCTAssertEqual(phrases.compactMap { $0["text"] as? String }, ["Hello there.", "Now deploy.", "Bye."])
    XCTAssertEqual(phrases[1]["start"] as? Double ?? 0, 2.2, accuracy: 0.02)
    XCTAssertEqual(phrases[2]["start"] as? Double ?? 0, 7.5, accuracy: 0.02)

    // Window, and the second call reads from cache.
    let windowed = try json(await toolbox.execute(name: "get_transcript", argumentsJSON: #"{"start": 2, "end": 4, "language": "vi-VN"}"#))
    XCTAssertEqual((windowed["phrases"] as? [[String: Any]])?.compactMap { $0["text"] as? String }, ["Now deploy."])
    XCTAssertEqual(calls.value, 1)
    XCTAssertEqual(toolbox.finishRun().changeCount, 1, "only the cut")
    _ = state
  }

  func testGetTranscript_errorsAreWrittenForTheModel() async throws {
    let denied = VideoEditorAgentTranscriber(engine: transcriptEngine { _ in throw VideoEditorTranscriptError.denied })
    let (_, toolbox) = try await makeActivityToolbox(transcriber: denied)
    let result = await toolbox.execute(name: "get_transcript", argumentsJSON: "{}")
    XCTAssertTrue(result.isError)
    XCTAssertTrue(result.text.contains("Speech Recognition"), result.text)

    let silent = VideoEditorAgentTranscriber(engine: transcriptEngine { _ in [] })
    let (_, quiet) = try await makeActivityToolbox(transcriber: silent)
    let empty = try json(await quiet.execute(name: "get_transcript", argumentsJSON: "{}"))
    XCTAssertEqual((empty["phrases"] as? [Any])?.count, 0)
    XCTAssertNotNil(empty["note"])

    let state = try await VideoEditorActivityFixture.makeState(in: tempDirectory, audio: false)
    retained.append(state)
    let noAudio = VideoEditorAgentToolbox(state: state, analyzer: VideoEditorAgentAnalyzer(transcriber: silent))
    let failure = await noAudio.execute(name: "get_transcript", argumentsJSON: "{}")
    XCTAssertTrue(failure.isError)
    XCTAssertTrue(failure.text.contains("no audio"), failure.text)
  }

  // MARK: - Tool images → providers

  func testEndpointConversation_toolImagesFollowAsOneUserMessage() throws {
    let image = AgentToolImage(mimeType: "image/jpeg", base64: "AAAA", pixelSize: CGSize(width: 640, height: 360))
    XCTAssertNil(AgentEndpointProvider.Conversation.toolImagesMessage([]))
    let message = try XCTUnwrap(AgentEndpointProvider.Conversation.toolImagesMessage([("get_frame", image)]))
    XCTAssertEqual(message["role"] as? String, "user")
    let parts = try XCTUnwrap(message["content"] as? [[String: Any]])
    XCTAssertEqual(parts.count, 2)
    XCTAssertTrue((parts[0]["text"] as? String ?? "").contains("get_frame"))
    XCTAssertEqual((parts[1]["image_url"] as? [String: Any])?["url"] as? String, "data:image/jpeg;base64,AAAA")

    let conversation = AgentEndpointProvider.Conversation(
      request: AgentRequest(prompt: "x", history: [], sceneJSON: "{}"),
      image: nil
    )
    XCTAssertFalse(conversation.hasImages(in: [["role": "user", "content": "text"]]))
    XCTAssertTrue(conversation.hasImages(in: [message]), "a rejected tool image can be dropped and retried")
    let stripped = AgentEndpointProvider.Conversation.removingImages(from: [message])
    XCTAssertFalse(conversation.hasImages(in: stripped))
  }

  func testEndpointConversation_keepsOnlyRecentToolImages() throws {
    let image = AgentToolImage(mimeType: "image/jpeg", base64: "AAAA", pixelSize: CGSize(width: 1, height: 1))
    var messages: [[String: Any]] = [["role": "system", "content": "s"]]
    for _ in 0 ..< 3 {
      messages = AgentEndpointProvider.Conversation.keepingRecentToolImages(messages, limit: AgentEndpointProvider.Conversation.toolImageHistory - 1)
      messages.append(try XCTUnwrap(AgentEndpointProvider.Conversation.toolImagesMessage([("get_frame", image)])))
    }
    let withImages = messages.filter { ($0["content"] as? [[String: Any]])?.contains { $0["type"] as? String == "image_url" } ?? false }
    XCTAssertEqual(withImages.count, 2)
    XCTAssertTrue((messages[1]["content"] as? String ?? "").contains("no longer attached"))
  }

  func testBridge_passesToolImagesOnlyWhenAllowed() async throws {
    let toolbox = ImageToolbox()
    let session = AgentSession(toolbox: toolbox, pacingEnabled: false, onToolCall: { _ in })
    let bridge = AgentBridge()

    let allowed = bridge.open(session: session, image: nil, sceneSize: nil, allowsToolImages: true)
    let shown = try await bridge.call(token: allowed, name: "look", arguments: "{}")
    XCTAssertEqual(shown.image, AgentImage(mimeType: "image/jpeg", base64: "AAAA"))
    bridge.close(allowed)

    let kept = bridge.open(session: session, image: nil, sceneSize: nil)
    let hidden = try await bridge.call(token: kept, name: "look", arguments: "{}")
    XCTAssertNil(hidden.image, "send image off: frames stay on the Mac")
    XCTAssertEqual(hidden.text, #"{"ok":true}"#)
    bridge.close(kept)
  }

  func testMock_quotedTextZoomsOnScreenText() {
    let calls = VideoEditorAgentMockProvider.plan(for: #"Zoom vào nút "Deploy" 3x"#)
    XCTAssertEqual(calls.count, 1)
    XCTAssertEqual(calls.first?.name, "add_zoom")
    let args = (try? JSONSerialization.jsonObject(with: Data(calls[0].arguments.utf8))) as? [String: Any]
    XCTAssertEqual(args?["text"] as? String, "deploy")
    XCTAssertEqual(args?["level"] as? Double, 3)
  }

  // MARK: - Live (opt-in)

  /// Real agent CLI through `snapzy mcp`, text fixture: `SNAPZY_LIVE_CLI="opencode|<model>"`
  /// (xcodebuild: `TEST_RUNNER_SNAPZY_LIVE_CLI`). Text models work too: add_zoom(text:) reads the screen in the app.
  func testLiveVisionPrompts() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let spec = environment["SNAPZY_LIVE_CLI"] else {
      throw XCTSkip("Set SNAPZY_LIVE_CLI=\"opencode|<model>\" to run a real agent CLI")
    }
    let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
    let kind = try XCTUnwrap(AnnotateAgentCLIKind(rawValue: parts[0]))
    guard FileManager.default.isExecutableFile(atPath: AgentCLIProvider.helperPath) else {
      throw XCTSkip("No embedded snapzy helper at \(AgentCLIProvider.helperPath)")
    }
    let socket = (NSTemporaryDirectory() as NSString).appendingPathComponent("snapzy-live-vision-\(getpid()).sock")
    setenv("SNAPZY_SOCKET", socket, 1)
    CLIServer.shared.stop()
    defer {
      CLIServer.shared.stop()
      unsetenv("SNAPZY_SOCKET")
    }
    let defaults = UserDefaults(suiteName: "SnapzyTests.VideoVisionLive.\(UUID().uuidString)")!
    if parts.count > 1 { defaults.set(parts[1], forKey: kind.modelDefaultsKey) }

    let center = TextFixture.deployCenter
    let prompts: [(String, (VideoEditorState, String) -> Bool)] = [
      ("Zoom vào nút Deploy khi nó xuất hiện", { state, _ in
        state.zoomSegments.count == 1 && state.zoomSegments.allSatisfy {
          abs($0.startTime - TextFixture.deployAppears) < 0.6 && $0.zoomType == .manual
            && abs($0.zoomCenter.x - center.x) < 0.1 && abs($0.zoomCenter.y - center.y) < 0.1
        }
      }),
      ("When does the word Deploy first show up? Just answer, don't edit.", { state, message in
        state.zoomSegments.isEmpty && state.clips.count == 1 && message.contains("4")
      }),
      ("Cắt bỏ phần trước khi nút Deploy hiện ra", { state, _ in
        abs(TimelineSequence.duration(state.clips) - (TextFixture.duration - TextFixture.deployAppears)) < 0.6
      }),
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
      let (state, _) = try await makeTextToolbox()
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
        let ok = check(state, message)
        passed += ok ? 1 : 0
        let zooms = state.zoomSegments.map {
          String(format: "%.1f-%.1f @(%.2f,%.2f)", $0.startTime, $0.endTime, $0.zoomCenter.x, $0.zoomCenter.y)
        }.joined(separator: ",")
        log("[live-vision] \(ok ? "PASS" : "MISS") \(elapsed) “\(prompt)” → \(count) changes, duration \(String(format: "%.2f", TimelineSequence.duration(state.clips))) zooms[\(zooms)] “\(message)”")
      default:
        errors += 1
        log("[live-vision] ERROR \(elapsed) “\(prompt)” → \(String(describing: controller.notice))")
        controller.stop()
      }
    }
    let total = only == nil ? prompts.count : 1
    log("[live-vision] \(kind.displayName) \(parts.count > 1 ? parts[1] : "default"): \(passed)/\(total) passed, \(errors) errors")
    let report = lines.joined(separator: "\n")
    try? report.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snapzy-live-vision.log"), atomically: true, encoding: .utf8)
    add(XCTAttachment(string: report))
    XCTAssertEqual(errors, 0)
    XCTAssertEqual(AgentBridge.shared.openCount, 0)
  }

  // MARK: - Helpers

  private func makeTextToolbox() async throws -> (VideoEditorState, VideoEditorAgentToolbox) {
    let url = try await TextFixture.makeVideo(in: tempDirectory)
    let state = VideoEditorState(url: url, sessionData: VideoEditorSessionData(sourceSnapshotURL: url, recordingMetadata: nil))
    await state.loadMetadata()
    let toolbox = VideoEditorAgentToolbox(state: state)
    toolbox.beginRun()
    retained.append(state)
    return (state, toolbox)
  }

  private func makeActivityToolbox(transcriber: VideoEditorAgentTranscriber) async throws -> (VideoEditorState, VideoEditorAgentToolbox) {
    let state = try await VideoEditorActivityFixture.makeState(in: tempDirectory)
    let toolbox = VideoEditorAgentToolbox(state: state, analyzer: VideoEditorAgentAnalyzer(transcriber: transcriber))
    toolbox.beginRun()
    retained.append(state)
    return (state, toolbox)
  }

  private func json(_ result: AgentToolResult) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.text.utf8)) as? [String: Any], result.text)
  }
}

// MARK: - Fixtures

/// Builds a transcript engine outside the test class's main-actor isolation, like the production
/// `SpeechTranscriptionEngine.transcribe`, so the closure converts to `Engine` on older toolchains.
private nonisolated func transcriptEngine(
  _ body: @escaping @Sendable (Locale) throws -> [VideoEditorTranscriptWord]
) -> VideoEditorAgentTranscriber.Engine {
  { _, _, locale in try body(locale) }
}

private nonisolated final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  var value: Int { lock.lock(); defer { lock.unlock() }; return count }
  func increment() { lock.lock(); count += 1; lock.unlock() }
}

/// One tool, `look`, that returns a picture.
@MainActor
private final class ImageToolbox: AgentToolbox {
  var surface: AgentSurface { .video }
  var toolSpecs: [AgentToolSpec] { [AgentToolSpec(name: "look", description: "Look.", parametersJSON: "{}")] }
  func isReadOnly(_ name: String) -> Bool { true }
  func execute(name: String, argumentsJSON: String) async -> AgentToolResult {
    AgentToolResult.success([:]).with(image: AgentToolImage(mimeType: "image/jpeg", base64: "AAAA", pixelSize: CGSize(width: 1, height: 1)))
  }
}

@MainActor
private enum TextFixture {
  static let size = CGSize(width: 640, height: 360)
  static let duration: TimeInterval = 10
  static let deployAppears: TimeInterval = 4
  /// Center of the "Deploy" label, top-left normalized.
  static let deployCenter = CGPoint(x: 0.75, y: 0.78)

  static func makeVideo(in directory: URL) async throws -> URL {
    let url = directory.appendingPathComponent("text-\(UUID().uuidString).mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let width = Int(size.width), height = Int(size.height)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
      kCVPixelBufferWidthKey as String: width,
      kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? NSError(domain: "TextFixture", code: 1) }
    writer.startSession(atSourceTime: .zero)

    let frameRate: Int32 = 10
    let without = try frame(showsDeploy: false)
    let with = try frame(showsDeploy: true)
    for index in 0 ..< Int(duration * Double(frameRate)) {
      while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
      let t = Double(index) / Double(frameRate)
      guard adaptor.append(t >= deployAppears ? with : without, withPresentationTime: CMTime(value: Int64(index), timescale: frameRate)) else {
        throw writer.error ?? NSError(domain: "TextFixture", code: 2)
      }
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? NSError(domain: "TextFixture", code: 3) }
    return url
  }

  private static func frame(showsDeploy: Bool) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, nil, &buffer)
    guard let buffer else { throw NSError(domain: "TextFixture", code: 4) }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let context = CGContext(
      data: CVPixelBufferGetBaseAddress(buffer),
      width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else { throw NSError(domain: "TextFixture", code: 5) }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
      .foregroundColor: NSColor.black,
    ]
    // CG origin is bottom left: y = height - top.
    ("Snapzy Demo" as NSString).draw(at: CGPoint(x: 24, y: size.height - 24 - 36), withAttributes: attributes)
    if showsDeploy {
      let label = "Deploy" as NSString
      let labelSize = label.size(withAttributes: attributes)
      let center = CGPoint(x: deployCenter.x * size.width, y: size.height - deployCenter.y * size.height)
      label.draw(at: CGPoint(x: center.x - labelSize.width / 2, y: center.y - labelSize.height / 2), withAttributes: attributes)
    }
    NSGraphicsContext.restoreGraphicsState()
    return buffer
  }
}
