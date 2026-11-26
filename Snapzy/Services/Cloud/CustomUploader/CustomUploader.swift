//
//  CustomUploader.swift
//  Snapzy
//
//  A user-defined HTTP upload destination (ShareX-style custom uploader).
//  Stored as JSON in UserDefaults; secret values never live here, only
//  `{secret:NAME}` references resolved at upload time.
//

import Foundation

nonisolated struct CustomUploader: Codable, Equatable, Identifiable, Sendable {

  static let defaultTimeout: TimeInterval = 60
  static let defaultFileField = "file"

  // MARK: - Nested Types

  enum HTTPMethod: String, Codable, CaseIterable, Sendable {
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
  }

  /// Ordered name/value pair used for headers, query parameters and form fields.
  struct KeyValue: Codable, Equatable, Hashable, Sendable {
    var key: String
    var value: String

    init(_ key: String, _ value: String) {
      self.key = key
      self.value = value
    }

    init(key: String, value: String) {
      self.key = key
      self.value = value
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
      value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
    }
  }

  enum Body: Equatable, Sendable {
    /// `multipart/form-data` with the file under `fileField` after the extra fields.
    case multipart(fileField: String, extraFields: [KeyValue])
    /// The raw file bytes are the request body.
    case binary
    /// `application/x-www-form-urlencoded` fields only; the file is not sent.
    case formURLEncoded(fields: [KeyValue])

    var kind: Kind {
      switch self {
      case .multipart: return .multipart
      case .binary: return .binary
      case .formURLEncoded: return .formURLEncoded
      }
    }

    enum Kind: String, CaseIterable, Sendable {
      case multipart
      case binary
      case formURLEncoded
    }
  }

  /// How a value (URL, thumbnail, deletion link, error message) is read from the response.
  enum ResponseExtractor: Equatable, Sendable {
    /// The whole response body, trimmed.
    case plainText
    /// JSONPath subset: `a.b[0].c`, `[0].url`.
    case jsonPath(String)
    /// Regex; first capture group, else the whole match.
    case regex(String)
    /// Template mixing literals with `{json:…}`, `{regex:…}`, `{response}`, `{header:…}`, `{filename}`.
    case template(String)

    var kind: Kind {
      switch self {
      case .plainText: return .plainText
      case .jsonPath: return .jsonPath
      case .regex: return .regex
      case .template: return .template
      }
    }

    /// The editable expression (empty for `.plainText`).
    var expression: String {
      switch self {
      case .plainText: return ""
      case .jsonPath(let value), .regex(let value), .template(let value): return value
      }
    }

    static func make(kind: Kind, expression: String) -> ResponseExtractor {
      switch kind {
      case .plainText: return .plainText
      case .jsonPath: return .jsonPath(expression)
      case .regex: return .regex(expression)
      case .template: return .template(expression)
      }
    }

    enum Kind: String, CaseIterable, Sendable {
      case plainText
      case jsonPath
      case regex
      case template
    }
  }

  // MARK: - Properties

  var id: UUID
  var name: String
  var method: HTTPMethod
  /// URL template; supports `{filename}`, `{file.name}` and `{secret:NAME}`.
  var url: String
  var headers: [KeyValue]
  var query: [KeyValue]
  var body: Body
  var responseURL: ResponseExtractor
  var thumbnailURL: ResponseExtractor?
  var deletionURL: ResponseExtractor?
  var errorMessage: ResponseExtractor?
  var timeout: TimeInterval

  init(
    id: UUID = UUID(),
    name: String,
    method: HTTPMethod = .post,
    url: String,
    headers: [KeyValue] = [],
    query: [KeyValue] = [],
    body: Body = .multipart(fileField: CustomUploader.defaultFileField, extraFields: []),
    responseURL: ResponseExtractor = .plainText,
    thumbnailURL: ResponseExtractor? = nil,
    deletionURL: ResponseExtractor? = nil,
    errorMessage: ResponseExtractor? = nil,
    timeout: TimeInterval = CustomUploader.defaultTimeout
  ) {
    self.id = id
    self.name = name
    self.method = method
    self.url = url
    self.headers = headers
    self.query = query
    self.body = body
    self.responseURL = responseURL
    self.thumbnailURL = thumbnailURL
    self.deletionURL = deletionURL
    self.errorMessage = errorMessage
    self.timeout = timeout
  }

  /// Copy with a fresh id, for "Duplicate".
  func duplicated(name newName: String) -> CustomUploader {
    var copy = self
    copy.id = UUID()
    copy.name = newName
    return copy
  }

  // MARK: - Codable (tolerant: missing or unknown values fall back to defaults)

  private enum CodingKeys: String, CodingKey {
    case id, name, method, url, headers, query, body
    case responseURL, thumbnailURL, deletionURL, errorMessage, timeout
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
    name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
    let methodRaw = (try? container.decodeIfPresent(String.self, forKey: .method)) ?? nil
    method = methodRaw.flatMap { HTTPMethod(rawValue: $0.uppercased()) } ?? .post
    url = (try? container.decodeIfPresent(String.self, forKey: .url)) ?? ""
    headers = (try? container.decodeIfPresent([KeyValue].self, forKey: .headers)) ?? []
    query = (try? container.decodeIfPresent([KeyValue].self, forKey: .query)) ?? []
    body = (try? container.decodeIfPresent(Body.self, forKey: .body))
      ?? .multipart(fileField: Self.defaultFileField, extraFields: [])
    responseURL = (try? container.decodeIfPresent(ResponseExtractor.self, forKey: .responseURL)) ?? .plainText
    thumbnailURL = (try? container.decodeIfPresent(ResponseExtractor.self, forKey: .thumbnailURL)) ?? nil
    deletionURL = (try? container.decodeIfPresent(ResponseExtractor.self, forKey: .deletionURL)) ?? nil
    errorMessage = (try? container.decodeIfPresent(ResponseExtractor.self, forKey: .errorMessage)) ?? nil
    let decodedTimeout = (try? container.decodeIfPresent(Double.self, forKey: .timeout)) ?? nil
    timeout = decodedTimeout.flatMap { $0 > 0 ? $0 : nil } ?? Self.defaultTimeout
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(method.rawValue, forKey: .method)
    try container.encode(url, forKey: .url)
    try container.encode(headers, forKey: .headers)
    try container.encode(query, forKey: .query)
    try container.encode(body, forKey: .body)
    try container.encode(responseURL, forKey: .responseURL)
    try container.encodeIfPresent(thumbnailURL, forKey: .thumbnailURL)
    try container.encodeIfPresent(deletionURL, forKey: .deletionURL)
    try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
    try container.encode(timeout, forKey: .timeout)
  }
}

