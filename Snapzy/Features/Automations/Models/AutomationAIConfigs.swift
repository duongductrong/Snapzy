//
//  AutomationAIConfigs.swift
//  Snapzy
//
//  Milestone 6 step settings: Redact (on-device Vision + pattern matching)
//  and AI Describe (`aiAnnotate`: the user's AI provider writes text about
//  the image — alt text, a summary, an answer to the prompt).
//

import Foundation

struct AutomationRedactConfig: Codable, Equatable, Sendable {
  enum Category: String, Codable, CaseIterable, Identifiable, Sendable {
    case emails
    case phoneNumbers
    case urls
    /// Card numbers, expiry dates, cardholder names.
    case paymentCards
    /// Passwords, API keys, bearer and access tokens.
    case credentials
    case faces
    case people

    var id: String { rawValue }

    /// Read from the image's text; the others come from face / body detection.
    var isText: Bool {
      switch self {
      case .emails, .phoneNumbers, .urls, .paymentCards, .credentials: true
      case .faces, .people: false
      }
    }

    /// The category a detected region belongs to.
    init(_ kind: AnnotateSensitiveDataKind) {
      switch kind {
      case .email: self = .emails
      case .phoneNumber: self = .phoneNumbers
      case .url: self = .urls
      case .creditCard, .paymentCardExpiration, .paymentCardholderName: self = .paymentCards
      case .credential, .accessToken: self = .credentials
      case .face: self = .faces
      case .person: self = .people
      }
    }
  }

  enum Style: String, Codable, CaseIterable, Identifiable, Sendable {
    case pixelate
    case blur
    /// Solid black box: nothing of the original survives.
    case solid

    var id: String { rawValue }
  }

  static let defaultCategories: [Category] = [.emails, .phoneNumbers, .paymentCards, .credentials]

  /// Kept in `Category.allCases` order, without duplicates.
  var categories: [Category]
  var style: Style

  init(categories: [Category] = AutomationRedactConfig.defaultCategories, style: Style = .pixelate) {
    self.categories = Category.allCases.filter(categories.contains)
    self.style = style
  }

  private enum CodingKeys: String, CodingKey {
    case categories, style
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // Unknown category names (a newer Snapzy) are dropped, not fatal.
    let raw = (try? container.decode([String].self, forKey: .categories)) ?? Self.defaultCategories.map(\.rawValue)
    self.init(
      categories: raw.compactMap(Category.init(rawValue:)),
      style: container.value(.style, default: .pixelate)
    )
  }

  var textCategories: [Category] { categories.filter(\.isText) }
  var detectsFaces: Bool { categories.contains(.faces) }
  var detectsPeople: Bool { categories.contains(.people) }
}

struct AutomationAIAnnotateConfig: Codable, Equatable, Sendable {
  /// Which AI answers. `nil` = the provider chosen in Settings → AI.
  enum Provider: Equatable, Sendable {
    case settings
    case endpoint(UUID)
    case cli(String)

    var persistedValue: String {
      switch self {
      case .settings: "settings"
      case .endpoint(let id): "endpoint:\(id.uuidString)"
      case .cli(let kind): "cli:\(kind)"
      }
    }

    init(persistedValue: String?) {
      switch persistedValue {
      case let value? where value.hasPrefix("endpoint:"):
        self = UUID(uuidString: String(value.dropFirst("endpoint:".count))).map(Provider.endpoint) ?? .settings
      case let value? where value.hasPrefix("cli:"):
        self = .cli(String(value.dropFirst("cli:".count)))
      default:
        self = .settings
      }
    }
  }

  static let defaultPrompt = "Write concise alt text for this screenshot."
  static let maxPromptLength = 2000
  static let timeoutSeconds = 120

  var prompt: String
  var provider: Provider

  init(prompt: String = AutomationAIAnnotateConfig.defaultPrompt, provider: Provider = .settings) {
    self.prompt = prompt
    self.provider = provider
  }

  var trimmedPrompt: String {
    String(prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxPromptLength))
  }

  private enum CodingKeys: String, CodingKey {
    case prompt, provider
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    prompt = container.value(.prompt, default: Self.defaultPrompt)
    provider = Provider(persistedValue: try? container.decode(String.self, forKey: .provider))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(prompt, forKey: .prompt)
    try container.encode(provider.persistedValue, forKey: .provider)
  }
}
