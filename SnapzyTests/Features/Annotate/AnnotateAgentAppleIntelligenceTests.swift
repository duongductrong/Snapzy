//
//  AnnotateAgentAppleIntelligenceTests.swift
//  SnapzyTests
//
//  Annotate AI prompt, phase 3: Apple Intelligence provider. Unit tests cover the
//  prompt budget, error mapping and the coarse draw/edit/canvas tools. The live
//  evaluation of the 10 standard prompts runs only with SNAPZY_LIVE_AI=1
//  (xcodebuild: TEST_RUNNER_SNAPZY_LIVE_AI=1) on a Mac with Apple Intelligence.
//

#if canImport(FoundationModels)
import AppKit
import FoundationModels
import XCTest
@testable import Snapzy

@available(macOS 26.0, *)
@MainActor
final class AnnotateAgentAppleIntelligenceTests: XCTestCase {
  private static var retainedStates: [AnnotateState] = []
  private let imageSize = CGSize(width: 1000, height: 700)

  // MARK: - Fixture: a login form

  private func makeState() throws -> AnnotateState {
    let state = AnnotateState()
    Self.retainedStates.append(state)
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: Int(imageSize.width), height: Int(imageSize.height)))
    state.loadImage(NSImage(cgImage: cgImage, size: imageSize))
    return state
  }

  /// Vision boxes (bottom-left, normalized): title on top, form in the middle, footer at the bottom.
  private func makeAnalysis() -> AnnotateAgentImageAnalysis {
    func block(_ text: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat = 0.04) -> OCRTextBlock {
      let box = CGRect(x: x, y: y, width: w, height: h)
      return OCRTextBlock(text: text, box: box, rowBoxes: [box])
    }
    let blocks = [
      block("Welcome back", 0.35, 0.88, 0.30, 0.06),
      block("Email", 0.30, 0.72, 0.08),
      block("anna.nguyen@example.com", 0.30, 0.66, 0.30),
      block("Password", 0.30, 0.56, 0.12),
      block("Incorrect password. Try again.", 0.30, 0.44, 0.36),
      block("Sign in", 0.44, 0.32, 0.12),
      block("Forgot password?", 0.40, 0.24, 0.20),
      block("Support: +1 555 0100", 0.36, 0.06, 0.28),
    ]
    return AnnotateAgentImageAnalysis(
      textBlocks: AnnotateAgentImageAnalysis.textBlocks(from: blocks, imageSize: imageSize),
      elements: [
        CGRect(x: 260, y: 140, width: 480, height: 420), // login form card
        CGRect(x: 420, y: 455, width: 160, height: 50),  // Sign in button
      ]
    )
  }

  private func makeSession() throws -> (AnnotateState, AnnotateAgentToolbox, AnnotateAgentSession) {
    let state = try makeState()
    let toolbox = AnnotateAgentToolbox(state: state, analysis: makeAnalysis())
    toolbox.beginRun()
    return (state, toolbox, AnnotateAgentSession(toolbox: toolbox, pacingEnabled: false))
  }

  // MARK: - Prompt

  func testPromptCompactsSceneAndKeepsRecentHistory() throws {
    let (_, toolbox, _) = try makeSession()
    let scene = try XCTUnwrap(toolbox.scene())
    let history = (1 ... 5).map { AnnotateAgentTurn(prompt: "prompt \($0)", reply: "reply \($0)") }
    let request = AnnotateAgentRequest(prompt: "Circle Sign in", history: history, sceneJSON: "{}", scene: scene)

    let prompt = AnnotateAgentAppleIntelligenceProvider.prompt(for: request, budget: (texts: 3, length: 5))
    XCTAssertTrue(prompt.contains("\"t3\""))
    XCTAssertFalse(prompt.contains("\"t4\""), "budget keeps only 3 text blocks")
    XCTAssertTrue(prompt.contains("Welco"))
    XCTAssertFalse(prompt.contains("Welcome"), "text is cut to the budget length")
    XCTAssertFalse(prompt.contains("prompt 2"), "only the last 3 turns are sent")
    XCTAssertTrue(prompt.contains("prompt 3") && prompt.contains("reply 5"))
    XCTAssertTrue(prompt.hasSuffix("Request: Circle Sign in"))
  }

  func testCleanReplyStripsQuotesAndMarkdown() {
    XCTAssertEqual(AnnotateAgentAppleIntelligenceProvider.cleanReply("  \"Circled **Sign in**.\"\n"), "Circled **Sign in**.")
    XCTAssertEqual(AnnotateAgentAppleIntelligenceProvider.cleanReply("**Done**"), "Done")
    XCTAssertEqual(AnnotateAgentAppleIntelligenceProvider.cleanReply("Numbered:\n\n1. Email\n2. Sign in"), "Numbered: 1. Email 2. Sign in")
  }

  func testSensitiveTextDetection() {
    XCTAssertEqual(AnnotateAgentSensitiveText.kinds(in: "anna.nguyen@example.com"), [.email])
    XCTAssertEqual(AnnotateAgentSensitiveText.kinds(in: "Support: +1 555 0100"), [.phone])
    XCTAssertEqual(AnnotateAgentSensitiveText.kinds(in: "Gọi 0912 345 678"), [.phone])
    XCTAssertEqual(AnnotateAgentSensitiveText.kinds(in: "Server 192.168.1.20"), [.ip])
    XCTAssertEqual(AnnotateAgentSensitiveText.kinds(in: "4242 4242 4242 4242"), [.card])
    XCTAssertEqual(AnnotateAgentSensitiveText.kinds(in: "https://snapzy.app/docs"), [.link])
    XCTAssertTrue(AnnotateAgentSensitiveText.kinds(in: "Sign in").isEmpty)
    XCTAssertTrue(AnnotateAgentSensitiveText.kinds(in: "Version 2.2 · 2026").isEmpty)
  }

  func testBlurSensitiveBlursEmailAndPhone() async throws {
    let (state, _, session) = try makeSession()
    let tool = AppleBlurSensitiveTool(bridge: AppleToolBridge(session: session, counter: AnnotateAgentChangeCounter()))
    _ = try await tool.call(arguments: AppleBlurSensitiveTool.Arguments(GeneratedContent(properties: ["kinds": [String]()])))
    XCTAssertEqual(state.annotations.filter { $0.type.agentTypeName == "blur" }.count, 2)
  }

  // MARK: - Errors

  func testErrorsMapToProviderMessages() {
    let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
    func message(_ error: Error) -> String? {
      if case AnnotateAgentProviderError.failed(let text) = AnnotateAgentAppleIntelligenceProvider.map(error) { return text }
      return nil
    }
    XCTAssertEqual(message(LanguageModelSession.GenerationError.guardrailViolation(context)), L10n.AnnotateAI.appleRefused)
    XCTAssertEqual(message(LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(context)), L10n.AnnotateAI.appleUnsupportedLanguage)
    XCTAssertEqual(message(LanguageModelSession.GenerationError.rateLimited(context)), L10n.AnnotateAI.appleBusy)
    XCTAssertEqual(message(LanguageModelSession.GenerationError.exceededContextWindowSize(context)), L10n.AnnotateAI.appleTooLong)
    XCTAssertTrue(AnnotateAgentAppleIntelligenceProvider.isContextOverflow(LanguageModelSession.GenerationError.exceededContextWindowSize(context)))
    XCTAssertTrue(AnnotateAgentAppleIntelligenceProvider.map(CancellationError()) is CancellationError)
  }

  // MARK: - Tools

  func testDrawToolMapsKindsToAnnotations() async throws {
    let (state, _, session) = try makeSession()
    let bridge = AppleToolBridge(session: session, counter: AnnotateAgentChangeCounter())
    let draw = AppleDrawTool(bridge: bridge)
    func run(_ properties: KeyValuePairs<String, any ConvertibleToGeneratedContent>) async throws -> String {
      try await draw.call(arguments: AppleDrawTool.Arguments(GeneratedContent(properties: properties)))
    }

    _ = try await run(["kind": "box", "target": "Sign in", "color": "red"])
    _ = try await run(["kind": "arrow", "target": "t5"])
    _ = try await run(["kind": "blur", "target": "anna.nguyen@example.com", "color": ""])
    _ = try await run(["kind": "text", "target": "t5", "text": "Error here"])
    _ = try await run(["kind": "counter", "target": "Email"])
    let bad = try await run(["kind": "text", "target": "t5"])

    XCTAssertTrue(bad.contains("\"ok\":false"))
    let types = state.annotations.map(\.type.agentTypeName)
    XCTAssertEqual(types.filter { $0 == "box" }.count, 1)
    XCTAssertEqual(types.filter { $0 == "arrow" }.count, 1)
    XCTAssertEqual(types.filter { $0 == "blur" }.count, 1)
    XCTAssertEqual(types.filter { $0 == "text" }.count, 1)
    XCTAssertEqual(types.filter { $0 == "counter" }.count, 1)
    XCTAssertEqual(bridge.counter.value, 5)
  }

  func testEditToolRecolorsAndDeletesAll() async throws {
    let (state, toolbox, session) = try makeSession()
    _ = toolbox.execute(name: "add_arrow", argumentsJSON: #"{"to":"t6","color":"red"}"#)
    _ = toolbox.execute(name: "add_arrow", argumentsJSON: #"{"to":"t2","color":"red"}"#)
    let edit = AppleEditTool(bridge: AppleToolBridge(session: session, counter: AnnotateAgentChangeCounter()))

    _ = try await edit.call(arguments: AppleEditTool.Arguments(GeneratedContent(properties: [
      "ids": ["all"], "action": "recolor", "value": "blue",
    ])))
    XCTAssertEqual(state.annotations.map { AnnotateAgentColor.describe($0.properties.strokeColor) }, ["blue", "blue"])

    _ = try await edit.call(arguments: AppleEditTool.Arguments(GeneratedContent(properties: [
      "ids": ["all"], "action": "delete",
    ])))
    XCTAssertTrue(state.annotations.isEmpty)
  }

  func testCanvasToolSetsOnlyGivenValues() async throws {
    let (state, _, session) = try makeSession()
    let canvas = AppleCanvasTool(bridge: AppleToolBridge(session: session, counter: AnnotateAgentChangeCounter()))
    let shadowBefore = state.shadowIntensity

    let result = try await canvas.call(arguments: AppleCanvasTool.Arguments(GeneratedContent(properties: [
      "padding": 48, "cornerRadius": 12,
    ])))
    XCTAssertFalse(result.contains("\"ok\":false"), result)
    XCTAssertEqual(state.padding, 48)
    XCTAssertEqual(state.cornerRadius, 12)
    XCTAssertEqual(state.shadowIntensity, shadowBefore)

    let empty = try await canvas.call(arguments: AppleCanvasTool.Arguments(GeneratedContent(properties: [:])))
    XCTAssertTrue(empty.contains("\"ok\":false"))
  }

  // MARK: - Live evaluation (opt-in)

  /// The plan's 10 standard prompts against the real on-device model. Prints one line
  /// per prompt; fails only if the model errors out on most of them.
  func testLiveStandardPrompts() async throws {
    guard ProcessInfo.processInfo.environment["SNAPZY_LIVE_AI"] == "1" else {
      throw XCTSkip("Set SNAPZY_LIVE_AI=1 to call Apple Intelligence")
    }
    guard SystemLanguageModel.default.availability == .available else {
      throw XCTSkip("Apple Intelligence is not available on this Mac")
    }
    let prompts: [(String, (AnnotateState) -> Bool)] = [
      ("Khoanh đỏ nút Sign in", { $0.annotations.dropFirst(2).contains { ["box", "filled_box", "oval"].contains($0.type.agentTypeName) } }),
      ("Blur tất cả email và số điện thoại", { $0.annotations.filter { $0.type.agentTypeName == "blur" }.count >= 2 }),
      ("Đánh số các bước: Email, Password, Sign in", { $0.annotations.filter { $0.type.agentTypeName == "counter" }.count >= 3 }),
      ("Thêm callout 'Lỗi ở đây' chỉ vào thông báo lỗi", { $0.annotations.dropFirst(2).contains { $0.type.agentTypeName == "text" } }),
      ("Highlight vàng tiêu đề", { $0.annotations.contains { $0.type.agentTypeName == "highlight" } }),
      ("Nền gradient, padding 48, bo góc", { $0.padding >= 20 && $0.cornerRadius > 0 }),
      ("Đổi mọi mũi tên thành màu xanh", { state in
        state.annotations.filter { $0.type.agentTypeName == "arrow" }
          .allSatisfy { ["blue", "green"].contains(AnnotateAgentColor.describe($0.properties.strokeColor)) }
      }),
      ("Xoá hết annotation", { $0.annotations.isEmpty }),
      ("Circle the Sign in button in red", { $0.annotations.dropFirst(2).contains { ["box", "filled_box", "oval"].contains($0.type.agentTypeName) } }),
      ("Spotlight vào form đăng nhập", { $0.annotations.contains { $0.type.agentTypeName == "spotlight" } }),
    ]

    var passed = 0
    var errors = 0
    var lines: [String] = []
    func log(_ line: String) {
      print(line)
      lines.append(line)
    }
    for (prompt, check) in prompts {
      let (state, toolbox, _) = try makeSession()
      var calls: [String] = []
      let session = AnnotateAgentSession(toolbox: toolbox, pacingEnabled: false, onToolStart: { calls.append($0?.rawValue ?? "?") })
      // Prompts 7–8 need something to edit.
      _ = toolbox.execute(name: "add_arrow", argumentsJSON: #"{"to":"t6","color":"red"}"#)
      _ = toolbox.execute(name: "add_box", argumentsJSON: #"{"target":"t5","color":"red"}"#)
      let request = AnnotateAgentRequest(prompt: prompt, history: [], sceneJSON: "{}", scene: toolbox.scene())
      let started = Date()
      do {
        let reply = try await AnnotateAgentAppleIntelligenceProvider().run(request, session: session)
        let ok = check(state)
        passed += ok ? 1 : 0
        let kinds = state.annotations.map(\.type.agentTypeName).joined(separator: ",")
        log("[live-ai] \(ok ? "PASS" : "MISS") \(String(format: "%.1fs", Date().timeIntervalSince(started))) “\(prompt)” → [\(kinds)] calls: \(calls.joined(separator: ",")) “\(reply)”")
      } catch {
        errors += 1
        log("[live-ai] ERROR “\(prompt)” → \(error)")
      }
      _ = toolbox.finishRun()
    }
    log("[live-ai] \(passed)/\(prompts.count) passed, \(errors) errors")
    let report = lines.joined(separator: "\n")
    let logURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snapzy-live-ai.log")
    try? report.write(to: logURL, atomically: true, encoding: .utf8)
    add(XCTAttachment(string: report))
    XCTAssertLessThan(errors, prompts.count / 2)
  }
}
#endif
