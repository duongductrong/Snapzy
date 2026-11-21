//
//  AnnotateAgentEndpointProviderTests.swift
//  SnapzyTests
//
//  Annotate AI prompt, phase 4: custom OpenAI-compatible endpoint provider.
//  Network is a scripted `MockURLSession`: tool-calling loop, plan-mode fallback
//  and repair, image fallback, capability memory, error mapping, response/plan
//  parsing, provider selection and the one-time consent before sending off the Mac.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class AnnotateAgentEndpointProviderTests: XCTestCase {
  private static var retained: [AnyObject] = []
  private let imageSize = CGSize(width: 1000, height: 700)
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUp() {
    super.setUp()
    suiteName = "AnnotateAgentEndpointProviderTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    super.tearDown()
  }

  // MARK: - Scripted network

  /// Answers requests in order; records the decoded JSON bodies.
  private final class Script: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(Int, String)]
    private var _bodies: [[String: Any]] = []

    init(_ responses: [(Int, String)]) {
      self.responses = responses
    }

    var bodies: [[String: Any]] {
      lock.lock(); defer { lock.unlock() }
      return _bodies
    }

    func respond(_ request: URLRequest) throws -> (Data, URLResponse) {
      lock.lock(); defer { lock.unlock() }
      let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
      _bodies.append(body)
      guard !responses.isEmpty else { throw URLError(.badServerResponse) }
      let (status, text) = responses.removeFirst()
      return MockURLSession.makeResponse(statusCode: status, data: Data(text.utf8))
    }
  }

  private static func toolCallsResponse(_ calls: [(id: String, name: String, arguments: String)]) -> String {
    let toolCalls = calls.map { call -> [String: Any] in
      ["id": call.id, "type": "function", "function": ["name": call.name, "arguments": call.arguments]]
    }
    return json(["choices": [["message": ["role": "assistant", "content": NSNull(), "tool_calls": toolCalls]]]])
  }

  private static func textResponse(_ text: String) -> String {
    json(["choices": [["message": ["role": "assistant", "content": text]]]])
  }

  private static func json(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
  }

  // MARK: - Fixture

  private let model = CustomOCRModel(name: "Local LLM", baseURL: "http://localhost:11434/v1", modelIdentifier: "qwen3")

  private func makeState() throws -> AnnotateState {
    let state = AnnotateState()
    Self.retained.append(state)
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: Int(imageSize.width), height: Int(imageSize.height)))
    state.loadImage(NSImage(cgImage: cgImage, size: imageSize))
    return state
  }

  private func makeAnalysis() -> AnnotateAgentImageAnalysis {
    func block(_ text: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat) -> OCRTextBlock {
      let box = CGRect(x: x, y: y, width: w, height: 0.04)
      return OCRTextBlock(text: text, box: box, rowBoxes: [box])
    }
    let blocks = [
      block("Welcome back", 0.35, 0.88, 0.30),
      block("anna@example.com", 0.30, 0.66, 0.30),
      block("Sign in", 0.44, 0.32, 0.12),
    ]
    return AnnotateAgentImageAnalysis(
      textBlocks: AnnotateAgentImageAnalysis.textBlocks(from: blocks, imageSize: imageSize),
      elements: []
    )
  }

  private func makeRun(
    _ responses: [(Int, String)],
    withImage: Bool = false
  ) throws -> (AnnotateState, AnnotateAgentEndpointProvider, AnnotateAgentSession, AnnotateAgentRequest, Script) {
    let state = try makeState()
    let toolbox = AnnotateAgentToolbox(state: state, analysis: makeAnalysis())
    Self.retained.append(toolbox)
    toolbox.beginRun()
    let session = AnnotateAgentSession(toolbox: toolbox, pacingEnabled: false)
    let script = Script(responses)
    let provider = AnnotateAgentEndpointProvider(
      model: model,
      keychainStore: FakeOCRKeychainStore(),
      session: MockURLSession { try script.respond($0) },
      defaults: defaults
    )
    let request = AnnotateAgentRequest(
      prompt: "Circle Sign in",
      history: [AnnotateAgentTurn(prompt: "Blur the email", reply: "Blurred it.")],
      sceneJSON: toolbox.execute(name: "get_scene", argumentsJSON: "{}").text,
      scene: toolbox.scene(),
      image: withImage ? state.effectiveSourceImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) : nil
    )
    return (state, provider, session, request, script)
  }

  private func messages(_ body: [String: Any]) -> [[String: Any]] {
    body["messages"] as? [[String: Any]] ?? []
  }

  // MARK: - Tools mode

  func testToolCallingLoopDrawsAndReturnsReply() async throws {
    let (state, provider, session, request, script) = try makeRun([
      (200, Self.toolCallsResponse([("call_1", "add_box", #"{"target":{"text":"Sign in"},"color":"red"}"#)])),
      (200, Self.textResponse("Circled **Sign in** in red.\n")),
    ])

    let reply = try await provider.run(request, session: session)

    XCTAssertEqual(reply, "Circled **Sign in** in red.")
    XCTAssertEqual(state.annotations.map(\.type.agentTypeName), ["box"])
    let first = script.bodies[0]
    XCTAssertEqual(first["model"] as? String, "qwen3")
    XCTAssertEqual((first["tools"] as? [[String: Any]])?.count, AnnotateAgentToolCatalog.all.count)
    let firstMessages = messages(first)
    XCTAssertEqual(firstMessages.map { $0["role"] as? String }, ["system", "user", "assistant", "user"], "history goes before the request")
    XCTAssertTrue((firstMessages.last?["content"] as? String)?.hasSuffix("Request: Circle Sign in") ?? false)

    let second = messages(script.bodies[1])
    let assistant = try XCTUnwrap(second.dropLast().last)
    XCTAssertEqual((assistant["tool_calls"] as? [[String: Any]])?.first?["id"] as? String, "call_1")
    let tool = try XCTUnwrap(second.last)
    XCTAssertEqual(tool["role"] as? String, "tool")
    XCTAssertEqual(tool["tool_call_id"] as? String, "call_1")
    XCTAssertTrue((tool["content"] as? String)?.contains("\"ok\":true") ?? false)
    XCTAssertEqual(provider.capabilities.supportsTools, true)
  }

  func testToolErrorsGoBackToTheModel() async throws {
    let (state, provider, session, request, script) = try makeRun([
      (200, Self.toolCallsResponse([("c1", "add_box", #"{"target":"t99"}"#)])),
      (200, Self.toolCallsResponse([("c2", "add_box", #"{"target":"t3"}"#)])),
      (200, Self.textResponse("Done.")),
    ])

    _ = try await provider.run(request, session: session)

    XCTAssertEqual(state.annotations.count, 1)
    let errorMessage = try XCTUnwrap(messages(script.bodies[1]).last?["content"] as? String)
    XCTAssertTrue(errorMessage.contains("\"ok\":false"))
  }

  func testRoundLimitStopsARunawayModel() async throws {
    let looping = (0..<AnnotateAgentEndpointProvider.maximumRounds + 3).map { index in
      (200, Self.toolCallsResponse([("c\(index)", "find_text", #"{"query":"Sign"}"#)]))
    }
    let (_, provider, session, request, script) = try makeRun(looping)

    _ = try await provider.run(request, session: session)

    XCTAssertEqual(script.bodies.count, AnnotateAgentEndpointProvider.maximumRounds)
  }

  // MARK: - Plan mode

  func testEndpointWithoutToolsFallsBackToPlanModeAndRemembers() async throws {
    let plan = #"Sure!\n```json\n{"ops":[{"tool":"add_counter","args":{"target":"t2"}},{"tool":"add_counter","args":{"target":"t3"}}],"reply":"Numbered 2 steps."}\n```"#
    let (state, provider, session, request, script) = try makeRun([
      (400, #"{"error":{"message":"registry.ollama.ai/library/gemma3 does not support tools"}}"#),
      (200, Self.textResponse(plan)),
    ])

    let reply = try await provider.run(request, session: session)

    XCTAssertEqual(reply, "Numbered 2 steps.")
    XCTAssertEqual(state.annotations.map(\.type.agentTypeName), ["counter", "counter"])
    XCTAssertNil(script.bodies[1]["tools"])
    XCTAssertTrue((messages(script.bodies[1]).first?["content"] as? String)?.contains("\"ops\"") ?? false)
    XCTAssertEqual(provider.capabilities.supportsTools, false)

    // Next run goes straight to plan mode.
    let (_, _, session2, request2, _) = try makeRun([])
    let script2 = Script([(200, Self.textResponse(#"{"ops":[],"reply":"Nothing to do."}"#))])
    let provider2 = AnnotateAgentEndpointProvider(
      model: model, keychainStore: FakeOCRKeychainStore(), session: MockURLSession { try script2.respond($0) }, defaults: defaults
    )
    let reply2 = try await provider2.run(request2, session: session2)
    XCTAssertEqual(reply2, "Nothing to do.")
    XCTAssertEqual(script2.bodies.count, 1)
    XCTAssertNil(script2.bodies[0]["tools"])
  }

  func testPlanModeRepairsFailedOpsOnce() async throws {
    AnnotateAgentEndpointCapabilityStore(defaults: defaults).save(.init(supportsTools: false), for: model)
    let (state, provider, session, request, script) = try makeRun([
      (200, Self.textResponse(#"{"ops":[{"tool":"add_box","args":{"target":"t3"}},{"tool":"add_blur","args":{"target":"nope"}}],"reply":"Boxed."}"#)),
      (200, Self.textResponse(#"{"ops":[{"tool":"add_blur","args":{"target":"t2"}}],"reply":"Boxed Sign in and blurred the email."}"#)),
    ])

    let reply = try await provider.run(request, session: session)

    XCTAssertEqual(reply, "Boxed Sign in and blurred the email.")
    XCTAssertEqual(state.annotations.map(\.type.agentTypeName), ["box", "blur"])
    let repairPrompt = try XCTUnwrap(messages(script.bodies[1]).last?["content"] as? String)
    XCTAssertTrue(repairPrompt.contains("op 2 add_blur"))
    XCTAssertFalse(repairPrompt.contains("op 1"))
  }

  func testPlanModeAsksOnceForJSONThenGivesUp() async throws {
    AnnotateAgentEndpointCapabilityStore(defaults: defaults).save(.init(supportsTools: false), for: model)
    let (_, provider, session, request, script) = try makeRun([
      (200, Self.textResponse("")),
      (200, Self.textResponse("")),
    ])

    do {
      _ = try await provider.run(request, session: session)
      XCTFail("expected failure")
    } catch {
      XCTAssertEqual(error as? AnnotateAgentProviderError, .failed(L10n.AnnotateAI.invalidReply))
    }
    XCTAssertEqual(script.bodies.count, 2)
  }

  // MARK: - Vision

  func testImageIsSentAndDroppedWhenRejected() async throws {
    let (_, provider, session, request, script) = try makeRun([
      (400, #"{"error":{"message":"Invalid content type. image_url is only supported by certain models."}}"#),
      (200, Self.textResponse("Nothing to change.")),
    ], withImage: true)

    _ = try await provider.run(request, session: session)

    let first = try XCTUnwrap(messages(script.bodies[0]).last?["content"] as? [[String: Any]])
    XCTAssertEqual(first.map { $0["type"] as? String }, ["text", "image_url"])
    let url = try XCTUnwrap((first[1]["image_url"] as? [String: Any])?["url"] as? String)
    XCTAssertTrue(url.hasPrefix("data:image/jpeg;base64,"))
    XCTAssertTrue((first[0]["text"] as? String)?.contains("1000×700 pixels") ?? false)

    XCTAssertTrue(messages(script.bodies[1]).last?["content"] is String, "retry is text only")
    XCTAssertEqual(provider.capabilities.supportsVision, false)
  }

  func testImageIsNotSentWhenTurnedOff() async throws {
    defaults.set(false, forKey: AnnotateAgentEndpointProvider.sendImageDefaultsKey)
    let (_, provider, session, request, script) = try makeRun([(200, Self.textResponse("Ok."))], withImage: true)

    _ = try await provider.run(request, session: session)

    XCTAssertTrue(messages(script.bodies[0]).last?["content"] is String)
  }

  func testLargeImageIsDownscaledWithScaleNote() throws {
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: 3136, height: 1000))
    let image = try XCTUnwrap(AnnotateAgentEndpointImage.encode(cgImage, sceneSize: CGSize(width: 3136, height: 1000)))
    XCTAssertEqual(image.pixelSize.width, 1568)
    XCTAssertEqual(image.pixelSize.height, 500)
    XCTAssertEqual(image.scale, 0.5, accuracy: 0.0001)

    // A Retina image is drawn at scene units (points), not pixels.
    let retina = try XCTUnwrap(AnnotateAgentEndpointImage.encode(cgImage, sceneSize: CGSize(width: 1568, height: 500)))
    XCTAssertEqual(retina.pixelSize.width, 1568)
    XCTAssertEqual(retina.scale, 1)
  }

  // MARK: - Errors

  func testHTTPErrorsBecomeReadableMessages() async throws {
    let (_, provider, session, request, _) = try makeRun([(401, "nope")])
    do {
      _ = try await provider.run(request, session: session)
      XCTFail("expected failure")
    } catch {
      XCTAssertEqual(error as? AnnotateAgentProviderError, .failed(L10n.OCR.remoteErrorUnauthorized))
    }
  }

  func testRejectionClassifier() {
    XCTAssertEqual(AnnotateAgentEndpointProvider.rejection(status: 400, body: "model does not support tools"), .tools)
    XCTAssertEqual(AnnotateAgentEndpointProvider.rejection(status: 422, body: "Unknown field: functions"), .tools)
    XCTAssertEqual(AnnotateAgentEndpointProvider.rejection(status: 400, body: "This model doesn't support vision"), .images)
    XCTAssertNil(AnnotateAgentEndpointProvider.rejection(status: 429, body: "tool rate limit"))
    XCTAssertNil(AnnotateAgentEndpointProvider.rejection(status: 400, body: "context length exceeded"))
    XCTAssertEqual(AnnotateAgentEndpointProvider.rejection(status: 400, body: "llama3.2-vision does not support tools"), .tools)
    XCTAssertEqual(AnnotateAgentEndpointProvider.rejection(status: 400, body: "Unsupported value: 'temperature' does not support 0.2"), .temperature)
    XCTAssertNil(AnnotateAgentEndpointProvider.rejection(status: 500, body: "image tokens exceed the context window"))
  }

  func testToolErrorOnALaterRoundDoesNotSwitchToPlanMode() async throws {
    let (_, provider, session, request, _) = try makeRun([
      (200, Self.toolCallsResponse([("c1", "find_text", #"{"query":"Sign"}"#)])),
      (400, #"{"error":"invalid tool_call_id"}"#),
    ])
    do {
      _ = try await provider.run(request, session: session)
      XCTFail("expected failure")
    } catch {
      XCTAssertNotNil(error as? AnnotateAgentProviderError)
    }
    XCTAssertNotEqual(provider.capabilities.supportsTools, false)
  }

  func testTemperatureIsDroppedWhenRejected() async throws {
    let (_, provider, session, request, script) = try makeRun([
      (400, #"{"error":{"message":"Unsupported value: 'temperature' does not support 0.2 with this model."}}"#),
      (200, Self.textResponse("Ok.")),
    ])
    _ = try await provider.run(request, session: session)
    XCTAssertNotNil(script.bodies[0]["temperature"])
    XCTAssertNil(script.bodies[1]["temperature"])
  }

  func testPlanWrittenAsTextInToolsModeIsApplied() async throws {
    let (state, provider, session, request, script) = try makeRun([
      (200, Self.textResponse(#"{"ops":[{"tool":"add_highlight","args":{"target":"t1"}}],"reply":"Highlighted the title."}"#)),
    ])
    let reply = try await provider.run(request, session: session)
    XCTAssertEqual(reply, "Highlighted the title.")
    XCTAssertEqual(state.annotations.map(\.type.agentTypeName), ["highlight"])
    XCTAssertEqual(script.bodies.count, 1)
    XCTAssertNil(provider.capabilities.supportsTools, "a text plan says nothing about tool calling")
  }

  func testEditingTheEndpointForgetsCapabilitiesAndAsksConsentAgain() {
    let store = AnnotateAgentEndpointCapabilityStore(defaults: defaults)
    store.save(.init(supportsTools: false, supportsVision: true), for: model)
    XCTAssertEqual(store.capabilities(for: model).supportsTools, false)
    var edited = model
    edited.modelIdentifier = "qwen3-vl"
    XCTAssertEqual(store.capabilities(for: edited), .init())

    var moved = model
    moved.baseURL = "https://api.example.com/v1"
    let original = AnnotateAgentEndpointProvider(model: model, defaults: defaults).remoteDestination
    let other = AnnotateAgentEndpointProvider(model: moved, defaults: defaults).remoteDestination
    XCTAssertNotEqual(original?.id, other?.id)
    XCTAssertEqual(other?.host, "api.example.com")
  }

  // MARK: - Parsing

  func testMessageParsingAcceptsObjectArgumentsAndMissingIDs() throws {
    let data = Data(Self.json(["choices": [["message": [
      "content": [["type": "text", "text": "Working"]],
      "tool_calls": [["function": ["name": "add_box", "arguments": ["target": "t1"]]]],
    ]]]]).utf8)
    let message = try XCTUnwrap(AnnotateAgentEndpointMessage.parse(data))
    XCTAssertEqual(message.text, "Working")
    XCTAssertEqual(message.toolCalls, [.init(id: "call_1", name: "add_box", arguments: #"{"target":"t1"}"#)])
    XCTAssertNil(AnnotateAgentEndpointMessage.parse(Data("{}".utf8)))
  }

  func testPlanParsingVariants() {
    XCTAssertEqual(
      AnnotateAgentEndpointPlan.parse(#"[{"name":"add_box","arguments":{"target":"t1"}},{"tool":"add_blur","args":"{\"target\":\"t2\"}"}]"#)?.ops,
      [.init(tool: "add_box", arguments: #"{"target":"t1"}"#), .init(tool: "add_blur", arguments: #"{"target":"t2"}"#)]
    )
    XCTAssertEqual(AnnotateAgentEndpointPlan.parse(#"Here: {"ops": [], "summary": "Nothing."} hope that helps"#)?.reply, "Nothing.")
    XCTAssertNil(AnnotateAgentEndpointPlan.parse("I circled it."))
    XCTAssertNil(AnnotateAgentEndpointPlan.parse(#"{"answer": 1}"#))
  }

  // MARK: - Selection

  func testSelectionPersistsAndResolvesEndpoint() {
    for selection in [AnnotateAgentProviderSelection.automatic, .appleIntelligence, .endpoint(model.id)] {
      XCTAssertEqual(AnnotateAgentProviderSelection(persistedValue: selection.persistedValue), selection)
    }
    XCTAssertEqual(AnnotateAgentProviderSelection(persistedValue: "endpoint:garbage"), .automatic)
    XCTAssertEqual(AnnotateAgentProviderSelection(persistedValue: nil), .automatic)

    defaults.set(false, forKey: AnnotateAgentProviderResolver.mockProviderDefaultsKey)
    AnnotateAgentProviderResolver.setSelection(.endpoint(model.id), defaults: defaults)
    let provider = AnnotateAgentProviderResolver.resolve(defaults: defaults, endpoints: [model])
    XCTAssertEqual((provider as? AnnotateAgentEndpointProvider)?.model.id, model.id)
    XCTAssertEqual(provider?.remoteDestination?.host, "localhost")

    // A removed endpoint does not leave the prompt pointing at nothing.
    let fallback = AnnotateAgentProviderResolver.resolve(defaults: defaults, endpoints: [])
    XCTAssertFalse(fallback is AnnotateAgentEndpointProvider)
  }

  // MARK: - Consent

  private final class RemoteProvider: AnnotateAgentProvider {
    let displayName = "Remote"
    let symbolName = "network"
    let remoteDestination: AnnotateAgentRemoteDestination? = .init(id: "endpoint:test", name: "Remote", host: "example.com")
    private(set) var requests: [AnnotateAgentRequest] = []

    func run(_ request: AnnotateAgentRequest, session: AnnotateAgentSession) async throws -> String {
      requests.append(request)
      return "Ok."
    }
  }

  func testRemoteProviderAsksOnceBeforeSending() async throws {
    let state = try makeState()
    let provider = RemoteProvider()
    var answers = [false, true]
    var asked: [String] = []
    let controller = AnnotateAgentController(
      state: state,
      pacingEnabled: false,
      defaults: defaults,
      resolveProvider: { provider },
      confirmRemoteUse: { destination in
        asked.append(destination.id)
        return answers.removeFirst()
      }
    )
    Self.retained.append(controller)

    controller.draft = "Box the title"
    controller.submit()
    try await waitUntil { !asked.isEmpty && controller.canSend }
    XCTAssertTrue(provider.requests.isEmpty, "declined: nothing is sent")
    XCTAssertEqual(controller.draft, "Box the title", "declined: the draft stays")

    controller.submit()
    try await waitUntil { !provider.requests.isEmpty && !controller.isRunning }
    XCTAssertEqual(asked.count, 2)
    XCTAssertNotNil(provider.requests.first?.image, "remote providers get the screenshot")

    controller.draft = "Again"
    controller.submit()
    try await waitUntil { provider.requests.count == 2 && !controller.isRunning }
    XCTAssertEqual(asked.count, 2, "consent is remembered")
  }

  // MARK: - Live evaluation (opt-in)

  /// The plan's 10 standard prompts against a real endpoint (e.g. LM Studio):
  /// `SNAPZY_LIVE_ENDPOINT="http://localhost:1234/v1|google/gemma-4-e2b"` and optionally
  /// `SNAPZY_LIVE_ENDPOINT_MODE=plan` to force plan mode (xcodebuild: prefix `TEST_RUNNER_`).
  func testLiveStandardPrompts() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let spec = environment["SNAPZY_LIVE_ENDPOINT"], case let parts = spec.split(separator: "|"), parts.count == 2 else {
      throw XCTSkip("Set SNAPZY_LIVE_ENDPOINT=\"<base url>|<model>\" to call a real endpoint")
    }
    let liveModel = CustomOCRModel(name: "Live", baseURL: String(parts[0]), modelIdentifier: String(parts[1]))
    let forcePlan = environment["SNAPZY_LIVE_ENDPOINT_MODE"] == "plan"
    let loginAnalysis: AnnotateAgentImageAnalysis = {
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
        elements: [CGRect(x: 260, y: 140, width: 480, height: 420), CGRect(x: 420, y: 455, width: 160, height: 50)]
      )
    }()
    let shapes = ["box", "filled_box", "oval"]
    let prompts: [(String, (AnnotateState) -> Bool)] = [
      ("Khoanh đỏ nút Sign in", { $0.annotations.dropFirst(2).contains { shapes.contains($0.type.agentTypeName) } }),
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
      ("Circle the Sign in button in red", { $0.annotations.dropFirst(2).contains { shapes.contains($0.type.agentTypeName) } }),
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
      let state = try makeState()
      let toolbox = AnnotateAgentToolbox(state: state, analysis: loginAnalysis)
      Self.retained.append(toolbox)
      toolbox.beginRun()
      var calls: [String] = []
      let session = AnnotateAgentSession(toolbox: toolbox, pacingEnabled: false, onToolStart: { calls.append($0?.rawValue ?? "?") })
      // Prompts 7–8 need something to edit.
      _ = toolbox.execute(name: "add_arrow", argumentsJSON: #"{"to":"t6","color":"red"}"#)
      _ = toolbox.execute(name: "add_box", argumentsJSON: #"{"target":"t5","color":"red"}"#)
      if forcePlan {
        AnnotateAgentEndpointCapabilityStore(defaults: defaults).save(.init(supportsTools: false), for: liveModel)
      }
      let provider = AnnotateAgentEndpointProvider(model: liveModel, keychainStore: FakeOCRKeychainStore(), defaults: defaults, timeout: 180)
      let request = AnnotateAgentRequest(
        prompt: prompt,
        history: [],
        sceneJSON: toolbox.execute(name: "get_scene", argumentsJSON: "{}").text,
        scene: toolbox.scene()
      )
      let started = Date()
      do {
        let reply = try await provider.run(request, session: session)
        let ok = check(state)
        passed += ok ? 1 : 0
        let kinds = state.annotations.map(\.type.agentTypeName).joined(separator: ",")
        log("[live-endpoint] \(ok ? "PASS" : "MISS") \(String(format: "%.1fs", Date().timeIntervalSince(started))) “\(prompt)” → [\(kinds)] calls: \(calls.joined(separator: ",")) “\(reply)”")
      } catch {
        errors += 1
        log("[live-endpoint] ERROR “\(prompt)” → \(error)")
      }
      _ = toolbox.finishRun()
    }
    let mode = forcePlan ? "plan" : (AnnotateAgentEndpointCapabilityStore(defaults: defaults).capabilities(for: liveModel).supportsTools == false ? "plan (auto)" : "tools")
    log("[live-endpoint] \(liveModel.modelIdentifier) mode=\(mode): \(passed)/\(prompts.count) passed, \(errors) errors")
    let report = lines.joined(separator: "\n")
    let logURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snapzy-live-endpoint.log")
    try? report.write(to: logURL, atomically: true, encoding: .utf8)
    add(XCTAttachment(string: report))
    XCTAssertLessThan(errors, prompts.count / 2)
  }

  private func waitUntil(timeout: TimeInterval = 10, _ condition: @MainActor () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
      guard Date() < deadline else { return XCTFail("timed out") }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
  }
}
