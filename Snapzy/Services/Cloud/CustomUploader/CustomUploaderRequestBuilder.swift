//
//  CustomUploaderRequestBuilder.swift
//  Snapzy
//
//  Turns a `CustomUploader` into a concrete request: resolves `{filename}` and
//  `{secret:NAME}` tokens, builds the URL with query items, and writes the
//  multipart body to a temp file so large videos never sit in memory.
//

import Foundation
import UniformTypeIdentifiers

/// A request with every template token resolved. Holds secret values: never log it.
nonisolated struct CustomUploaderResolvedRequest: Sendable {
  enum Body: Sendable, Equatable {
    case multipart(fileField: String, fields: [CustomUploader.KeyValue])
    case binary
    case formURLEncoded(fields: [CustomUploader.KeyValue])
  }

  var url: URL
  var method: String
  var headers: [CustomUploader.KeyValue]
  var body: Body
  var timeout: TimeInterval
}

enum CustomUploaderRequestBuilder {

  /// Resolves every request-side template of `uploader` for `fileName`.
  /// Throws `unresolvedSecret` for a missing secret (the literal token is never sent)
  /// and `unsupportedToken` for anything other than `{filename}`, `{file.name}`, `{secret:…}`.
  static func resolve(
    _ uploader: CustomUploader,
    fileName: String,
    secrets: CustomUploaderSecretResolving?
  ) throws -> CustomUploaderResolvedRequest {
    func render(_ template: String, encodeForURL: Bool = false) throws -> String {
      try renderRequestTemplate(template, fileName: fileName, secrets: secrets, encodeForURL: encodeForURL)
    }
    func renderPairs(_ pairs: [CustomUploader.KeyValue]) throws -> [CustomUploader.KeyValue] {
      try pairs
        .filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
        .map { CustomUploader.KeyValue(try render($0.key), try render($0.value)) }
    }

    // Values spliced into a URL are percent-encoded, unless the whole URL is one token
    // (for example `{secret:WEBHOOK_URL}`), which must stay a URL.
    let urlTemplate = uploader.url.trimmingCharacters(in: .whitespacesAndNewlines)
    let urlSegments = CustomUploaderTemplate.parse(urlTemplate)
    let isSingleToken: Bool = {
      guard urlSegments.count == 1, case .token = urlSegments[0] else { return false }
      return true
    }()
    let renderedURL = try render(urlTemplate, encodeForURL: !isSingleToken)
    guard var components = URLComponents(string: renderedURL),
      let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
      components.host?.isEmpty == false
    else {
      throw CustomUploaderError.invalidRequestURL
    }

    let query = try renderPairs(uploader.query)
    if !query.isEmpty {
      var items = components.queryItems ?? []
      items.append(contentsOf: query.map { URLQueryItem(name: $0.key, value: $0.value) })
      components.queryItems = items
      // URLQueryItem leaves `+` alone, which servers read as a space.
      components.percentEncodedQuery = components.percentEncodedQuery?
        .replacingOccurrences(of: "+", with: "%2B")
    }
    guard let url = components.url else {
      throw CustomUploaderError.invalidRequestURL
    }

    let body: CustomUploaderResolvedRequest.Body
    switch uploader.body {
    case .multipart(let fileField, let extraFields):
      let field = try render(fileField).trimmingCharacters(in: .whitespacesAndNewlines)
      body = .multipart(
        fileField: field.isEmpty ? CustomUploader.defaultFileField : field,
        fields: try renderPairs(extraFields)
      )
    case .binary:
      body = .binary
    case .formURLEncoded(let fields):
      body = .formURLEncoded(fields: try renderPairs(fields))
    }

    return CustomUploaderResolvedRequest(
      url: url,
      method: uploader.method.rawValue,
      headers: try renderPairs(uploader.headers),
      body: body,
      timeout: uploader.timeout > 0 ? uploader.timeout : CustomUploader.defaultTimeout
    )
  }

