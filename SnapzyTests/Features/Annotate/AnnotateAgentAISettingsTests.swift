//
//  AnnotateAgentAISettingsTests.swift
//  SnapzyTests
//
//  Annotate AI prompt, phase 6: Settings › AI plumbing — endpoint Test probe,
//  CLI version parsing, shared options, `[annotate.ai]` config import/export.
//

import XCTest
@testable import Snapzy

@MainActor
final class AnnotateAgentAISettingsTests: XCTestCase {
  private let model = CustomOCRModel(name: "Local LLM", baseURL: "http://localhost:11434/v1", modelIdentifier: "qwen3")

  /// Answers requests in order; records the decoded JSON bodies.
  private final class Script: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(Int, String)]
    private(set) var bodies: [[String: Any]] = []

    init(_ responses: [(Int, String)]) { self.responses = responses }

    func respond(_ request: URLRequest) throws -> (Data, URLResponse) {
      lock.lock(); defer { lock.unlock() }
      bodies.append(request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:])
      guard !responses.isEmpty else { throw URLError(.badServerResponse) }
      let (status, text) = responses.removeFirst()
      return MockURLSession.makeResponse(statusCode: status, data: Data(text.utf8))
    }
  }

  private static let toolCall = #"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"c1","type":"function","function":{"name":"ping","arguments":"{}"}}]}}]}"#
  private static let text = #"{"choices":[{"message":{"role":"assistant","content":"Red"}}]}"#

  private func probe(_ responses: [(Int, String)], defaults: UserDefaults) async -> (AnnotateAgentEndpointProbe.Outcome, Script) {
    let script = Script(responses)
    let outcome = await AnnotateAgentEndpointProbe.run(
      model,
      keychainStore: FakeOCRKeychainStore(),
      session: MockURLSession { try script.respond($0) },
      defaults: defaults
    )
    return (outcome, script)
  }

  // MARK: - Endpoint probe

  func testProbeLearnsToolsAndVision() async {
    let defaults = UserDefaultsFactory.make()
    let (outcome, script) = await probe([(200, Self.toolCall), (200, Self.text)], defaults: defaults)

    let expected = AnnotateAgentEndpointCapabilities(supportsTools: true, supportsVision: true)
    XCTAssertEqual(outcome, .finished(expected))
    XCTAssertEqual(AnnotateAgentEndpointCapabilityStore(defaults: defaults).capabilities(for: model), expected)
    XCTAssertNotNil(script.bodies.first?["tools"])
    let content = (script.bodies.last?["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]
    XCTAssertEqual(content?.last?["type"] as? String, "image_url")
    XCTAssertFalse(AnnotateAgentEndpointProbe.probeImageBase64.isEmpty)
  }

  func testProbeRecordsRejectedToolsAndImages() async {
    let defaults = UserDefaultsFactory.make()
    let (outcome, _) = await probe([
      (400, #"{"error":"registry.ollama.ai/library/gemma does not support tools"}"#),
      (400, #"{"error":"this model does not support image input"}"#),
    ], defaults: defaults)

    XCTAssertEqual(outcome, .finished(AnnotateAgentEndpointCapabilities(supportsTools: false, supportsVision: false)))
  }

  func testProbeTextAnswerLeavesToolsUnknown() async {
    let defaults = UserDefaultsFactory.make()
    let (outcome, _) = await probe([(200, Self.text), (200, Self.text)], defaults: defaults)
    XCTAssertEqual(outcome, .finished(AnnotateAgentEndpointCapabilities(supportsTools: nil, supportsVision: true)))
  }

  func testProbeTextAnswerKeepsLearnedToolSupport() async {
    let defaults = UserDefaultsFactory.make()
    let store = AnnotateAgentEndpointCapabilityStore(defaults: defaults)
    store.save(AnnotateAgentEndpointCapabilities(supportsTools: true, supportsVision: nil), for: model)

    let (outcome, _) = await probe([(200, Self.text), (200, Self.text)], defaults: defaults)

    XCTAssertEqual(outcome, .finished(AnnotateAgentEndpointCapabilities(supportsTools: true, supportsVision: true)))
    XCTAssertEqual(store.capabilities(for: model).supportsTools, true)
  }

  func testProbeReportsAuthFailureWithoutSaving() async {
    let defaults = UserDefaultsFactory.make()
    let (outcome, _) = await probe([(401, #"{"error":"bad key"}"#)], defaults: defaults)

    guard case .failed(let message) = outcome else { return XCTFail("expected failure, got \(outcome)") }
    XCTAssertFalse(message.isEmpty)
    XCTAssertEqual(AnnotateAgentEndpointCapabilityStore(defaults: defaults).capabilities(for: model), AnnotateAgentEndpointCapabilities())
  }

  // MARK: - CLI version

  func testParseVersionPullsNumberFromVersionLine() {
    XCTAssertEqual(AnnotateAgentCLIEnvironment.parseVersion("2.1.325 (Claude Code)\n"), "2.1.325")
    XCTAssertEqual(AnnotateAgentCLIEnvironment.parseVersion("codex-cli 0.169.0"), "0.169.0")
    XCTAssertEqual(AnnotateAgentCLIEnvironment.parseVersion("\n  2.1.0-beta.3\nextra"), "2.1.0-beta.3")
    XCTAssertEqual(AnnotateAgentCLIEnvironment.parseVersion("dev build"), "dev build")
    XCTAssertNil(AnnotateAgentCLIEnvironment.parseVersion("  \n"))
  }

  // MARK: - Shared options

  func testCLITimeoutHonorsAnyPositiveValue() {
    let defaults = UserDefaultsFactory.make()
    XCTAssertEqual(AnnotateAgentAISettings.cliTimeout(defaults: defaults), 180)
    defaults.set(300.0, forKey: PreferencesKeys.annotateAgentCLITimeout)
    XCTAssertEqual(AnnotateAgentAISettings.cliTimeout(defaults: defaults), 300)
    defaults.set(5.0, forKey: PreferencesKeys.annotateAgentCLITimeout)
    XCTAssertEqual(AnnotateAgentAISettings.cliTimeout(defaults: defaults), 5)
    defaults.set(-1.0, forKey: PreferencesKeys.annotateAgentCLITimeout)
    XCTAssertEqual(AnnotateAgentAISettings.cliTimeout(defaults: defaults), 180)
  }

  func testResetConsentsForgetsAllowedProviders() {
    let defaults = UserDefaultsFactory.make()
    defaults.set(["cli:codex", "endpoint:x@http:localhost"], forKey: PreferencesKeys.annotateAgentConsentedProviders)
    XCTAssertEqual(AnnotateAgentAISettings.consentedProviderCount(defaults: defaults), 2)
    AnnotateAgentAISettings.resetConsents(defaults: defaults)
    XCTAssertEqual(AnnotateAgentAISettings.consentedProviderCount(defaults: defaults), 0)
  }

  // MARK: - Config file

  func testConfigRoundTripsAISettings() {
    let source = UserDefaultsFactory.make()
    source.set("cli:opencode", forKey: PreferencesKeys.annotateAgentProvider)
    source.set(false, forKey: PreferencesKeys.annotateAgentSendImage)
    source.set(600.0, forKey: PreferencesKeys.annotateAgentCLITimeout)
    source.set("opencode-go/deepseek-v4.1-flash", forKey: AnnotateAgentCLIKind.openCode.modelDefaultsKey)
    source.set("/opt/claude", forKey: AnnotateAgentCLIKind.claudeCode.pathDefaultsKey)

    let toml = SnapzyConfigurationExporter.exportTOML(defaults: source)
    XCTAssertTrue(toml.contains("[annotate.ai]"))
    XCTAssertFalse(toml.contains("/opt/claude"), "CLI paths are per-Mac")

    let target = UserDefaultsFactory.make()
    target.set("sonnet", forKey: AnnotateAgentCLIKind.claudeCode.modelDefaultsKey)
    let result = SnapzyConfigurationImporter.importTOML(toml, defaults: target)

    XCTAssertFalse(result.hasErrors)
    XCTAssertEqual(target.string(forKey: PreferencesKeys.annotateAgentProvider), "cli:opencode")
    XCTAssertEqual(target.object(forKey: PreferencesKeys.annotateAgentSendImage) as? Bool, false)
    XCTAssertEqual(target.double(forKey: PreferencesKeys.annotateAgentCLITimeout), 600)
    XCTAssertEqual(target.string(forKey: AnnotateAgentCLIKind.openCode.modelDefaultsKey), "opencode-go/deepseek-v4.1-flash")
    XCTAssertNil(target.string(forKey: AnnotateAgentCLIKind.claudeCode.modelDefaultsKey), "empty model clears the override")
  }

  func testConfigImportNormalizesUnknownProviderAndRejectsTimeout() {
    let defaults = UserDefaultsFactory.make()
    let ok = SnapzyConfigurationImporter.importTOML("""
    schema_version = 1

    [annotate.ai]
    provider = "cli:gemini"
    """, defaults: defaults)
    XCTAssertFalse(ok.hasErrors)
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.annotateAgentProvider), "automatic")

    let bad = SnapzyConfigurationImporter.importTOML("""
    schema_version = 1

    [annotate.ai]
    cli_timeout = 5
    """, defaults: defaults)
    XCTAssertTrue(bad.hasErrors)
  }

  func testDefaultDocumentResetsAISettings() {
    let defaults = UserDefaultsFactory.make()
    defaults.set("apple", forKey: PreferencesKeys.annotateAgentProvider)
    defaults.set(false, forKey: PreferencesKeys.annotateAgentSendImage)

    let result = SnapzyConfigurationImporter.importTOML(SnapzyConfigurationDefaultDocument.toml(), defaults: defaults)

    XCTAssertFalse(result.hasErrors)
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.annotateAgentProvider), "automatic")
    XCTAssertEqual(defaults.object(forKey: PreferencesKeys.annotateAgentSendImage) as? Bool, true)
    XCTAssertEqual(defaults.double(forKey: PreferencesKeys.annotateAgentCLITimeout), 180)
  }
}
