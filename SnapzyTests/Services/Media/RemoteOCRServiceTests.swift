//
//  RemoteOCRServiceTests.swift
//  SnapzyTests
//
//  RemoteOCRProvider URL normalization, payload, parsing, and error mapping.
//

import XCTest
@testable import Snapzy

final class RemoteOCRServiceTests: XCTestCase {
  private var keychain: FakeOCRKeychainStore!
  private let modelID = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!

  override func setUp() {
    super.setUp()
    keychain = FakeOCRKeychainStore()
  }

  private func makeModel(
    baseURL: String = "https://api.example.com",
    prompt: String? = nil
  ) -> CustomOCRModel {
    CustomOCRModel(
      id: modelID,
      name: "Test Model",
      baseURL: baseURL,
      modelIdentifier: "test-model",
      prompt: prompt
    )
  }

  private func completionData(content: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
  }

  private func makeImage() -> CGImage {
    TestImageFactory.solidColor(width: 16, height: 16)!
  }

  private func makeProvider(
    model: CustomOCRModel? = nil,
    session: MockURLSession
  ) -> RemoteOCRProvider {
    RemoteOCRProvider(model: model ?? makeModel(), keychainStore: keychain, session: session)
  }

  private func makeSession(
    statusCode: Int = 200,
    data: Data? = nil
  ) -> MockURLSession {
    MockURLSession { _ in
      MockURLSession.makeResponse(statusCode: statusCode, data: data ?? self.completionData(content: "ok"))
    }
  }

  // MARK: - URL normalization

  func testEndpointURLNormalizationVariants() {
    let cases: [(String, String?)] = [
      ("https://api.openai.com", "https://api.openai.com/v1/chat/completions"),
      ("https://api.openai.com/", "https://api.openai.com/v1/chat/completions"),
      ("  https://api.openai.com  ", "https://api.openai.com/v1/chat/completions"),
      ("http://localhost:11434/v1", "http://localhost:11434/v1/chat/completions"),
      ("http://localhost:11434/v1/", "http://localhost:11434/v1/chat/completions"),
      ("https://x.test/v1/chat/completions", "https://x.test/v1/chat/completions"),
      ("https://x.test/v1/chat/completions/", "https://x.test/v1/chat/completions"),
      ("", nil),
      ("   ", nil),
    ]

    for (input, expected) in cases {
      XCTAssertEqual(RemoteOCRProvider.endpointURL(forBaseURL: input)?.absoluteString, expected, input)
    }
  }

  // MARK: - Payload construction

  func testPayloadContainsModelPromptImageAndHeaders() async throws {
    let session = makeSession(data: completionData(content: "hello"))
    let provider = makeProvider(session: session)

    let result = try await provider.recognize(OCRRequest(image: makeImage()))

    XCTAssertEqual(result.text, "hello")
    XCTAssertEqual(result.engine, .remote)
    XCTAssertEqual(result.profileID, modelID.uuidString)
    XCTAssertTrue(result.lines.isEmpty)
    XCTAssertEqual(result.averageConfidence, 1)

    let request = try XCTUnwrap(session.requests.first)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/chat/completions")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    XCTAssertEqual(request.timeoutInterval, 60, accuracy: 0.001)

    let body = try XCTUnwrap(request.httpBody)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(json["model"] as? String, "test-model")

    let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
    let message = try XCTUnwrap(messages.first)
    XCTAssertEqual(message["role"] as? String, "user")

    let content = try XCTUnwrap(message["content"] as? [[String: Any]])
    XCTAssertEqual(content.count, 2)
    XCTAssertEqual(content[0]["type"] as? String, "text")
    XCTAssertEqual(content[0]["text"] as? String, RemoteOCRProvider.defaultPrompt(for: .interfaceText))
    XCTAssertEqual(content[1]["type"] as? String, "image_url")
    let imageURL = try XCTUnwrap(content[1]["image_url"] as? [String: Any])
    XCTAssertTrue((imageURL["url"] as? String)?.hasPrefix("data:image/jpeg;base64,") == true)
  }

  func testDefaultPromptVariesPerContentType() async throws {
    for contentType in [OCRContentType.interfaceText, .denseDocument, .code] {
      let session = makeSession()
      let provider = makeProvider(session: session)

      _ = try await provider.recognize(OCRRequest(image: makeImage(), contentType: contentType))

      let textPart = try XCTUnwrap(firstTextPart(from: session))
      XCTAssertEqual(textPart, RemoteOCRProvider.defaultPrompt(for: contentType), contentType.rawValue)
    }
  }

  func testCustomPromptOverridesDefault() async throws {
    let session = makeSession()
    let provider = makeProvider(model: makeModel(prompt: "Read only the headings."), session: session)

    _ = try await provider.recognize(OCRRequest(image: makeImage(), contentType: .code))

    let textPart = try XCTUnwrap(firstTextPart(from: session))
    XCTAssertEqual(textPart, "Read only the headings.")
  }

  func testWhitespaceOnlyPromptFallsBackToDefault() async throws {
    let session = makeSession()
    let provider = makeProvider(model: makeModel(prompt: "   \n"), session: session)

    _ = try await provider.recognize(OCRRequest(image: makeImage(), contentType: .denseDocument))

    let textPart = try XCTUnwrap(firstTextPart(from: session))
    XCTAssertEqual(textPart, RemoteOCRProvider.defaultPrompt(for: .denseDocument))
  }

