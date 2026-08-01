//
//  RemoteOCRService.swift
//  Snapzy
//
//  OpenAI-compatible chat-completions OCR provider for custom endpoints.
//

import AppKit
import Foundation

/// Errors surfaced by `RemoteOCRProvider` with user-facing descriptions.
enum RemoteOCRError: LocalizedError, Equatable {
  case invalidBaseURL
  case imageEncodingFailed
  case unauthorized
  case httpStatus(Int, String)
  case invalidResponse
  case unreachable(URLError)

  var errorDescription: String? {
    switch self {
    case .invalidBaseURL:
      return L10n.OCR.remoteErrorInvalidBaseURL
    case .imageEncodingFailed:
      return L10n.OCR.remoteErrorImageEncodingFailed
    case .unauthorized:
      return L10n.OCR.remoteErrorUnauthorized
    case .httpStatus(let statusCode, let snippet):
      let base = L10n.OCR.remoteErrorHTTPStatus(statusCode)
      return snippet.isEmpty ? base : "\(base): \(snippet)"
    case .invalidResponse:
      return L10n.OCR.remoteErrorInvalidResponse
    case .unreachable(let error):
      return L10n.OCR.remoteErrorUnreachable(error.localizedDescription)
    }
  }
}

/// `OCRProvider` posting base64 JPEG images to a user-configured
/// OpenAI-compatible `chat/completions` endpoint.
struct RemoteOCRProvider: OCRProvider {
  let engine: OCREngine = .remote

  private let model: CustomOCRModel
  private let keychainStore: OCRKeychainStoring
  private let session: URLSessionProtocol
  private let timeout: TimeInterval

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

  func recognize(_ request: OCRRequest) async throws -> OCRResult {
    let content = try await performCompletion(image: request.image, prompt: resolvedPrompt(for: request.contentType))
    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw RemoteOCRError.invalidResponse
    }
    // Remote completions carry no line geometry or confidence; downstream
    // consumers only read `text`.
    return OCRResult(engine: .remote, profileID: model.id.uuidString, text: content, lines: [], averageConfidence: 1)
  }

  /// Probes the endpoint with a tiny generated image and measures latency.
  /// Some servers answer blank images with empty completions, so any
  /// well-formed chat-completion response — even with empty content — counts
  /// as success; only transport, HTTP, and parse errors fail the test.
  func testConnection() async -> Result<TimeInterval, Error> {
    let start = Date()
    do {
      guard let probeImage = Self.makeProbeImage() else {
        throw RemoteOCRError.imageEncodingFailed
      }
      _ = try await performCompletion(image: probeImage, prompt: resolvedPrompt(for: .interfaceText))
      return .success(Date().timeIntervalSince(start))
    } catch {
      return .failure(error)
    }
  }

  // MARK: - Request

  @discardableResult
  private func performCompletion(image: CGImage, prompt: String) async throws -> String {
    guard let endpoint = Self.endpointURL(forBaseURL: model.baseURL) else {
      throw RemoteOCRError.invalidBaseURL
    }
    guard let jpegData = Self.jpegData(from: image) else {
      throw RemoteOCRError.imageEncodingFailed
    }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let apiKey = keychainStore.readKey(for: model.id), !apiKey.isEmpty {
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
    request.httpBody = try JSONEncoder().encode(ChatCompletionRequest(
      model: model.modelIdentifier,
      messages: [ChatCompletionMessage(role: "user", content: [
        .text(prompt),
        .imageURL("data:image/jpeg;base64,\(jpegData.base64EncodedString())"),
      ])]
    ))

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
      break
    case 401, 403:
      throw RemoteOCRError.unauthorized
    default:
      throw RemoteOCRError.httpStatus(httpResponse.statusCode, Self.bodySnippet(from: data))
    }

    guard let chatResponse = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data),
          let content = chatResponse.choices.first?.message.content else {
      throw RemoteOCRError.invalidResponse
    }
    return content.text
  }

  // MARK: - Helpers

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

  static func defaultPrompt(for contentType: OCRContentType) -> String {
    switch contentType {
    case .interfaceText:
      return "Extract all text from this image exactly as it appears, preserving the original layout and line breaks. Output only the extracted text, with no commentary."
    case .denseDocument:
      return "Transcribe all text in this document image, preserving paragraph structure and reading order. Output only the transcribed text, with no commentary."
    case .code:
      return "Output only the raw code shown in this image, exactly as written, with no explanation and no markdown formatting."
    }
  }

  private func resolvedPrompt(for contentType: OCRContentType) -> String {
    guard let prompt = model.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty else {
      return Self.defaultPrompt(for: contentType)
    }
    return prompt
  }

  private static func jpegData(from image: CGImage) -> Data? {
    NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.9])
  }

  private static func makeProbeImage() -> CGImage? {
    let size = 8
    guard let context = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    return context.makeImage()
  }

  private static func bodySnippet(from data: Data, limit: Int = 200) -> String {
    String(data: data.prefix(limit), encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }
}
