//
//  CustomUploaderSXCUImporter.swift
//  Snapzy
//
//  Imports ShareX custom uploader files (.sxcu, JSON) into `CustomUploader`.
//  Unsupported fields and tokens are reported as warnings instead of failing,
//  and credential-looking values are offered as secret candidates.
//

import Foundation

nonisolated enum CustomUploaderImportWarning: Equatable, Sendable {
  case unsupportedToken(field: String, token: String)
  case unsupportedBody(String)
  case bodyWithoutFile(String)
  case unsupportedMethod(String)
  case ignoredField(String)
  /// A `{secret:NAME}` reference the file tried to use; removed on import.
  case removedSecret(field: String, token: String)

  var message: String {
    switch self {
    case .unsupportedToken(let field, let token):
      return L10n.CustomUploader.warningUnsupportedToken(token, field: field)
    case .unsupportedBody(let body):
      return L10n.CustomUploader.warningUnsupportedBody(body)
    case .bodyWithoutFile(let body):
      return L10n.CustomUploader.warningBodyWithoutFile(body)
    case .unsupportedMethod(let method):
      return L10n.CustomUploader.warningUnsupportedMethod(method)
    case .ignoredField(let field):
      return L10n.CustomUploader.warningIgnoredField(field)
    case .removedSecret(let field, let token):
      return L10n.CustomUploader.warningRemovedSecret(token, field)
    }
  }
}

/// A header, query parameter or body field whose value looks like a credential.
nonisolated struct CustomUploaderSecretCandidate: Equatable, Hashable, Identifiable, Sendable {
  enum Location: String, Sendable {
    case header
    case query
    case bodyField
  }

  let location: Location
  let fieldName: String
  let suggestedSecretName: String

  var id: String { "\(location.rawValue):\(fieldName)" }

  /// Field names that usually carry credentials.
  static func looksLikeCredential(_ name: String) -> Bool {
    let lowered = name.lowercased()
    if lowered == "authorization" || lowered == "proxy-authorization" { return true }
    return ["key", "token", "secret", "password", "auth"].contains { lowered.contains($0) }
  }
}

nonisolated struct CustomUploaderImportResult: Sendable {
  var uploader: CustomUploader
  var warnings: [CustomUploaderImportWarning]
  var secretCandidates: [CustomUploaderSecretCandidate]
}

