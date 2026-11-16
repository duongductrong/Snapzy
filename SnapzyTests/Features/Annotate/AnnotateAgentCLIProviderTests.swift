//
//  AnnotateAgentCLIProviderTests.swift
//  SnapzyTests
//
//  Annotate AI prompt, phase 5: agent CLIs (Claude Code, Codex, OpenCode) over
//  `snapzy mcp`. Adapters are checked against recorded output (no agent is
//  called); the bridge's session tokens, the process group Stop, selection, and
//  an opt-in live run (`SNAPZY_LIVE_CLI=opencode|<model>`) against a real CLI.
//

import AppKit
import SnapzyCLIProtocol
import XCTest
@testable import Snapzy

@MainActor
final class AnnotateAgentCLIProviderTests: XCTestCase {
  private static var retained: [AnyObject] = []
  private let imageSize = CGSize(width: 1000, height: 700)

  private let mcp = AnnotateAgentMCPLaunch(helperPath: "/Apps/Snapzy.app/Contents/Helpers/snapzy", token: "tok123")

  private func input(resume: String? = nil, model: String? = nil, image: String? = nil) -> AnnotateAgentCLIRunInput {
    AnnotateAgentCLIRunInput(
      prompt: "Scene…\n\nRequest: Circle Sign in",
      systemPrompt: "You edit a screenshot.",
      resumeSessionID: resume,
      model: model,
      mcp: mcp,
      directory: "/tmp/run",
      runID: "R1",
      imagePath: image
    )
  }

  private func value(after flag: String, in arguments: [String]) -> String? {
    arguments.firstIndex(of: flag).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
  }

  // MARK: - Invocations

