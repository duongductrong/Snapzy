//
//  TranslationTests.swift
//  SnapzyTests
//
//  Snip to Translate core: engine resolution, line segmentation, remote provider.
//

import XCTest
@testable import Snapzy

@MainActor
final class TranslationEngineResolverTests: XCTestCase {
  private func makeModel(id: UUID = UUID()) -> CustomOCRModel {
    CustomOCRModel(id: id, name: "Endpoint", baseURL: "https://api.example.com", modelIdentifier: "m")
  }

  private func store(_ models: [CustomOCRModel], in defaults: UserDefaults) throws {
    defaults.set(try JSONEncoder().encode(models), forKey: PreferencesKeys.ocrCustomModels)
  }

  func testDefaultsToAppleOnSupportedSystem() {
    let resolver = TranslationEngineResolver(defaults: UserDefaultsFactory.make(), isAppleTranslationSupported: true)
    XCTAssertEqual(resolver.storedSelection(), .builtIn)
    XCTAssertEqual(resolver.resolve(), .apple)
  }

  func testAppleUnavailableBeforeMacOS15() {
    let resolver = TranslationEngineResolver(defaults: UserDefaultsFactory.make(), isAppleTranslationSupported: false)
    XCTAssertEqual(resolver.resolve(), .unavailable(.requiresMacOS15))
  }

  func testAppleUnavailableDoesNotFallBackToEndpoint() throws {
    let defaults = UserDefaultsFactory.make()
    try store([makeModel()], in: defaults)
    let resolver = TranslationEngineResolver(defaults: defaults, isAppleTranslationSupported: false)
    XCTAssertEqual(resolver.resolve(), .unavailable(.requiresMacOS15))
    XCTAssertNotNil(resolver.firstAvailableEndpoint())
  }

  func testCustomSelectionResolvesToEndpointOnAnySystem() throws {
    let defaults = UserDefaultsFactory.make()
    let model = makeModel()
    try store([model], in: defaults)
    let resolver = TranslationEngineResolver(defaults: defaults, isAppleTranslationSupported: false)
    resolver.store(.custom(model.id))
    XCTAssertEqual(resolver.resolve(), .remote(model))
  }

  func testMissingEndpointCanonicalizesToBuiltIn() {
    let defaults = UserDefaultsFactory.make()
    let resolver = TranslationEngineResolver(defaults: defaults, isAppleTranslationSupported: true)
    resolver.store(.custom(UUID()))
    XCTAssertEqual(resolver.resolve(), .apple)
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.translateSelectedEngine), "builtin")
  }

  func testTargetLanguageUnsetUntilChosen() {
    let defaults = UserDefaultsFactory.make()
    XCTAssertNil(TranslationLanguage.storedTarget(defaults: defaults))
    TranslationLanguage.storeTarget(TranslationLanguage(identifier: "vi"), defaults: defaults)
    XCTAssertEqual(TranslationLanguage.storedTarget(defaults: defaults)?.identifier, "vi")
  }

  func testUnknownStoredTargetReadsAsUnset() {
    let defaults = UserDefaultsFactory.make()
    defaults.set("xx-unknown", forKey: PreferencesKeys.translateTargetLanguage)
    XCTAssertNil(TranslationLanguage.storedTarget(defaults: defaults))
  }
}

final class TranslationTextSegmentsTests: XCTestCase {
  func testKeepsParagraphAndLineLayout() {
    let segments = TranslationTextSegments(text: "First paragraph.\n\nItem one\nItem two")
    XCTAssertEqual(segments.translatableTexts, ["First paragraph.", "Item one", "Item two"])
    XCTAssertEqual(segments.rebuilt(with: ["A", "B", "C"]), "A\n\nB\nC")
  }

  func testTrimsLinesAndNormalizesCRLF() {
    let segments = TranslationTextSegments(text: "  Hello \r\n\r\n World")
    XCTAssertEqual(segments.translatableTexts, ["Hello", "World"])
    XCTAssertEqual(segments.rebuilt(with: ["Xin chào", "Thế giới"]), "Xin chào\n\nThế giới")
  }

  func testMissingTranslationsKeepOriginalLines() {
    let segments = TranslationTextSegments(text: "One\nTwo")
    XCTAssertEqual(segments.rebuilt(with: ["Một"]), "Một\nTwo")
  }

  func testWhitespaceOnlyIsEmpty() {
    XCTAssertTrue(TranslationTextSegments(text: " \n\n ").isEmpty)
    XCTAssertTrue(TranslationTextSegments(text: "").isEmpty)
  }
}

final class RemoteTranslationProviderTests: XCTestCase {
  private let model = CustomOCRModel(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000077")!,
    name: "Endpoint",
    baseURL: "https://api.example.com/v1",
    modelIdentifier: "gpt-test"
  )

  private func completion(_ content: String) -> Data {
    try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
  }

  func testSendsTextOnlyPromptWithTargetLanguage() async throws {
    let session = MockURLSession { _ in MockURLSession.makeResponse(statusCode: 200, data: self.completion(" Xin chào \n")) }
    let provider = RemoteTranslationProvider(model: model, keychainStore: FakeOCRKeychainStore(), session: session)

    let output = try await provider.translate("Hello", to: TranslationLanguage(identifier: "vi"))

    XCTAssertEqual(output, "Xin chào")
    let request = try XCTUnwrap(session.requests.first)
    XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/chat/completions")
    let body = try XCTUnwrap(request.httpBody)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(json["model"] as? String, "gpt-test")
    let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
    XCTAssertEqual(messages.count, 1)
    let parts = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
    XCTAssertEqual(parts.count, 1, "text only, no image part")
    let prompt = try XCTUnwrap(parts[0]["text"] as? String)
    XCTAssertTrue(prompt.contains("Vietnamese"))
    XCTAssertTrue(prompt.contains("<text>\nHello\n</text>"))
  }

  func testEmptyCompletionIsInvalidResponse() async {
    let session = MockURLSession { _ in MockURLSession.makeResponse(statusCode: 200, data: self.completion("  ")) }
    let provider = RemoteTranslationProvider(model: model, keychainStore: FakeOCRKeychainStore(), session: session)
    do {
      _ = try await provider.translate("Hello", to: TranslationLanguage(identifier: "vi"))
      XCTFail("expected error")
    } catch {
      XCTAssertEqual(error as? RemoteOCRError, .invalidResponse)
    }
  }

  func testUnauthorizedMapsToTypedError() async {
    let session = MockURLSession { _ in MockURLSession.makeResponse(statusCode: 401) }
    let provider = RemoteTranslationProvider(model: model, keychainStore: FakeOCRKeychainStore(), session: session)
    do {
      _ = try await provider.translate("Hello", to: TranslationLanguage(identifier: "vi"))
      XCTFail("expected error")
    } catch {
      XCTAssertEqual(error as? RemoteOCRError, .unauthorized)
    }
  }
}
