//
//  RemoteTranslationProvider.swift
//  Snapzy
//
//  Translates text through a custom OpenAI-compatible endpoint.
//

import Foundation

struct RemoteTranslationProvider {
  private let client: OpenAICompatibleChatClient

  init(
    model: CustomOCRModel,
    keychainStore: OCRKeychainStoring = OCRKeychainStore(),
    session: URLSessionProtocol = URLSession.shared,
    timeout: TimeInterval = 60
  ) {
    client = OpenAICompatibleChatClient(
      model: model,
      keychainStore: keychainStore,
      session: session,
      timeout: timeout
    )
  }

  func translate(_ text: String, to target: TranslationLanguage) async throws -> String {
    let content = try await client.complete(messages: [
      ChatCompletionMessage(role: "user", content: [.text(Self.prompt(text: text, target: target))]),
    ])
    let translated = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !translated.isEmpty else {
      throw RemoteOCRError.invalidResponse
    }
    return translated
  }

  /// One user message (instruction + text): some OpenAI-compatible servers
  /// reject system messages or array content on the system role.
  static func prompt(text: String, target: TranslationLanguage) -> String {
    """
    Translate the text between <text> tags into \(target.englishName) (\(target.identifier)). \
    Keep the original line breaks and paragraph structure. \
    Output only the translation, with no explanation, no quotes, and no tags.

    <text>
    \(text)
    </text>
    """
  }
}
