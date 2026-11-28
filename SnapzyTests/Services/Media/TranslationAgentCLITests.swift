//
//  TranslationAgentCLITests.swift
//  SnapzyTests
//
//  Translating through an agent CLI: engine selection, routing, the translation
//  model override and the text-only CLI invocations (no agent is called).
//

import XCTest
@testable import Snapzy

@MainActor
final class TranslationAgentCLITests: XCTestCase {
  private func value(after flag: String, in arguments: [String]) -> String? {
    arguments.firstIndex(of: flag).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
  }

  // MARK: Selection

  func testSelectionRoundTripsEveryEngine() {
    let id = UUID()
    let selections: [TranslationEngineSelection] = [.builtIn, .custom(id), .agentCLI(.claudeCode), .agentCLI(.codex), .agentCLI(.openCode)]
    for selection in selections {
      XCTAssertEqual(TranslationEngineSelection(persistedValue: selection.persistedValue), selection)
    }
    XCTAssertEqual(TranslationEngineSelection.agentCLI(.claudeCode).persistedValue, "cli:claude")
    XCTAssertEqual(TranslationEngineSelection.custom(id).persistedValue, "custom:\(id.uuidString)")
  }

  func testUnknownSelectionReadsAsBuiltIn() {
    XCTAssertEqual(TranslationEngineSelection(persistedValue: "cli:gemini"), .builtIn)
    XCTAssertEqual(TranslationEngineSelection(persistedValue: "custom:not-a-uuid"), .builtIn)
    XCTAssertEqual(TranslationEngineSelection(persistedValue: ""), .builtIn)
  }

  func testCLISelectionResolvesToRemoteOnAnySystem() {
    let defaults = UserDefaultsFactory.make()
    let resolver = TranslationEngineResolver(defaults: defaults, isAppleTranslationSupported: false)
    resolver.store(.agentCLI(.codex))
    XCTAssertEqual(resolver.resolve(), .remote(.agentCLI(.codex)))
    XCTAssertEqual(RemoteTranslationEngine.agentCLI(.codex).displayName, "Codex")
  }

  // MARK: Model override

  func testModelFollowsAISettingsUntilOverridden() {
    let defaults = UserDefaultsFactory.make()
    XCTAssertNil(TranslationAgentCLISettings.model(.claudeCode, defaults: defaults))

    defaults.set("opus", forKey: AnnotateAgentCLIKind.claudeCode.modelDefaultsKey)
    defaults.set("high", forKey: AnnotateAgentCLIKind.claudeCode.effortDefaultsKey)
    XCTAssertEqual(TranslationAgentCLISettings.model(.claudeCode, defaults: defaults), "opus")
    XCTAssertEqual(TranslationAgentCLISettings.effort(.claudeCode, defaults: defaults), "high")

    TranslationAgentCLISettings.setModelOverride("  haiku ", for: .claudeCode, defaults: defaults)
    XCTAssertEqual(TranslationAgentCLISettings.modelOverride(.claudeCode, defaults: defaults), "haiku")
    XCTAssertEqual(TranslationAgentCLISettings.model(.claudeCode, defaults: defaults), "haiku")
    // The AI effort was picked for another model: the override runs at the CLI's default.
    XCTAssertNil(TranslationAgentCLISettings.effort(.claudeCode, defaults: defaults))

    TranslationAgentCLISettings.setModelOverride("", for: .claudeCode, defaults: defaults)
    XCTAssertNil(TranslationAgentCLISettings.modelOverride(.claudeCode, defaults: defaults))
    XCTAssertEqual(TranslationAgentCLISettings.model(.claudeCode, defaults: defaults), "opus")
  }

  func testOverrideIsPerCLI() {
    let defaults = UserDefaultsFactory.make()
    TranslationAgentCLISettings.setModelOverride("gpt-5-mini", for: .codex, defaults: defaults)
    XCTAssertNil(TranslationAgentCLISettings.modelOverride(.openCode, defaults: defaults))
    XCTAssertEqual(defaults.string(forKey: "translate.cli.codex.model"), "gpt-5-mini")
  }

  // MARK: Text invocations

