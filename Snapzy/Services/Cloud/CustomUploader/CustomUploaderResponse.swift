//
//  CustomUploaderResponse.swift
//  Snapzy
//
//  Raw HTTP response from a custom uploader and the extraction of
//  URL / thumbnail / deletion link / error message from it.
//

import Foundation

nonisolated struct CustomUploaderResponse: Equatable, Sendable {
  let statusCode: Int
  /// Header names lowercased.
  let headers: [String: String]
  let body: Data
  /// Final URL after redirects, if known.
  let responseURL: URL?

  init(statusCode: Int, headers: [String: String] = [:], body: Data, responseURL: URL? = nil) {
    self.statusCode = statusCode
    var lowered: [String: String] = [:]
    for (key, value) in headers { lowered[key.lowercased()] = value }
    self.headers = lowered
    self.body = body
    self.responseURL = responseURL
  }

  init(http: HTTPURLResponse, body: Data) {
    var headers: [String: String] = [:]
    for (key, value) in http.allHeaderFields {
      headers["\(key)"] = "\(value)"
    }
    self.init(statusCode: http.statusCode, headers: headers, body: body, responseURL: http.url)
  }

  var isSuccess: Bool { (200..<300).contains(statusCode) }

  var text: String {
    String(data: body, encoding: .utf8) ?? String(decoding: body, as: UTF8.self)
  }

  /// The first `limit` characters of the body, for error messages and the Test panel.
  func textPrefix(_ limit: Int) -> String {
    let full = text
    return full.count > limit ? String(full.prefix(limit)) + "…" : full
  }
}

/// Values extracted from a successful response.
nonisolated struct CustomUploaderExtraction: Equatable, Sendable {
  let url: URL
  let thumbnailURL: URL?
  let deletionURL: URL?
}

nonisolated enum CustomUploaderResponseParser {

  /// Field names used in error messages.
  enum Field {
    static let url = "URL"
    static let thumbnail = "ThumbnailURL"
    static let deletion = "DeletionURL"
    static let errorMessage = "ErrorMessage"
  }

  /// Applies an extractor and returns the raw text, or throws when nothing is found.
  static func extract(
    _ extractor: CustomUploader.ResponseExtractor,
    from response: CustomUploaderResponse,
    fileName: String = "",
    field: String = Field.url
  ) throws -> String {
    let value: String?
    switch extractor {
    case .plainText:
      value = response.text
    case .jsonPath(let path):
      guard CustomUploaderJSONPath.parse(path) != nil else {
        throw CustomUploaderError.invalidJSONPath(path)
      }
      value = CustomUploaderJSONPath.string(at: path, inJSON: response.body)
    case .regex(let argument):
      let (pattern, group) = CustomUploaderRegex.splitArgument(argument)
      value = try CustomUploaderRegex.firstMatch(pattern, in: response.text, group: group)
    case .template(let template):
      value = try renderTemplate(template, response: response, fileName: fileName, field: field)
    }
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else {
      throw CustomUploaderError.valueNotFound(field: field)
    }
    return trimmed
  }

  /// Expands `{json:…}`, `{regex:…}`, `{response}`, `{responseurl}`, `{header:…}`, `{filename}`.
  static func renderTemplate(
    _ template: String,
    response: CustomUploaderResponse,
    fileName: String,
    field: String
  ) throws -> String {
    try CustomUploaderTemplate.render(template) { name, argument in
      switch (name, argument) {
      case ("json", let path?):
        guard CustomUploaderJSONPath.parse(path) != nil else {
          throw CustomUploaderError.invalidJSONPath(path)
        }
        guard let value = CustomUploaderJSONPath.string(at: path, inJSON: response.body) else {
          throw CustomUploaderError.valueNotFound(field: field)
        }
        return value
      case ("regex", let argument?):
        let (pattern, group) = CustomUploaderRegex.splitArgument(argument)
        guard let value = try CustomUploaderRegex.firstMatch(pattern, in: response.text, group: group) else {
          throw CustomUploaderError.valueNotFound(field: field)
        }
        return value
      case ("response", nil):
        return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
      case ("responseurl", nil):
        return response.responseURL?.absoluteString ?? ""
      case ("header", let headerName?):
        return response.headers[headerName.lowercased()] ?? ""
      case ("filename", nil), ("file.name", nil):
        return fileName
      default:
        throw CustomUploaderError.unsupportedToken(tokenDescription(name: name, argument: argument))
      }
    }
  }

  /// Extracts and validates the public URL plus optional thumbnail and deletion links.
  /// The public URL must be http/https; optional links that fail are dropped.
  static func extraction(
    from response: CustomUploaderResponse,
    uploader: CustomUploader,
    fileName: String
  ) throws -> CustomUploaderExtraction {
    let raw = try extract(uploader.responseURL, from: response, fileName: fileName, field: Field.url)
    guard let url = CustomUploaderURLValidator.validatedWebURL(raw) else {
      throw CustomUploaderError.invalidResultURL(field: Field.url)
    }
    return CustomUploaderExtraction(
      url: url,
      thumbnailURL: optionalURL(uploader.thumbnailURL, response: response, fileName: fileName, field: Field.thumbnail),
      deletionURL: optionalURL(uploader.deletionURL, response: response, fileName: fileName, field: Field.deletion)
    )
  }

  /// Message for a non-2xx response: the ErrorMessage extractor if it yields text,
  /// else the first 200 characters of the body, else the HTTP status text.
  static func errorMessage(for response: CustomUploaderResponse, uploader: CustomUploader) -> String {
    if let extractor = uploader.errorMessage,
      let message = try? extract(extractor, from: response, field: Field.errorMessage)
    {
      return String(message.prefix(200))
    }
    let body = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !body.isEmpty {
      return String(body.prefix(200))
    }
    return HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
  }

  static func tokenDescription(name: String, argument: String?) -> String {
    argument.map { "{\(name):\($0)}" } ?? "{\(name)}"
  }

  private static func optionalURL(
    _ extractor: CustomUploader.ResponseExtractor?,
    response: CustomUploaderResponse,
    fileName: String,
    field: String
  ) -> URL? {
    guard let extractor,
      let raw = try? extract(extractor, from: response, fileName: fileName, field: field)
    else { return nil }
    return CustomUploaderURLValidator.validatedWebURL(raw)
  }
}