nonisolated enum CustomUploaderSXCUImporter {

  static let fileExtension = "sxcu"

  private static let requestTokens: Set<String> = ["filename", "file.name", "secret"]

  /// A downloaded `.sxcu` must never name one of the user's stored secrets:
  /// `{"X-A": "{secret:SLACK_WEBHOOK}"}` would send that value to the file's
  /// server. References are removed (with a warning); the user can add their
  /// own with "Store as Secret" or in the editor.
  static func strippingSecretReferences(_ value: String) -> (text: String, removed: [String]) {
    var text = value
    var removed: [String] = []
    while let start = text.range(of: "{secret:", options: .caseInsensitive),
          let close = text[start.upperBound...].firstIndex(of: "}")
    {
      removed.append(String(text[start.lowerBound...close]))
      text.removeSubrange(start.lowerBound...close)
    }
    return (text, removed)
  }
  private static let responseTokens: Set<String> = [
    "json", "regex", "response", "responseurl", "header", "filename", "file.name",
  ]

  // MARK: - Import

  static func importUploader(from data: Data, fallbackName: String = "") throws -> CustomUploaderImportResult {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw CustomUploaderError.invalidImportFile
    }
    let rawText = String(data: data, encoding: .utf8) ?? ""
    let source = CaseInsensitiveObject(object)
    var warnings: [CustomUploaderImportWarning] = []
    let regexList = (source["RegexList"] as? [Any])?.map { CustomUploaderJSONPath.stringify($0) } ?? []

    func withoutSecrets(_ value: String, field: String) -> String {
      let stripped = strippingSecretReferences(value)
      for token in stripped.removed {
        let warning = CustomUploaderImportWarning.removedSecret(field: field, token: token)
        if !warnings.contains(warning) { warnings.append(warning) }
      }
      return stripped.text
    }
    func text(_ key: String) -> String {
      guard let value = source[key], !(value is NSNull) else { return "" }
      return withoutSecrets(convertLegacySyntax(CustomUploaderJSONPath.stringify(value), regexList: regexList), field: key)
    }
    func pairs(_ key: String) -> [CustomUploader.KeyValue] {
      guard let dictionary = source[key] as? [String: Any] else { return [] }
      return orderedKeys(of: dictionary, in: rawText).map { name in
        let value = dictionary[name].map { $0 is NSNull ? "" : CustomUploaderJSONPath.stringify($0) } ?? ""
        return CustomUploader.KeyValue(name, withoutSecrets(convertLegacySyntax(value, regexList: regexList), field: key))
      }
    }

    let requestURL = text("RequestURL").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !requestURL.isEmpty else { throw CustomUploaderError.invalidImportFile }

    // Method
    let methodRaw = (text("RequestMethod").isEmpty ? text("RequestType") : text("RequestMethod"))
      .trimmingCharacters(in: .whitespaces).uppercased()
    let method: CustomUploader.HTTPMethod
    if methodRaw.isEmpty {
      method = .post
    } else if let supported = CustomUploader.HTTPMethod(rawValue: methodRaw) {
      method = supported
    } else {
      method = .post
      warnings.append(.unsupportedMethod(methodRaw))
    }

    let headers = pairs("Headers")
    let query = pairs("Parameters")
    let arguments = pairs("Arguments")
    let fileFormName = text("FileFormName").trimmingCharacters(in: .whitespaces)

    // Body
    let bodyRaw = text("Body").trimmingCharacters(in: .whitespaces)
    let body: CustomUploader.Body
    let multipart = CustomUploader.Body.multipart(
      fileField: fileFormName.isEmpty ? CustomUploader.defaultFileField : fileFormName,
      extraFields: arguments
    )
    switch bodyRaw.lowercased() {
    case "", "multipartformdata":
      body = multipart
    case "binary":
      body = .binary
      if !arguments.isEmpty { warnings.append(.ignoredField("Arguments")) }
    case "formurlencoded":
      body = .formURLEncoded(fields: arguments)
      warnings.append(.bodyWithoutFile(bodyRaw))
    case "none":
      body = .formURLEncoded(fields: arguments)
      warnings.append(.bodyWithoutFile(bodyRaw))
    default:
      body = multipart
      warnings.append(.unsupportedBody(bodyRaw))
      if !text("Data").isEmpty { warnings.append(.ignoredField("Data")) }
    }

    // Legacy response type: anything but plain text (e.g. RedirectionURL) is not supported.
    let responseType = text("ResponseType").trimmingCharacters(in: .whitespaces)
    if !responseType.isEmpty, responseType.lowercased() != "text" {
      warnings.append(.ignoredField("ResponseType"))
    }

    func extractor(_ key: String) -> CustomUploader.ResponseExtractor? {
      let value = text(key).trimmingCharacters(in: .whitespacesAndNewlines)
      return value.isEmpty ? nil : normalizedExtractor(value)
    }

    let name = text("Name").trimmingCharacters(in: .whitespacesAndNewlines)
    let fallback = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
    let uploader = CustomUploader(
      name: name.isEmpty ? (fallback.isEmpty ? L10n.CustomUploader.importedDefaultName : fallback) : name,
      method: method,
      url: requestURL,
      headers: headers,
      query: query,
      body: body,
      responseURL: extractor("URL") ?? .plainText,
      thumbnailURL: extractor("ThumbnailURL"),
      deletionURL: extractor("DeletionURL"),
      errorMessage: extractor("ErrorMessage")
    )

    warnings.append(contentsOf: unsupportedTokenWarnings(in: uploader))
    return CustomUploaderImportResult(
      uploader: uploader,
      warnings: warnings,
      secretCandidates: secretCandidates(in: uploader)
    )
  }

  // MARK: - Extractors

  /// `{response}` → plain text, a lone `{json:p}` → JSONPath, a lone `{regex:p}` → regex,
  /// anything else → template.
  static func normalizedExtractor(_ value: String) -> CustomUploader.ResponseExtractor {
    let segments = CustomUploaderTemplate.parse(value)
    if segments.count == 1, case .token(let name, let argument) = segments[0] {
      switch (name, argument) {
      case ("response", nil): return .plainText
      case ("json", let path?): return .jsonPath(path)
      case ("regex", let pattern?): return .regex(pattern)
      default: break
      }
    }
    return .template(value)
  }

  // MARK: - Warnings

  static func unsupportedTokenWarnings(in uploader: CustomUploader) -> [CustomUploaderImportWarning] {
    var warnings: [CustomUploaderImportWarning] = []
    func check(_ template: String, field: String, allowed: Set<String>) {
      for token in CustomUploaderTemplate.tokens(in: template) where !allowed.contains(token.name) {
        let warning = CustomUploaderImportWarning.unsupportedToken(
          field: field,
          token: CustomUploaderResponseParser.tokenDescription(name: token.name, argument: token.argument)
        )
        if !warnings.contains(warning) { warnings.append(warning) }
      }
    }

    check(uploader.url, field: "RequestURL", allowed: requestTokens)
    for pair in uploader.headers { check(pair.value, field: "Headers", allowed: requestTokens) }
    for pair in uploader.query { check(pair.value, field: "Parameters", allowed: requestTokens) }
    switch uploader.body {
    case .multipart(_, let fields), .formURLEncoded(let fields):
      for pair in fields { check(pair.value, field: "Arguments", allowed: requestTokens) }
    case .binary:
      break
    }
    let responseFields: [(String, CustomUploader.ResponseExtractor?)] = [
      ("URL", uploader.responseURL),
      ("ThumbnailURL", uploader.thumbnailURL),
      ("DeletionURL", uploader.deletionURL),
      ("ErrorMessage", uploader.errorMessage),
    ]
    for (field, extractor) in responseFields {
      if case .template(let template)? = extractor {
        check(template, field: field, allowed: responseTokens)
      }
    }
    return warnings
  }

  // MARK: - Secrets

  static func secretCandidates(in uploader: CustomUploader) -> [CustomUploaderSecretCandidate] {
    var candidates: [CustomUploaderSecretCandidate] = []
    func consider(_ pairs: [CustomUploader.KeyValue], location: CustomUploaderSecretCandidate.Location) {
      for pair in pairs where CustomUploaderSecretCandidate.looksLikeCredential(pair.key) {
        let value = pair.value.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !isOnlySecretReference(value) else { continue }
        candidates.append(
          CustomUploaderSecretCandidate(
            location: location,
            fieldName: pair.key,
            suggestedSecretName: CustomUploaderSecrets.suggestedName(uploaderName: uploader.name, fieldName: pair.key)
          )
        )
      }
    }
    consider(uploader.headers, location: .header)
    consider(uploader.query, location: .query)
    switch uploader.body {
    case .multipart(_, let fields), .formURLEncoded(let fields):
      consider(fields, location: .bodyField)
    case .binary:
      break
    }
    return candidates
  }

  /// Moves a candidate's value into the secret store and replaces it with `{secret:NAME}`.
  @MainActor
  static func storeSecret(
    _ candidate: CustomUploaderSecretCandidate,
    secretName: String,
    in uploader: inout CustomUploader,
    provider: CustomUploaderSecretResolving
  ) throws {
    guard CustomUploaderSecrets.isValidName(secretName),
      let value = uploader.value(of: candidate)
    else { return }
    try provider.storeSecret(name: secretName, value: value)
    uploader.setValue(CustomUploaderSecrets.reference(to: secretName), for: candidate)
  }

  private static func isOnlySecretReference(_ value: String) -> Bool {
    let segments = CustomUploaderTemplate.parse(value)
    return segments.count == 1 && segments.first.map {
      if case .token(name: "secret", argument: _) = $0 { return true }
      return false
    } == true
  }

  // MARK: - Legacy syntax

  /// Converts pre-ShareX-13 `$json:path$`, `$response$`, `$regex:i,g$` (with RegexList)
  /// and other `$name:arg$` tokens to `{…}` syntax.
  static func convertLegacySyntax(_ value: String, regexList: [String]) -> String {
    guard value.contains("$"),
      let regex = try? NSRegularExpression(pattern: #"\$([A-Za-z][A-Za-z.]*)(?::([^$]*))?\$"#)
    else { return value }
    let nsValue = value as NSString
    var output = ""
    var cursor = 0
    for match in regex.matches(in: value, range: NSRange(location: 0, length: nsValue.length)) {
      output += nsValue.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
      let name = nsValue.substring(with: match.range(at: 1)).lowercased()
      let argument = match.range(at: 2).location == NSNotFound ? nil : nsValue.substring(with: match.range(at: 2))
      if name == "regex", let argument {
        let parts = argument.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        if let index = parts.first ?? nil, index >= 1, index <= regexList.count {
          let group = parts.count > 1 ? parts[1] : nil
          output += "{regex:\(regexList[index - 1])\(group.map { "|\($0)" } ?? "")}"
        } else {
          output += "{regex:\(argument)}"
        }
      } else {
        output += argument.map { "{\(name):\($0)}" } ?? "{\(name)}"
      }
      cursor = match.range.location + match.range.length
    }
    output += nsValue.substring(from: cursor)
    return output
  }

  /// Dictionary keys in the order they appear in the source text (JSONSerialization drops order).
  private static func orderedKeys(of dictionary: [String: Any], in rawText: String) -> [String] {
    func position(_ key: String) -> Int {
      guard let data = try? JSONSerialization.data(withJSONObject: [key], options: []),
        let quoted = String(data: data, encoding: .utf8)?.dropFirst().dropLast(),
        let range = rawText.range(of: String(quoted))
      else { return Int.max }
      return rawText.distance(from: rawText.startIndex, to: range.lowerBound)
    }
    return dictionary.keys.sorted { lhs, rhs in
      let (left, right) = (position(lhs), position(rhs))
      return left == right ? lhs < rhs : left < right
    }
  }
}

