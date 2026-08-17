import Foundation
import PluginKitCore
import SnapzyPluginAPI
import SnapzyPluginSDK
import SnapzyPluginTesting
import Testing

// Sample Word Count Plugin
struct WordCountPlugin: SnapzyPlugin {
  init() {}

  func activate(_ context: SnapzyPluginContext) async throws {
    context.command("count") { request, ctx in
      let image = try await ctx.asset.read()
      let ocrResult = try await ctx.ocr.recognize(image)
      try Task.checkCancellation()
      let wordCount = ocrResult.text.split(whereSeparator: \.isWhitespace).count
      return .text("\(wordCount) words")
    }
  }
}

// Sample Translate Plugin mockup
struct MockTranslatePlugin: SnapzyPlugin {
  init() {}

  func activate(_ context: SnapzyPluginContext) async throws {
    context.command("translate") { request, ctx in
      let image = try await ctx.asset.read()
      let ocrResult = try await ctx.ocr.recognize(image)
      let orderedLines = inReadingOrder(ocrResult.lines)
      var edits: [DocumentEdit] = []
      for line in orderedLines {
        let item = textItem(
          id: stableID(line.text),
          rect: line.box,
          text: "Translated: \(line.text)"
        )
        edits.append(addItem(item))
      }
      return .patch(edits)
    }
  }
}

@Suite struct PluginSDKTests {
  @Test func wordCountPluginRunsUnderHarness() async throws {
    let host = FakeHost()
    let fixtureData = Data("test-image-bytes".utf8)
    host.stubAsset(fixtureData)
    host.stubOCR(lines: ["Hello world from", "Snapzy native plugin SDK"])

    let harness = PluginHarness(WordCountPlugin.self, host: host)
    let outcome = try await harness.invoke("count")

    #expect(outcome == .text("7 words"))
    #expect(host.calls.map(\.service) == ["asset.read", "ocr.recognize"])
  }

  @Test func mockTranslatePluginGeneratesEdits() async throws {
    let host = FakeHost()
    host.stubAsset(Data("img".utf8))
    host.stubOCR(lines: ["First line", "Second line"])

    let harness = PluginHarness(MockTranslatePlugin.self, host: host)
    let outcome = try await harness.invoke("translate")

    guard case .patch(let edits) = outcome else {
      Issue.record("Expected .patch outcome")
      return
    }
    #expect(edits.count == 2)
    #expect(host.calls.map(\.service) == ["asset.read", "ocr.recognize"])
  }

  @Test func textItemAndFitFontSize() {
    let rect = SnapzyRect(x: 0, y: 0, width: 100, height: 40)
    let item = textItem(id: "t1", rect: rect, text: "Sample")
    #expect(item.id == "t1")
    #expect(item.kind == "text")
    #expect(item.style.fontSize != nil)

    let size = fitFontSize("Short", in: rect)
    #expect(size > 8)
  }

  @Test func inReadingOrderSorting() {
    let line1 = PluginOCRLine(text: "Bottom", box: SnapzyRect(x: 10, y: 100, width: 50, height: 20), confidence: 1.0)
    let line2 = PluginOCRLine(text: "Top Right", box: SnapzyRect(x: 60, y: 10, width: 50, height: 20), confidence: 1.0)
    let line3 = PluginOCRLine(text: "Top Left", box: SnapzyRect(x: 10, y: 10, width: 50, height: 20), confidence: 1.0)

    let sorted = inReadingOrder([line1, line2, line3])
    #expect(sorted.map(\.text) == ["Top Left", "Top Right", "Bottom"])
  }

  @Test func stableIDIsDeterministic() {
    let id1 = stableID("hello")
    let id2 = stableID("hello")
    let id3 = stableID("world")
    #expect(id1 == id2)
    #expect(id1 != id3)
  }

  @Test func manifestAuthoringRoundTrip() throws {
    let builder = SnapzyManifestBuilder(
      id: "com.snapzy.test",
      version: "1.0.0",
      displayName: "Test Plugin",
      executable: "TestPlugin"
    )
    let json = try builder.emitJSON()
    let decoded = try JSONDecoder().decode(PluginManifest.self, from: json)
    #expect(decoded.id == PluginID("com.snapzy.test"))
    #expect(decoded.displayName == "Test Plugin")
    #expect(decoded.runtime == .custom(
      RuntimeID("process"),
      options: ["executable": .string("TestPlugin"), "protocolVersion": .string("1.0.0")]
    ))
  }

  @Test func storageAndSecretsFacade() async throws {
    struct StorageSecretsPlugin: SnapzyPlugin {
      init() {}
      func activate(_ context: SnapzyPluginContext) async throws {
        context.command("store") { request, ctx in
          try await ctx.storage.set("myKey", "myValue")
          let val = try await ctx.storage.get("myKey")
          try await ctx.secrets.set("mySecret", "secret123")
          let secret = try await ctx.secrets.get("mySecret")
          try await ctx.notify.post(title: "Done", body: "Stored")
          return .text("val: \(val ?? "nil"), secret: \(secret ?? "nil")")
        }
      }
    }

    let host = FakeHost()
    let harness = PluginHarness(StorageSecretsPlugin.self, host: host)
    let outcome = try await harness.invoke("store")
    #expect(outcome == .text("val: myValue, secret: secret123"))
    #expect(host.assertCalled(service: "storage.set"))
    #expect(host.assertCalled(service: "storage.get"))
    #expect(host.assertCalled(service: "secrets.set"))
    #expect(host.assertCalled(service: "secrets.get"))
    #expect(host.assertCalled(service: "notify.post"))
  }

  @Test func httpFacade() async throws {
    struct HTTPPlugin: SnapzyPlugin {
      init() {}
      func activate(_ context: SnapzyPluginContext) async throws {
        context.command("fetch") { request, ctx in
          let resp = try await ctx.http.fetch(url: "https://api.example.com/data")
          let text = String(data: resp.body, encoding: .utf8) ?? ""
          return .text("status: \(resp.status), body: \(text)")
        }
      }
    }

    let host = FakeHost()
    host.stubHTTP(status: 200, body: Data("mocked-body".utf8))
    let harness = PluginHarness(HTTPPlugin.self, host: host)
    let outcome = try await harness.invoke("fetch")
    #expect(outcome == .text("status: 200, body: mocked-body"))
    #expect(host.assertCalled(service: "http.fetch"))
  }
}
