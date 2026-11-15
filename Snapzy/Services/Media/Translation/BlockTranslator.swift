//
//  BlockTranslator.swift
//  Snapzy
//
//  Translates many independent text blocks at once and keeps each result tied to
//  its block (Annotate Auto Translate). Snip to Translate keeps its own runners.
//

import Foundation
import Translation

/// One translated block; nil text means the engine returned nothing for it.
struct BlockTranslationOutput: Equatable {
  let texts: [String?]
  let sourceLanguageIdentifier: String?
}

@available(macOS 15.0, *)
enum AppleBlockTranslator {
  /// One batch for all blocks; `clientIdentifier` is the block index.
  static func run(_ blocks: [String], session: TranslationSession) async throws -> BlockTranslationOutput {
    guard !blocks.isEmpty else {
      return BlockTranslationOutput(texts: [], sourceLanguageIdentifier: nil)
    }

    let requests = blocks.enumerated().map { offset, text in
      TranslationSession.Request(sourceText: text, clientIdentifier: String(offset))
    }
    let responses = try await session.translations(from: requests)

    var texts = [String?](repeating: nil, count: blocks.count)
    for response in responses {
      guard let identifier = response.clientIdentifier, let offset = Int(identifier),
            texts.indices.contains(offset) else { continue }
      let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
      texts[offset] = translated.isEmpty ? nil : translated
    }

    return BlockTranslationOutput(
      texts: texts,
      sourceLanguageIdentifier: responses.first.map { $0.sourceLanguage.minimalIdentifier }
    )
  }
}

/// Translates blocks through a custom OpenAI-compatible endpoint with a JSON
/// array in and out, so every result maps back to its block by id.
struct RemoteBlockTranslator {
  static let maxBlocksPerRequest = 40

  private let client: OpenAICompatibleChatClient

  init(
    model: CustomOCRModel,
    keychainStore: OCRKeychainStoring = OCRKeychainStore(),
    session: URLSessionProtocol = URLSession.shared,
    timeout: TimeInterval = 90
  ) {
    client = OpenAICompatibleChatClient(
      model: model,
      keychainStore: keychainStore,
      session: session,
      timeout: timeout
    )
  }

  func translate(_ blocks: [String], to target: TranslationLanguage) async throws -> BlockTranslationOutput {
    var texts = [String?](repeating: nil, count: blocks.count)
    var firstError: Error?
    var translatedAny = false

    for start in stride(from: 0, to: blocks.count, by: Self.maxBlocksPerRequest) {
      try Task.checkCancellation()
      let end = min(start + Self.maxBlocksPerRequest, blocks.count)
      let chunk = Array(blocks[start..<end])
      do {
        let content = try await client.complete(messages: [
          ChatCompletionMessage(role: "user", content: [.text(Self.prompt(blocks: chunk, target: target))]),
        ])
        let parsed = Self.parse(content, count: chunk.count)
        for (offset, text) in parsed.enumerated() where text != nil {
          texts[start + offset] = text
          translatedAny = true
        }
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        firstError = firstError ?? error
      }
    }

    if !translatedAny, let firstError {
      throw firstError
    }
    return BlockTranslationOutput(texts: texts, sourceLanguageIdentifier: nil)
  }

  static func prompt(blocks: [String], target: TranslationLanguage) -> String {
    let items = blocks.enumerated().map { ["id": $0.offset, "text": $0.element] as [String: Any] }
    let json = (try? JSONSerialization.data(withJSONObject: ["items": items], options: [.sortedKeys]))
      .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"items\":[]}"
    return """
    Translate each item's "text" into \(target.englishName) (\(target.identifier)). \
    The items are separate pieces of text from one screenshot (labels, buttons, paragraphs). \
    Keep each item's line breaks. Keep numbers, URLs, code, product names and placeholders unchanged. \
    Reply with JSON only, in exactly this shape and with the same ids: \
    {"items":[{"id":0,"text":"..."}]}

    \(json)
    """
  }

  /// Reads `{"items":[{"id":..,"text":..}]}` (or a bare array), tolerating code fences
  /// and text around the JSON. Ids outside `0..<count` are ignored.
  static func parse(_ content: String, count: Int) -> [String?] {
    var texts = [String?](repeating: nil, count: count)
    guard let data = extractJSON(from: content).data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) else { return texts }

    let items: [Any]
    if let dictionary = object as? [String: Any], let array = dictionary["items"] as? [Any] {
      items = array
    } else if let array = object as? [Any] {
      items = array
    } else {
      return texts
    }

    for item in items {
      guard let item = item as? [String: Any],
            let text = item["text"] as? String else { continue }
      let id: Int?
      if let number = item["id"] as? Int {
        id = number
      } else if let string = item["id"] as? String {
        id = Int(string)
      } else {
        id = nil
      }
      guard let id, texts.indices.contains(id) else { continue }
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      texts[id] = trimmed.isEmpty ? nil : trimmed
    }
    return texts
  }

  private static func extractJSON(from content: String) -> String {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    let openers: [Character] = ["{", "["]
    guard let start = trimmed.firstIndex(where: { openers.contains($0) }) else { return trimmed }
    let closer: Character = trimmed[start] == "{" ? "}" : "]"
    guard let end = trimmed.lastIndex(of: closer), end > start else { return trimmed }
    return String(trimmed[start...end])
  }
}