  func testClaudeCodeTextRunHasNoToolsAndNoMCP() {
    let invocation = AnnotateAgentCLIAdapter.textInvocation(
      for: .claudeCode, prompt: "Translate…", model: "haiku", effort: "low", directory: "/tmp/run", runID: "R1"
    )
    let arguments = invocation.arguments
    XCTAssertEqual(arguments.first, "-p")
    XCTAssertTrue(arguments.contains("--strict-mcp-config"))
    XCTAssertFalse(arguments.contains("--mcp-config"))
    XCTAssertFalse(arguments.contains("--allowedTools"))
    XCTAssertEqual(value(after: "--tools", in: arguments), "")
    XCTAssertEqual(value(after: "--model", in: arguments), "haiku")
    XCTAssertEqual(value(after: "--effort", in: arguments), "low")
    XCTAssertEqual(invocation.stdin, "Translate…")
    XCTAssertTrue(invocation.files.isEmpty)
  }

  func testCodexTextRunIsReadOnlyAndReadsStdin() {
    let invocation = AnnotateAgentCLIAdapter.textInvocation(
      for: .codex, prompt: "Translate…", model: nil, effort: nil, directory: "/tmp/run", runID: "R1"
    )
    XCTAssertEqual(invocation.arguments.prefix(2), ["exec", "--json"])
    XCTAssertTrue(invocation.arguments.contains("sandbox_mode=\"read-only\""))
    XCTAssertFalse(invocation.arguments.contains { $0.hasPrefix("mcp_servers.") })
    XCTAssertFalse(invocation.arguments.contains("--model"))
    XCTAssertEqual(invocation.arguments.last, "-")
    XCTAssertEqual(invocation.stdin, "Translate…")
  }

  func testOpenCodeTextRunDeniesToolsAndAddsEffortVariant() throws {
    let invocation = AnnotateAgentCLIAdapter.textInvocation(
      for: .openCode, prompt: "Translate…", model: "openai/gpt-5", effort: "low", directory: "/tmp/run", runID: "R1"
    )
    XCTAssertEqual(value(after: "--model", in: invocation.arguments), "openai/gpt-5#low")
    XCTAssertEqual(invocation.arguments.last, "Translate…")
    XCTAssertEqual(invocation.environment["OPENCODE_CONFIG"], "/tmp/run/snapzy-opencode-R1.json")
    let config = try XCTUnwrap(invocation.files["snapzy-opencode-R1.json"])
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any])
    XCTAssertNil(object["mcp"])
    let permission = try XCTUnwrap(object["permission"] as? [String: String])
    XCTAssertEqual(permission["bash"], "deny")
    XCTAssertEqual(permission["read"], "deny")
  }

  // MARK: Block translator

  func testProviderTrimsCompleterReplyAndBlocksParse() async throws {
    let reply = #"```json{"items":[{"id":0,"text":"Xin chào"},{"id":1,"text":"Thế giới"}]}```"#
    let provider = RemoteTranslationProvider(completer: TranslationPromptCompleter { prompt in
      XCTAssertTrue(prompt.contains("Vietnamese"))
      return "  Xin chào thế giới \n"
    })
    let translated = try await provider.translate("Hello world", to: TranslationLanguage(identifier: "vi"))
    XCTAssertEqual(translated, "Xin chào thế giới")
    XCTAssertEqual(RemoteBlockTranslator.parse(reply, count: 2), ["Xin chào", "Thế giới"])
  }

  func testChunksRespectCountAndCharacterLimits() {
    let blocks = ["aaaa", "bb", "cccccc", "d", "e"]
    XCTAssertEqual(RemoteBlockTranslator.chunks(blocks, maxCount: 2, maxCharacters: .max), [0..<2, 2..<4, 4..<5])
    XCTAssertEqual(RemoteBlockTranslator.chunks(blocks, maxCount: 10, maxCharacters: 7), [0..<2, 2..<4, 4..<5])
    // A block longer than the limit still goes, alone.
    XCTAssertEqual(RemoteBlockTranslator.chunks(["x" + String(repeating: "y", count: 20)], maxCount: 10, maxCharacters: 5), [0..<1])
    XCTAssertEqual(RemoteBlockTranslator.chunks([], maxCount: 10, maxCharacters: 5), [])
  }
}