// MARK: - Case-insensitive lookup

private nonisolated struct CaseInsensitiveObject {
  private let storage: [String: Any]

  init(_ object: [String: Any]) {
    var storage: [String: Any] = [:]
    for (key, value) in object { storage[key.lowercased()] = value }
    self.storage = storage
  }

  subscript(_ key: String) -> Any? { storage[key.lowercased()] }
}

// MARK: - Field access for secret candidates

nonisolated extension CustomUploader {
  func value(of candidate: CustomUploaderSecretCandidate) -> String? {
    pairs(for: candidate.location)?.first { $0.key == candidate.fieldName }?.value
  }

  mutating func setValue(_ value: String, for candidate: CustomUploaderSecretCandidate) {
    func replace(_ pairs: inout [KeyValue]) {
      for index in pairs.indices where pairs[index].key == candidate.fieldName {
        pairs[index].value = value
      }
    }
    switch candidate.location {
    case .header:
      replace(&headers)
    case .query:
      replace(&query)
    case .bodyField:
      switch body {
      case .multipart(let fileField, var fields):
        replace(&fields)
        body = .multipart(fileField: fileField, extraFields: fields)
      case .formURLEncoded(var fields):
        replace(&fields)
        body = .formURLEncoded(fields: fields)
      case .binary:
        break
      }
    }
  }

  private func pairs(for location: CustomUploaderSecretCandidate.Location) -> [KeyValue]? {
    switch location {
    case .header: return headers
    case .query: return query
    case .bodyField:
      switch body {
      case .multipart(_, let fields), .formURLEncoded(let fields): return fields
      case .binary: return nil
      }
    }
  }
}