  func testClaudeCodeGetsOnlySnapzyAndNoBuiltInTools() throws {
    let invocation = AnnotateAgentCLIAdapter.invocation(for: .claudeCode, input(resume: "sess-1", model: "haiku"))
    let arguments = invocation.arguments
    XCTAssertEqual(arguments.first, "-p")
    XCTAssertEqual(value(after: "--output-format", in: arguments), "stream-json")
    XCTAssertTrue(arguments.contains("--strict-mcp-config"))
    XCTAssertEqual(value(after: "--tools", in: arguments), "")
    XCTAssertEqual(value(after: "--allowedTools", in: arguments), "mcp__snapzy")
    XCTAssertEqual(value(after: "--permission-mode", in: arguments), "dontAsk")
    XCTAssertEqual(value(after: "--resume", in: arguments), "sess-1")
    XCTAssertEqual(value(after: "--model", in: arguments), "haiku")
    XCTAssertEqual(value(after: "--append-system-prompt", in: arguments), "You edit a screenshot.")
    // The prompt goes over stdin, not argv.
    XCTAssertEqual(invocation.stdin, "Scene…\n\nRequest: Circle Sign in")
    XCTAssertFalse(arguments.contains("Scene…\n\nRequest: Circle Sign in"))
    XCTAssertEqual(value(after: "--mcp-config", in: arguments), "/tmp/run/snapzy-mcp-R1.json")

    let config = try XCTUnwrap(invocation.files["snapzy-mcp-R1.json"])
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any])
    let server = try XCTUnwrap((object["mcpServers"] as? [String: Any])?["snapzy"] as? [String: Any])
    XCTAssertEqual(server["command"] as? String, mcp.helperPath)
    XCTAssertEqual(server["args"] as? [String], ["mcp"])
    XCTAssertEqual((server["env"] as? [String: String])?["SNAPZY_AGENT_SESSION"], "tok123")
    // The token never appears on the command line (visible in `ps`).
    XCTAssertFalse(arguments.joined(separator: " ").contains("tok123"))
  }

  func testCodexOverridesConfigAndResumesThread() throws {
    let freshInvocation = AnnotateAgentCLIAdapter.invocation(for: .codex, input(image: "/tmp/run/screenshot.jpg"))
    let fresh = freshInvocation.arguments
    XCTAssertEqual(Array(fresh.prefix(2)), ["exec", "--json"])
    XCTAssertEqual(value(after: "--image", in: fresh), "/tmp/run/screenshot.jpg")
    let overrides = fresh.indices.filter { fresh[$0] == "-c" }.map { fresh[$0 + 1] }
    XCTAssertTrue(overrides.contains(#"mcp_servers.snapzy.command="/Apps/Snapzy.app/Contents/Helpers/snapzy""#))
    XCTAssertTrue(overrides.contains(#"mcp_servers.snapzy.args=["mcp"]"#))
    XCTAssertTrue(overrides.contains(#"mcp_servers.snapzy.env={SNAPZY_AGENT_SESSION="tok123"}"#))
    XCTAssertTrue(overrides.contains(#"sandbox_mode="read-only""#))
    // Instructions lead the first message, read from stdin ("-").
    XCTAssertEqual(fresh.last, "-")
    XCTAssertEqual(freshInvocation.stdin, "You edit a screenshot.\n\nScene…\n\nRequest: Circle Sign in")

    let resumedInvocation = AnnotateAgentCLIAdapter.invocation(for: .codex, input(resume: "thread-9"))
    let resumed = resumedInvocation.arguments
    XCTAssertEqual(Array(resumed.prefix(3)), ["exec", "resume", "--json"])
    XCTAssertEqual(Array(resumed.suffix(2)), ["thread-9", "-"])
    XCTAssertEqual(resumedInvocation.stdin, "Scene…\n\nRequest: Circle Sign in")
  }

  func testOpenCodeUsesPrivateServerAndConfigFile() throws {
    let invocation = AnnotateAgentCLIAdapter.invocation(for: .openCode, input(resume: "ses_1", model: "opencode-go/deepseek-v4.1-flash", image: "/tmp/run/screenshot.jpg"))
    let arguments = invocation.arguments
    XCTAssertEqual(Array(arguments.prefix(4)), ["run", "--standalone", "--format", "json"])
    XCTAssertEqual(value(after: "--session", in: arguments), "ses_1")
    XCTAssertEqual(value(after: "--model", in: arguments), "opencode-go/deepseek-v4.1-flash")
    XCTAssertEqual(value(after: "--file", in: arguments), "/tmp/run/screenshot.jpg")
    XCTAssertEqual(arguments.last, "Scene…\n\nRequest: Circle Sign in")
    XCTAssertEqual(invocation.environment["OPENCODE_CONFIG"], "/tmp/run/snapzy-opencode-R1.json")

    let config = try XCTUnwrap(invocation.files["snapzy-opencode-R1.json"])
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any])
    let server = try XCTUnwrap(((object["mcp"] as? [String: Any])?["servers"] as? [String: Any])?["snapzy"] as? [String: Any])
    XCTAssertEqual(server["command"] as? [String], [mcp.helperPath, "mcp"])
    XCTAssertEqual((server["environment"] as? [String: String])?["SNAPZY_AGENT_SESSION"], "tok123")
    XCTAssertEqual((object["permission"] as? [String: String])?["bash"], "deny")
    XCTAssertEqual((object["permission"] as? [String: String])?["read"], "deny")
  }

  func testTOMLStringEscaping() {
    XCTAssertEqual(AnnotateAgentCLIAdapter.toml("a \"b\" \\ c\nd"), #""a \"b\" \\ c\nd""#)
  }

  // MARK: - Event streams (recorded output)

  private func replay(_ kind: AnnotateAgentCLIKind, _ lines: [String]) -> [AnnotateAgentCLIEvent] {
    lines.flatMap { AnnotateAgentCLIAdapter.events(in: $0, kind: kind) }
  }

  func testClaudeStreamJSON() {
    let events = replay(.claudeCode, [
      #"{"type":"system","subtype":"init","session_id":"c-1","tools":["mcp__snapzy__add_box"]}"#,
      #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__snapzy__add_box","input":{}}]},"session_id":"c-1"}"#,
      #"{"type":"user","message":{"content":[{"type":"tool_result","content":"{\"ok\":true}"}]}}"#,
      #"{"type":"assistant","message":{"content":[{"type":"text","text":"Circled Sign in."}]}}"#,
      #"{"type":"result","subtype":"success","is_error":false,"result":"Circled Sign in in red.","session_id":"c-1"}"#,
      "not json",
    ])
    XCTAssertEqual(events, [.session("c-1"), .message("Circled Sign in."), .session("c-1"), .message("Circled Sign in in red.")])

    let failure = replay(.claudeCode, [
      #"{"type":"result","subtype":"success","is_error":true,"result":"Invalid API key · Please run /login","session_id":"c-2"}"#,
    ])
    XCTAssertEqual(failure.last, .failure("Invalid API key · Please run /login"))
    let maxTurns = replay(.claudeCode, [#"{"type":"result","subtype":"error_max_turns","is_error":true}"#])
    XCTAssertEqual(maxTurns, [.failure("error_max_turns")])
  }

  func testCodexJSONL() {
    let events = replay(.codex, [
      #"{"type":"thread.started","thread_id":"0199-abc"}"#,
      #"{"type":"turn.started"}"#,
      #"{"type":"item.completed","item":{"id":"item_0","type":"reasoning","text":"**Planning**"}}"#,
      #"{"type":"item.started","item":{"id":"item_1","type":"mcp_tool_call","server":"snapzy","tool":"add_box","status":"in_progress"}}"#,
      #"{"type":"item.completed","item":{"id":"item_1","type":"mcp_tool_call","server":"snapzy","tool":"add_box","status":"completed"}}"#,
      #"{"type":"item.completed","item":{"id":"item_2","type":"agent_message","text":"Boxed Sign in."}}"#,
      #"{"type":"turn.completed","usage":{"input_tokens":10}}"#,
    ])
    XCTAssertEqual(events, [.session("0199-abc"), .message("Boxed Sign in.")])
    XCTAssertEqual(replay(.codex, [#"{"type":"turn.failed","error":{"message":"quota exceeded"}}"#]), [.failure("quota exceeded")])
    XCTAssertEqual(replay(.codex, [#"{"type":"error","message":"stream disconnected"}"#]), [.failure("stream disconnected")])
  }

  /// Recorded from `opencode run --format json` (OpenCode 2.1, DeepSeek v4.1 Flash).
  func testOpenCodeJSON() {
    let events = replay(.openCode, [
      #"{"type":"step_start","timestamp":1,"sessionID":"ses_e1f7","part":{"type":"step-start"}}"#,
      #"{"type":"tool_use","timestamp":2,"sessionID":"ses_e1f7","part":{"type":"tool","tool":"execute","state":{"status":"completed","input":{"code":"return await tools.snapzy.add_box({ text: \"Sign in\" });"},"output":"Added box a1"}}}"#,
      #"{"type":"step_finish","timestamp":3,"sessionID":"ses_e1f7","part":{"type":"step-finish","reason":"tool-calls"}}"#,
      #"{"type":"text","timestamp":4,"sessionID":"ses_e1f7","part":{"type":"text","text":"Drew box a1 around Sign in."}}"#,
    ])
    XCTAssertEqual(events.compactMap { if case .message(let text) = $0 { text } else { nil } }, ["Drew box a1 around Sign in."])
    XCTAssertTrue(events.allSatisfy { if case .session(let id) = $0 { id == "ses_e1f7" } else { true } })
    let failure = replay(.openCode, [#"{"type":"error","sessionID":"s","error":{"name":"ProviderAuthError","data":{"message":"No API key for opencode-go"}}}"#])
    XCTAssertEqual(failure.last, .failure("No API key for opencode-go"))
  }

  func testRetriedErrorsDoNotFailARunThatFinished() {
    var outcome = AnnotateAgentCLIProvider.Outcome()
    for line in [
      #"{"type":"thread.started","thread_id":"t"}"#,
      #"{"type":"error","message":"Reconnecting... 2/5"}"#,
      #"{"type":"item.completed","item":{"type":"agent_message","text":"Done."}}"#,
    ] {
      AnnotateAgentCLIAdapter.events(in: line, kind: .codex).forEach { outcome.apply($0) }
    }
    XCTAssertNil(outcome.failure)
    XCTAssertEqual(outcome.reply, "Done.")

    // A final error after the text (Claude's is_error result) still fails the run.
    var claude = AnnotateAgentCLIProvider.Outcome()
    for line in [
      #"{"type":"assistant","message":{"content":[{"type":"text","text":"Working"}]}}"#,
      #"{"type":"result","subtype":"error_during_execution","is_error":true}"#,
    ] {
      AnnotateAgentCLIAdapter.events(in: line, kind: .claudeCode).forEach { claude.apply($0) }
    }
    XCTAssertEqual(claude.failure, "error_during_execution")
  }

  func testErrorLineShortening() {
    let text = "\u{1B}[31mError\u{1B}[0m: something\n\n  Not logged in · Please run /login  \n"
    XCTAssertEqual(AnnotateAgentCLIProvider.shorten(text), "Not logged in · Please run /login")
  }

  // MARK: - Prompt

  func testPromptCarriesHistoryOnlyWithoutResume() {
    let request = AnnotateAgentRequest(
      prompt: "make it blue",
      history: [AnnotateAgentTurn(prompt: "Circle Sign in", reply: "Circled it.", providerSessionID: "s")],
      sceneJSON: "{}"
    )
    let fresh = AnnotateAgentCLIProvider.prompt(for: request, surface: .annotate, hasImage: true, attachesImage: false)
    XCTAssertTrue(fresh.contains("Earlier in this conversation"))
    XCTAssertTrue(fresh.contains("get_snapshot"))
    XCTAssertTrue(fresh.hasSuffix("Request: make it blue"))

    var resumed = request
    resumed.resumeSessionID = "s"
    let next = AnnotateAgentCLIProvider.prompt(for: resumed, surface: .annotate, hasImage: false, attachesImage: false)
    XCTAssertFalse(next.contains("Earlier in this conversation"))
    XCTAssertFalse(next.contains("get_snapshot"))
  }

  // MARK: - Selection

  func testSelectionPersistsCLIKinds() throws {
    for kind in AnnotateAgentCLIKind.allCases {
      let selection = AnnotateAgentProviderSelection.cli(kind)
      XCTAssertEqual(AnnotateAgentProviderSelection(persistedValue: selection.persistedValue), selection)
    }
    XCTAssertEqual(AnnotateAgentProviderSelection(persistedValue: "cli:gemini"), .automatic)

    let suite = "AnnotateAgentCLIProviderTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(false, forKey: AnnotateAgentProviderResolver.mockProviderDefaultsKey)
    AnnotateAgentProviderResolver.setSelection(.cli(.openCode), defaults: defaults)
    let provider = AnnotateAgentProviderResolver.resolve(defaults: defaults, endpoints: [])
    XCTAssertEqual((provider as? AnnotateAgentCLIProvider)?.kind, .openCode)
    XCTAssertEqual(provider?.remoteDestination?.id, "cli:opencode")
  }

  func testLocatePrefersCustomPathAndSearchesLoginPath() throws {
    let suite = "AnnotateAgentCLIProviderTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fake = directory.appendingPathComponent("codex")
    try Data("#!/bin/sh\n".utf8).write(to: fake)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)

    XCTAssertEqual(AnnotateAgentCLIEnvironment.locate(.codex, defaults: defaults, loginPath: directory.path), fake.path)
    defaults.set("/nonexistent/codex", forKey: AnnotateAgentCLIKind.codex.pathDefaultsKey)
    XCTAssertNil(AnnotateAgentCLIEnvironment.locate(.codex, defaults: defaults, loginPath: directory.path))

    let environment = AnnotateAgentCLIEnvironment.environment(forExecutable: fake.path, loginPath: "/usr/bin:/bin")
    XCTAssertTrue(environment["PATH"]?.hasPrefix(directory.path + ":/usr/bin:/bin") == true)
  }

  // MARK: - Bridge

  private func makeState() throws -> AnnotateState {
    let state = AnnotateState()
    Self.retained.append(state)
    let cgImage = try XCTUnwrap(TestImageFactory.solidColor(width: Int(imageSize.width), height: Int(imageSize.height)))
    state.loadImage(NSImage(cgImage: cgImage, size: imageSize))
    return state
  }

  private func makeSession(_ state: AnnotateState) -> AnnotateAgentSession {
    let toolbox = AnnotateAgentToolbox(state: state, analysis: .empty)
    Self.retained.append(toolbox)
    toolbox.beginRun()
    return AnnotateAgentSession(toolbox: toolbox, pacingEnabled: false)
  }

  func testBridgeTokenRunsToolsOnlyWhileTheRunIsLive() async throws {
    let state = try makeState()
    let session = makeSession(state)
    let bridge = AnnotateAgentBridge()
    let image = try XCTUnwrap(state.effectiveSourceImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let token = bridge.open(session: session, image: image, sceneSize: imageSize)
    XCTAssertEqual(token.count, 64)

    let tools = try bridge.tools(token: token).map(\.name)
    XCTAssertTrue(tools.contains("add_box"))
    XCTAssertTrue(tools.contains(AnnotateAgentBridge.snapshotToolName))

    let result = try await bridge.call(token: token, name: "add_box", arguments: #"{"target":{"rect":[10,10,100,50]}}"#)
    XCTAssertFalse(result.isError)
    XCTAssertEqual(state.annotations.count, 1)

    let snapshot = try await bridge.call(token: token, name: AnnotateAgentBridge.snapshotToolName, arguments: "{}")
    XCTAssertEqual(snapshot.image?.mimeType, "image/jpeg")
    XCTAssertNotNil(Data(base64Encoded: snapshot.image?.base64 ?? ""))

    // A wrong token never reaches the canvas.
    XCTAssertThrowsError(try bridge.tools(token: "nope")) { XCTAssertEqual(($0 as? CLIError)?.code, .notAuthorized) }

    // Stop / end of run: the session is invalidated, the token stops working.
    session.invalidate()
    do {
      _ = try await bridge.call(token: token, name: "add_box", arguments: #"{"target":{"rect":[10,10,100,50]}}"#)
      XCTFail("expected expiry")
    } catch {
      XCTAssertEqual((error as? CLIError)?.code, .notAuthorized)
    }
    XCTAssertEqual(state.annotations.count, 1)
    XCTAssertEqual(bridge.openCount, 0)
  }

  func testBridgeCloseRevokesToken() throws {
    let state = try makeState()
    let bridge = AnnotateAgentBridge()
    // The bridge holds the session weakly; the controller owns it during a run.
    let session = makeSession(state)
    let token = bridge.open(session: session, image: nil, sceneSize: nil)
    XCTAssertFalse(try bridge.tools(token: token).contains { $0.name == AnnotateAgentBridge.snapshotToolName })
    bridge.close(token)
    XCTAssertThrowsError(try bridge.tools(token: token))
  }

  func testAgentMethodsSkipAppApprovalAndHaveRoutes() {
    XCTAssertTrue(CLIAuthorizationCoordinator.exemptMethods.contains(CLIMethod.agentCall.rawValue))
    XCTAssertTrue(CLIAuthorizationCoordinator.exemptMethods.contains(CLIMethod.agentTools.rawValue))
    XCTAssertEqual(CLIServer.makeAgentRouter().registeredMethods, ["system.status", "agent.tools", "agent.call"])
  }

  // MARK: - Process

  func testTerminateEndsTheWholeProcessGroup() async throws {
    let directory = NSTemporaryDirectory()
    let marker = (directory as NSString).appendingPathComponent("snapzy-cli-\(UUID().uuidString).pid")
    // The shell starts a grandchild that would outlive a plain kill(pid).
    let process = try AnnotateAgentCLIProcess(
      executable: "/bin/sh",
      arguments: ["-c", "sleep 30 & echo $! > '\(marker)'; echo ready; wait"],
      environment: ["PATH": "/usr/bin:/bin"],
      directory: directory
    )
    var lines: [String] = []
    for await line in process.lines {
      lines.append(line)
      if line == "ready" { break }
    }
    XCTAssertEqual(lines, ["ready"])
    let grandchild = try XCTUnwrap(pid_t(String(contentsOfFile: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
    defer { try? FileManager.default.removeItem(atPath: marker) }

    process.terminate()
    let exit = await process.waitForExit()
    XCTAssertEqual(exit.status, 128 + SIGTERM)
    try await Task.sleep(nanoseconds: 200_000_000)
    XCTAssertEqual(kill(grandchild, 0), -1, "grandchild should be gone")
  }

  func testProcessReportsExitStatusAndStderr() async throws {
    let process = try AnnotateAgentCLIProcess(
      executable: "/bin/sh",
      arguments: ["-c", "echo one; echo two; echo 'Not logged in' >&2; exit 3"],
      environment: ["PATH": "/usr/bin:/bin"],
      directory: NSTemporaryDirectory()
    )
    var lines: [String] = []
    for await line in process.lines { lines.append(line) }
    let exit = await process.waitForExit()
    XCTAssertEqual(lines, ["one", "two"])
    XCTAssertEqual(exit.status, 3)
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertTrue(process.stderrTailForTesting.contains("Not logged in"))
  }

  // MARK: - Live evaluation (opt-in)

  /// The plan's 10 standard prompts through a real agent CLI and `snapzy mcp`:
  /// `SNAPZY_LIVE_CLI="opencode|opencode-go/deepseek-v4.1-flash"` (xcodebuild: prefix `TEST_RUNNER_`).
  /// Needs the Debug app's embedded helper; the socket goes to a private path.
  func testLiveStandardPrompts() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let spec = environment["SNAPZY_LIVE_CLI"] else {
      throw XCTSkip("Set SNAPZY_LIVE_CLI=\"opencode|<model>\" to run a real agent CLI")
    }
    let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
    let kind = try XCTUnwrap(AnnotateAgentCLIKind(rawValue: parts[0]))
    guard FileManager.default.isExecutableFile(atPath: AnnotateAgentCLIProvider.helperPath) else {
      throw XCTSkip("No embedded snapzy helper at \(AnnotateAgentCLIProvider.helperPath)")
    }
    // Never touch the socket of a Snapzy that is running on this Mac.
    // The listener wants a parent directory owned by the user (not /tmp).
    let socket = (NSTemporaryDirectory() as NSString).appendingPathComponent("snapzy-live-\(getpid()).sock")
    setenv("SNAPZY_SOCKET", socket, 1)
    CLIServer.shared.stop()
    defer {
      CLIServer.shared.stop()
      unsetenv("SNAPZY_SOCKET")
    }

    let suite = "AnnotateAgentCLIProviderTests.live.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    if parts.count > 1 { defaults.set(parts[1], forKey: kind.modelDefaultsKey) }
    defaults.set(false, forKey: AnnotateAgentEndpointProvider.sendImageDefaultsKey)

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
    let only = environment["SNAPZY_LIVE_CLI_ONLY"].flatMap(Int.init)
    for (index, (prompt, check)) in prompts.enumerated() where only == nil || only == index + 1 {
      let state = try makeState()
      let toolbox = AnnotateAgentToolbox(state: state, analysis: loginAnalysis)
      Self.retained.append(toolbox)
      toolbox.beginRun()
      var calls: [String] = []
      let session = AnnotateAgentSession(toolbox: toolbox, pacingEnabled: false, onToolStart: { calls.append($0?.rawValue ?? "?") })
      _ = toolbox.execute(name: "add_arrow", argumentsJSON: #"{"to":"t6","color":"red"}"#)
      _ = toolbox.execute(name: "add_box", argumentsJSON: #"{"target":"t5","color":"red"}"#)
      let provider = AnnotateAgentCLIProvider(kind: kind, defaults: defaults)
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
        log("[live-cli] \(ok ? "PASS" : "MISS") \(String(format: "%.1fs", Date().timeIntervalSince(started))) “\(prompt)” → [\(kinds)] calls: \(calls.joined(separator: ",")) session: \(session.providerSessionID ?? "-") “\(reply)”")
      } catch {
        errors += 1
        log("[live-cli] ERROR \(String(format: "%.1fs", Date().timeIntervalSince(started))) “\(prompt)” → \(error)")
      }
      session.invalidate()
      _ = toolbox.finishRun()
    }
    log("[live-cli] \(kind.displayName) \(parts.count > 1 ? parts[1] : "default"): \(passed)/\(only == nil ? prompts.count : 1) passed, \(errors) errors")
    let report = lines.joined(separator: "\n")
    try? report.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snapzy-live-cli.log"), atomically: true, encoding: .utf8)
    add(XCTAttachment(string: report))
    XCTAssertLessThan(errors, max(1, (only == nil ? prompts.count : 1) / 2) + (only == nil ? 0 : 1))
    XCTAssertEqual(AnnotateAgentBridge.shared.openCount, 0)
  }
}
