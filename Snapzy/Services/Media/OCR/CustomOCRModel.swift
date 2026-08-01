//
//  CustomOCRModel.swift
//  Snapzy
//
//  User-defined OpenAI-compatible OCR endpoint configuration.
//

import Foundation

/// A user-added remote OCR endpoint speaking the OpenAI chat-completions
/// protocol (LLM APIs, Ollama, vLLM, LM Studio, self-hosted servers).
///
/// The API key itself never appears here — it lives in the Keychain via
/// `OCRKeychainStore`, keyed by `id`. `hasAPIKey` is a display hint only.
///
/// The JSON encoding keeps the `"id"` key: the Phase 1 availability checker
/// (`UserDefaultsOCRModelAvailability`) decodes stored models by `id`.
struct CustomOCRModel: Codable, Equatable, Identifiable {
  var id: UUID
  var name: String
  /// Base URL as entered by the user, e.g. `https://api.openai.com` or
  /// `http://localhost:11434/v1`. Normalized by `RemoteOCRProvider`.
  var baseURL: String
  /// Provider-side model name sent as the `"model"` field, e.g. `gpt-4o-mini`.
  var modelIdentifier: String
  /// Optional user prompt override; `nil`/empty falls back to the per
  /// content-type default in `RemoteOCRProvider`.
  var prompt: String?
  var hasAPIKey: Bool
  var createdAt: Date
  var updatedAt: Date

  init(
    id: UUID = UUID(),
    name: String,
    baseURL: String,
    modelIdentifier: String,
    prompt: String? = nil,
    hasAPIKey: Bool = false,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.baseURL = baseURL
    self.modelIdentifier = modelIdentifier
    self.prompt = prompt
    self.hasAPIKey = hasAPIKey
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  /// Tolerant decoding for hand-authored TOML configs: only the endpoint
  /// identity fields are required; flags and timestamps get defaults.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    baseURL = try container.decode(String.self, forKey: .baseURL)
    modelIdentifier = try container.decode(String.self, forKey: .modelIdentifier)
    prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
    hasAPIKey = try container.decodeIfPresent(Bool.self, forKey: .hasAPIKey) ?? false
    createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
  }
}
