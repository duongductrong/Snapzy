//
//  OpenAICompatibleChatClient.swift
//  Snapzy
//
//  Shared transport for user-configured OpenAI-compatible chat-completions
//  endpoints (custom OCR and translation).
//

import Foundation

/// Posts chat-completions requests to a `CustomOCRModel` endpoint. `complete`
/// returns the first choice's text; `send` returns the raw body. Maps
/// transport/HTTP failures to `RemoteOCRError`.
struct OpenAICompatibleChatClient {
  let model: CustomOCRModel
  let keychainStore: OCRKeychainStoring
  let session: URLSessionProtocol
  let timeout: TimeInterval

  init(
    model: CustomOCRModel,
    keychainStore: OCRKeychainStoring = OCRKeychainStore(),
    session: URLSessionProtocol = URLSession.shared,
    timeout: TimeInterval = 60
  ) {
    self.model = model
    self.keychainStore = keychainStore
    self.session = session
    self.timeout = timeout
  }

  func complete(messages: [ChatCompletionMessage]) async throws -> String {
    let body = try JSONEncoder().encode(ChatCompletionRequest(
      model: model.modelIdentifier,
      messages: messages
    ))
    let data = try await send(jsonBody: body)
    guard let chatResponse = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data),
          let content = chatResponse.choices.first?.message.content else {
      throw RemoteOCRError.invalidResponse
    }
    return content.text
  }

  /// Posts an already-encoded chat-completions body and returns the raw response
  /// body of a 2xx answer. For callers that need more than the first choice's text
  /// (tool calls in the Annotate AI prompt).
  func send(jsonBody: Data) async throws -> Data {
    guard let endpoint = Self.endpointURL(forBaseURL: model.baseURL) else {
      throw RemoteOCRError.invalidBaseURL
    }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let apiKey = keychainStore.readKey(for: model.id), !apiKey.isEmpty {
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
    request.httpBody = jsonBody

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch let error as URLError {
      throw RemoteOCRError.unreachable(error)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw RemoteOCRError.invalidResponse
    }
    switch httpResponse.statusCode {
    case 200...299:
      return data
    case 401, 403:
      throw RemoteOCRError.unauthorized
    default:
      throw RemoteOCRError.httpStatus(httpResponse.statusCode, Self.bodySnippet(from: data))
    }
  }

  /// Normalizes the user-entered base URL: trims whitespace and trailing
  /// slashes, keeps an explicit `/chat/completions` suffix, appends
  /// `/chat/completions` to a `/v1` base, else appends `/v1/chat/completions`.
  static func endpointURL(forBaseURL baseURL: String) -> URL? {
    var normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    while normalized.hasSuffix("/") { normalized.removeLast() }
    guard !normalized.isEmpty else { return nil }
    if normalized.hasSuffix("/chat/completions") {
      return URL(string: normalized)
    }
    if normalized.hasSuffix("/v1") {
      return URL(string: normalized + "/chat/completions")
    }
    return URL(string: normalized + "/v1/chat/completions")
  }

  private static func bodySnippet(from data: Data, limit: Int = 200) -> String {
    String(data: data.prefix(limit), encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }
}
