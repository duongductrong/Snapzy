//
//  RemoteTranslationProvider.swift
//  Snapzy
//
//  Translates text through a remote engine: a custom OpenAI-compatible endpoint
//  or an agent CLI.
//

import Foundation

/// Sends one prompt to a remote engine and returns its text reply.
struct TranslationPromptCompleter {
  let complete: (String) async throws -> String

  init(_ complete: @escaping (String) async throws -> String) {
    self.complete = complete
  }

  static func endpoint(
    _ model: CustomOCRModel,
    keychainStore: OCRKeychainStoring = OCRKeychainStore(),
    session: URLSessionProtocol = URLSession.shared,
    timeout: TimeInterval
  ) -> TranslationPromptCompleter {
    let client = OpenAICompatibleChatClient(model: model, keychainStore: keychainStore, session: session, timeout: timeout)
    return TranslationPromptCompleter { prompt in
      try await client.complete(messages: [
        ChatCompletionMessage(role: "user", content: [.text(prompt)]),
      ])
    }
  }

  static func agentCLI(_ kind: AnnotateAgentCLIKind) -> TranslationPromptCompleter {
    TranslationPromptCompleter { prompt in
      try await AgentCLITextRunner(kind: kind).complete(prompt)
    }
  }

  static func engine(_ engine: RemoteTranslationEngine, endpointTimeout: TimeInterval) -> TranslationPromptCompleter {
    switch engine {
    case .endpoint(let model): .endpoint(model, timeout: endpointTimeout)
    case .agentCLI(let kind): .agentCLI(kind)
    }
  }
}

struct RemoteTranslationProvider {
  private let completer: TranslationPromptCompleter

  init(
    model: CustomOCRModel,
    keychainStore: OCRKeychainStoring = OCRKeychainStore(),
    session: URLSessionProtocol = URLSession.shared,
    timeout: TimeInterval = 60
  ) {
    completer = .endpoint(model, keychainStore: keychainStore, session: session, timeout: timeout)
  }

  init(engine: RemoteTranslationEngine) {
    completer = .engine(engine, endpointTimeout: 60)
  }

  init(completer: TranslationPromptCompleter) {
    self.completer = completer
  }

  func translate(_ text: String, to target: TranslationLanguage) async throws -> String {
    let content = try await completer.complete(Self.prompt(text: text, target: target))
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
