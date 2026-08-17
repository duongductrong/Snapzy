import Foundation
import PluginKitCore
import Testing
@testable import SnapzyPluginAPI

@Suite("SnapzyPluginAPI vocabulary")
struct SnapzyPluginAPITests {
  private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(T.self, from: data)
  }

  @Test("request/response round-trip")
  func requestResponseRoundTrip() throws {
    let request = SnapzyCommandRequest(
      invocationID: UUID(),
      surface: .annotate,
      documentKind: .annotateSession,
      document: .annotate(
        AnnotateDocument(
          size: SnapzySize(width: 800, height: 600),
          items: [
            AnnotateDocItem(
              id: "item-1", kind: "text",
              rect: SnapzyRect(x: 1, y: 2, width: 3, height: 4),
              text: "你好", style: AnnotateDocStyle(strokeColor: SnapzyColor(red: 1, green: 0, blue: 0))
            ),
          ]
        )
      ),
      selection: ["item-1"],
      options: .object(["target": .string("en")])
    )
    let decoded = try roundTrip(request)
    #expect(decoded.invocationID == request.invocationID)
    #expect(decoded.surface == .annotate)
    #expect(decoded.document == request.document)
    #expect(decoded.selection == ["item-1"])

    let response = SnapzyCommandResponse(
      outcome: .patch([
        .addItem(
          AnnotateDocItem(id: "x", kind: "rect", rect: SnapzyRect(x: 0, y: 0, width: 10, height: 10))
        ),
        .removeItem(id: "item-1"),
        .setCrop(SnapzyRect(x: 5, y: 5, width: 100, height: 100)),
      ])
    )
    #expect(try roundTrip(response).outcome == response.outcome)
  }

  @Test("unknown document edit kinds fail loudly, unknown item kinds tolerate")
  func forwardCompatibility() throws {
    // Unknown item kind strings decode and are preserved.
    let itemJSON = """
      {"id":"a","kind":"future-kind","rect":{"x":0,"y":0,"width":5,"height":5},"zIndex":0}
      """
    let item = try JSONDecoder().decode(AnnotateDocItem.self, from: Data(itemJSON.utf8))
    #expect(item.kind == "future-kind")

    // Unknown *edit* op kinds fail: the host must never guess at mutation.
    let editJSON = """
      {"kind":"futureEdit","id":"a"}
      """
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(DocumentEdit.self, from: Data(editJSON.utf8))
    }
  }

  @Test("network scope attenuation never grants wildcard verbatim")
  func networkAttenuation() {
    let wildcard = SnapzyNetworkAccess.Scope(hosts: ["*"])
    #expect(wildcard.attenuated(to: .unrestricted) == nil)
    #expect(wildcard.attenuated(to: .init(hosts: ["api.openai.com"])) == .init(hosts: ["api.openai.com"]))

    let specific = SnapzyNetworkAccess.Scope(hosts: ["api.openai.com"])
    #expect(specific.attenuated(to: .unrestricted) == specific)
    #expect(specific.attenuated(to: .init(hosts: ["api.openai.com", "other.com"])) == specific)
    #expect(specific.attenuated(to: .init(hosts: ["other.com"])) == nil)
  }

  @Test("host policy narrows wildcard network requests")
  func hostWildcardPolicy() {
    #expect(
      SnapzyCapabilityPolicy.effectiveNetworkScope(requestedHosts: ["*"], policyLimit: nil) == nil
    )
    #expect(
      SnapzyCapabilityPolicy.effectiveNetworkScope(
        requestedHosts: ["*"], policyLimit: ["api.openai.com"]
      ) == ["api.openai.com"]
    )
    #expect(
      SnapzyCapabilityPolicy.effectiveNetworkScope(
        requestedHosts: ["api.openai.com", "evil.com"], policyLimit: ["api.openai.com"]
      ) == ["api.openai.com"]
    )
  }

  @Test("asset read scope attenuation")
  func assetScopeAttenuation() {
    let scope = SnapzyAssetRead.Scope(kinds: [.screenshot, .gif])
    #expect(
      scope.attenuated(to: .init(kinds: [.screenshot])) == .init(kinds: [.screenshot])
    )
    #expect(scope.attenuated(to: .init(kinds: [.video])) == nil)
  }

  @Test("UI request round-trip")
  func uiRoundTrip() throws {
    let request = PluginUIRequest.form(
      PluginUIForm(
        title: "Settings",
        fields: [
          PluginUIFormField(name: "endpoint", label: "Endpoint", kind: "url", required: true),
          PluginUIFormField(
            name: "model", label: "Model", kind: "enum",
            defaultValue: .string("gpt-4o"), options: ["gpt-4o", "gpt-4o-mini"]
          ),
        ]
      )
    )
    let decoded = try roundTrip(request)
    #expect(decoded == request)

    let result = PluginUIResult.submitted(.object(["endpoint": .string("https://x")]))
    #expect(try roundTrip(result) == result)
  }
}