// MARK: - Body Codable

nonisolated extension CustomUploader.Body: Codable {
  private enum CodingKeys: String, CodingKey {
    case type, fileField, fields
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? nil
    let fields = (try? container.decodeIfPresent([CustomUploader.KeyValue].self, forKey: .fields)) ?? []
    switch type.flatMap(Kind.init(rawValue:)) {
    case .binary:
      self = .binary
    case .formURLEncoded:
      self = .formURLEncoded(fields: fields)
    case .multipart, .none:
      let field = (try? container.decodeIfPresent(String.self, forKey: .fileField)) ?? nil
      let trimmed = field?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      self = .multipart(fileField: trimmed.isEmpty ? CustomUploader.defaultFileField : trimmed, extraFields: fields)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(kind.rawValue, forKey: .type)
    switch self {
    case .multipart(let fileField, let extraFields):
      try container.encode(fileField, forKey: .fileField)
      try container.encode(extraFields, forKey: .fields)
    case .binary:
      break
    case .formURLEncoded(let fields):
      try container.encode(fields, forKey: .fields)
    }
  }
}

// MARK: - ResponseExtractor Codable

nonisolated extension CustomUploader.ResponseExtractor: Codable {
  private enum CodingKeys: String, CodingKey {
    case type, value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? nil
    let value = (try? container.decodeIfPresent(String.self, forKey: .value)) ?? ""
    self = Self.make(kind: type.flatMap(Kind.init(rawValue:)) ?? .plainText, expression: value)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(kind.rawValue, forKey: .type)
    if kind != .plainText {
      try container.encode(expression, forKey: .value)
    }
  }
}