  // MARK: - Auth header

  func testAuthorizationHeaderIncludedWhenKeyExists() async throws {
    keychain.seedKey("sk-live", for: modelID)
    let session = makeSession()
    let provider = makeProvider(session: session)

    _ = try await provider.recognize(OCRRequest(image: makeImage()))

    let request = try XCTUnwrap(session.requests.first)
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-live")
  }

  func testAuthorizationHeaderOmittedWithoutKey() async throws {
    let session = makeSession()
    let provider = makeProvider(session: session)

    _ = try await provider.recognize(OCRRequest(image: makeImage()))

    let request = try XCTUnwrap(session.requests.first)
    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
  }

  // MARK: - Error mapping

  func testUnauthorizedMapsToTypedError() async {
    await assertRecognizeFails(statusCode: 401, expectedError: .unauthorized)
    await assertRecognizeFails(statusCode: 403, expectedError: .unauthorized)
  }

  func testHTTPErrorIncludesStatusAndBodySnippet() async {
    let body = Data(#"{"error":"boom"}"#.utf8)
    await assertRecognizeFails(
      statusCode: 500,
      data: body,
      expectedError: .httpStatus(500, #"{"error":"boom"}"#)
    )
  }

  func testTransportErrorMapsToUnreachable() async {
    let session = MockURLSession { _ in
      throw URLError(.notConnectedToInternet)
    }
    let provider = makeProvider(session: session)

    do {
      _ = try await provider.recognize(OCRRequest(image: makeImage()))
      XCTFail("expected unreachable error")
    } catch let error as RemoteOCRError {
      XCTAssertEqual(error, .unreachable(URLError(.notConnectedToInternet)))
    } catch {
      XCTFail("unexpected error: \(error)")
    }
  }

  func testInvalidBaseURLThrowsTypedError() async {
    let session = makeSession()
    let provider = makeProvider(model: makeModel(baseURL: "   "), session: session)

    do {
      _ = try await provider.recognize(OCRRequest(image: makeImage()))
      XCTFail("expected invalidBaseURL error")
    } catch let error as RemoteOCRError {
      XCTAssertEqual(error, .invalidBaseURL)
    } catch {
      XCTFail("unexpected error: \(error)")
    }
    XCTAssertTrue(session.requests.isEmpty)
  }

  // MARK: - Response parsing

  func testStringContentParses() async throws {
    let session = makeSession(data: completionData(content: "line one\nline two"))
    let provider = makeProvider(session: session)

    let result = try await provider.recognize(OCRRequest(image: makeImage()))

    XCTAssertEqual(result.text, "line one\nline two")
  }

  func testArrayPartsContentParses() async throws {
    let parts: [[String: Any]] = [
      ["type": "text", "text": "Hello "],
      ["type": "text", "text": "world"],
    ]
    let session = makeSession(data: completionData(content: parts))
    let provider = makeProvider(session: session)

    let result = try await provider.recognize(OCRRequest(image: makeImage()))

    XCTAssertEqual(result.text, "Hello world")
  }

  func testEmptyContentThrowsInvalidResponse() async {
    await assertRecognizeFails(data: completionData(content: ""), expectedError: .invalidResponse)
    await assertRecognizeFails(data: completionData(content: "  \n "), expectedError: .invalidResponse)
  }

  func testMalformedJSONThrowsInvalidResponse() async {
    await assertRecognizeFails(data: Data("not json".utf8), expectedError: .invalidResponse)
    await assertRecognizeFails(data: Data("{}".utf8), expectedError: .invalidResponse)
  }

  // MARK: - Connection test

  /// Blank probe images may legitimately yield empty completions — a
  /// well-formed response still proves reachability, auth, and parseability.
  func testConnectionSucceedsWithWellFormedEmptyContent() async {
    let session = makeSession(data: completionData(content: ""))
    let provider = makeProvider(session: session)

    let result = await provider.testConnection()

    guard case .success(let latency) = result else {
      XCTFail("expected success, got \(result)")
      return
    }
    XCTAssertGreaterThanOrEqual(latency, 0)
    XCTAssertEqual(session.requests.count, 1)
  }

  func testConnectionFailsOnUnauthorized() async {
    let session = makeSession(statusCode: 401)
    let provider = makeProvider(session: session)

    let result = await provider.testConnection()

    guard case .failure(let error) = result else {
      XCTFail("expected failure, got \(result)")
      return
    }
    XCTAssertEqual(error as? RemoteOCRError, .unauthorized)
  }

  // MARK: - Helpers

  private func firstTextPart(from session: MockURLSession) throws -> String? {
    let request = try XCTUnwrap(session.requests.first)
    let body = try XCTUnwrap(request.httpBody)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
    let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
    return content.first?["text"] as? String
  }

  private func assertRecognizeFails(
    statusCode: Int = 200,
    data: Data = Data(),
    expectedError: RemoteOCRError,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    let session = makeSession(statusCode: statusCode, data: data)
    let provider = makeProvider(session: session)

    do {
      _ = try await provider.recognize(OCRRequest(image: makeImage()))
      XCTFail("expected \(expectedError)", file: file, line: line)
    } catch let error as RemoteOCRError {
      XCTAssertEqual(error, expectedError, file: file, line: line)
    } catch {
      XCTFail("unexpected error: \(error)", file: file, line: line)
    }
  }
}
