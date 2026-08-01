//
//  RemoteOCRPayloads.swift
//  Snapzy
//
//  Codable wire shapes for OpenAI-compatible chat-completions OCR.
//

import Foundation

struct ChatCompletionRequest: Encodable {
  let model: String
  let messages: [ChatCompletionMessage]
}

struct ChatCompletionMessage: Encodable {
  let role: String
  let content: [ChatCompletionContentPart]
}

enum ChatCompletionContentPart: Encodable {
  case text(String)
  case imageURL(String)

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .text(let text):
      try container.encode("text", forKey: .type)
      try container.encode(text, forKey: .text)
    case .imageURL(let url):
      try container.encode("image_url", forKey: .type)
      try container.encode(["url": url], forKey: .imageURL)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case text
    case imageURL = "image_url"
  }
}

struct ChatCompletionResponse: Decodable {
  let choices: [Choice]

  struct Choice: Decodable {
    let message: Message
  }

  struct Message: Decodable {
    let content: MessageContent?
  }

  /// Providers return `content` either as a plain string or as an array of
  /// parts (`[{ "type": "text", "text": ... }]`) — both are accepted.
  enum MessageContent: Decodable {
    case text(String)
    case parts([Part])

    struct Part: Decodable {
      let text: String?
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let string = try? container.decode(String.self) {
        self = .text(string)
      } else {
        self = .parts(try container.decode([Part].self))
      }
    }

    var text: String {
      switch self {
      case .text(let string):
        return string
      case .parts(let parts):
        return parts.compactMap(\.text).joined()
      }
    }
  }
}
