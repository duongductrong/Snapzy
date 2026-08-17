import Foundation
import SnapzyPluginAPI
import SnapzyPluginSDK
import SnapzyPluginTesting
import Testing

@testable import WebhookUpload

@Test func webhookUploadSuccess() async throws {
  let host = FakeHost()
  host.registerSecret(key: "webhookURL", value: "https://discord.com/api/webhooks/123/abc")
  host.registerAsset(Data("fake-image-bytes".utf8))

  let discordJSON: [String: Any] = [
    "attachments": [
      ["url": "https://cdn.discordapp.com/attachments/123/456/snapzy.png"]
    ]
  ]
  let discordData = try JSONSerialization.data(withJSONObject: discordJSON)
  host.registerHTTPResponse(status: 200, body: discordData)

  let harness = PluginHarness(WebhookUploadPlugin.self, host: host)
  let result = try await harness.execute("upload", options: ["message": .string("Test capture")])

  #expect(result.isSuccess)
  if case .url(let url) = result {
    #expect(url.absoluteString == "https://cdn.discordapp.com/attachments/123/456/snapzy.png")
  } else {
    Issue.record("Expected .url outcome, got \(result)")
  }
}

@Test func webhookUploadPromptsFormWhenNoSecret() async throws {
  let host = FakeHost()
  host.registerAsset(Data("fake-image-bytes".utf8))
  host.registerUIFormResponse(["webhook": .string("https://discord.com/api/webhooks/999/xyz")])

  let discordJSON: [String: Any] = [
    "attachments": [
      ["url": "https://cdn.discordapp.com/attachments/999/snapzy.png"]
    ]
  ]
  let discordData = try JSONSerialization.data(withJSONObject: discordJSON)
  host.registerHTTPResponse(status: 200, body: discordData)

  let harness = PluginHarness(WebhookUploadPlugin.self, host: host)
  let result = try await harness.execute("upload")

  #expect(result.isSuccess)
  let stored = host.getSecret(key: "webhookURL")
  #expect(stored == "https://discord.com/api/webhooks/999/xyz")
}