  /// Renders one request-side template.
  static func renderRequestTemplate(
    _ template: String,
    fileName: String,
    secrets: CustomUploaderSecretResolving?,
    encodeForURL: Bool = false
  ) throws -> String {
    try CustomUploaderTemplate.render(template) { name, argument in
      let value: String
      switch (name, argument) {
      case ("filename", nil), ("file.name", nil):
        value = fileName
      case ("secret", let secretName?):
        let trimmed = secretName.trimmingCharacters(in: .whitespaces)
        guard let secret = secrets?.secretValue(named: trimmed) else {
          throw CustomUploaderError.unresolvedSecret(trimmed)
        }
        value = secret
      default:
        throw CustomUploaderError.unsupportedToken(
          CustomUploaderResponseParser.tokenDescription(name: name, argument: argument)
        )
      }
      return encodeForURL ? percentEncodeComponent(value) : value
    }
  }

  nonisolated static func percentEncodeComponent(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    // `alphanumerics` includes non-ASCII letters; keep the set ASCII-only.
    allowed = allowed.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(127)))
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }

  nonisolated static func mimeType(for fileURL: URL) -> String {
    UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
  }

  nonisolated static func formURLEncoded(_ fields: [CustomUploader.KeyValue]) -> Data {
    let encoded = fields
      .map { "\(percentEncodeComponent($0.key))=\(percentEncodeComponent($0.value))" }
      .joined(separator: "&")
    return Data(encoded.utf8)
  }
}

// MARK: - Multipart Body

nonisolated enum CustomUploaderMultipartBody {
  static let lineBreak = "\r\n"
  private static let chunkSize = 1024 * 1024

  static func makeBoundary() -> String {
    "SnapzyBoundary-\(UUID().uuidString)"
  }

  static func contentTypeHeader(boundary: String) -> String {
    "multipart/form-data; boundary=\(boundary)"
  }

  /// Quotes stripped of `"`, CR and LF so a name can't break out of the header.
  static func sanitizeHeaderValue(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\"", with: "%22")
      .replacingOccurrences(of: "\r", with: "")
      .replacingOccurrences(of: "\n", with: "")
  }

  static func fieldPart(name: String, value: String, boundary: String) -> Data {
    var text = "--\(boundary)\(lineBreak)"
    text += "Content-Disposition: form-data; name=\"\(sanitizeHeaderValue(name))\"\(lineBreak)\(lineBreak)"
    text += "\(value)\(lineBreak)"
    return Data(text.utf8)
  }

  static func filePartHeader(fieldName: String, fileName: String, contentType: String, boundary: String) -> Data {
    var text = "--\(boundary)\(lineBreak)"
    text += "Content-Disposition: form-data; name=\"\(sanitizeHeaderValue(fieldName))\"; "
    text += "filename=\"\(sanitizeHeaderValue(fileName))\"\(lineBreak)"
    text += "Content-Type: \(sanitizeHeaderValue(contentType))\(lineBreak)\(lineBreak)"
    return Data(text.utf8)
  }

  static func closing(boundary: String) -> Data {
    Data("\(lineBreak)--\(boundary)--\(lineBreak)".utf8)
  }

  /// Writes fields (in order), then the file part, then the closing boundary to `destination`.
  /// The file is copied in 1 MB chunks. Returns the number of bytes written.
  @discardableResult
  static func write(
    fields: [CustomUploader.KeyValue],
    fileField: String,
    fileURL: URL,
    fileName: String,
    contentType: String,
    boundary: String,
    to destination: URL
  ) throws -> Int64 {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard fileManager.createFile(atPath: destination.path, contents: nil) else {
      throw CocoaError(.fileWriteUnknown)
    }
    let output = try FileHandle(forWritingTo: destination)
    defer { try? output.close() }
    let input = try FileHandle(forReadingFrom: fileURL)
    defer { try? input.close() }

    var written: Int64 = 0
    func emit(_ data: Data) throws {
      try output.write(contentsOf: data)
      written += Int64(data.count)
    }

    for field in fields {
      try emit(fieldPart(name: field.key, value: field.value, boundary: boundary))
    }
    try emit(filePartHeader(fieldName: fileField, fileName: fileName, contentType: contentType, boundary: boundary))
    while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
      try emit(chunk)
    }
    try emit(closing(boundary: boundary))
    return written
  }
}

extension CustomUploaderRequestBuilder {
  /// RFC 7230 token characters only.
  nonisolated static func isValidHeaderName(_ name: String) -> Bool {
    let allowed = CharacterSet(charactersIn: "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    return !name.isEmpty && name.unicodeScalars.allSatisfy(allowed.contains)
  }
}
