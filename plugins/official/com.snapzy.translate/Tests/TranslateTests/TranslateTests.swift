import Foundation
import SnapzyPluginAPI
import SnapzyPluginSDK
import SnapzyPluginTesting
import Testing

@testable import Translate

@Test func translateReturnsPatchWhenAnnotateDocumentPresent() async throws {
  let host = FakeHost()
  host.registerSecret(key: "apiKey", value: "sk-fake-openai-key")
  host.registerAsset(Data("fake-image".utf8))
  host.stubOCR(lines: ["Hello World", "Welcome to Snapzy"])

  let openAIResponse: [String: Any] = [
    "choices": [
      [
        "message": [
          "content": "[\"Bonjour le monde\", \"Bienvenue sur Snapzy\"]"
        ]
      ]
    ]
  ]
  let openAIData = try JSONSerialization.data(withJSONObject: openAIResponse)
  host.registerHTTPResponse(status: 200, body: openAIData)

  let harness = PluginHarness(TranslatePlugin.self, host: host)
  let doc = AnnotateDocument(
    schema: 1,
    size: SnapzySize(width: 800, height: 600),
    scale: 2.0,
    items: []
  )

  let result = try await harness.execute(
    "translate",
    document: .annotate(doc)
  )

  #expect(result.isSuccess)
  if case .patch(let edits) = result {
    #expect(edits.count == 2)
  } else {
    Issue.record("Expected .patch outcome, got \(result)")
  }
}

@Test func translateReturnsPlainTextWhenNoDocumentPresent() async throws {
  let host = FakeHost()
  host.registerSecret(key: "apiKey", value: "sk-fake-openai-key")
  host.registerAsset(Data("fake-image".utf8))
  host.stubOCR(lines: ["Hello World"])

  let openAIResponse: [String: Any] = [
    "choices": [
      [
        "message": [
          "content": "[\"Bonjour le monde\"]"
        ]
      ]
    ]
  ]
  let openAIData = try JSONSerialization.data(withJSONObject: openAIResponse)
  host.registerHTTPResponse(status: 200, body: openAIData)

  let harness = PluginHarness(TranslatePlugin.self, host: host)
  let result = try await harness.execute("translate", document: nil)

  #expect(result.isSuccess)
  if case .text(let text) = result {
    #expect(text == "Bonjour le monde")
  } else {
    Issue.record("Expected .text outcome, got \(result)")
  }
}

@Test func translateFailsWhenNoAPIKeyConfigured() async throws {
  let host = FakeHost()
  let harness = PluginHarness(TranslatePlugin.self, host: host)
  let result = try await harness.execute("translate")

  #expect(!result.isSuccess)
}
