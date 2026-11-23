//
//  AutomationVariables.swift
//  Snapzy
//
//  `{token}` values for templates (link formats, copied text, file names).
//  Naming tokens (`{date}`, `{appName}`, …) come from `CaptureOutputNaming`;
//  the rest describe the run's payload. Unknown tokens stay literal.
//

import Foundation

/// How a value is escaped when inserted into a template.
enum AutomationEscape: String, Codable, CaseIterable, Sendable {
  case none
  /// Backslash-escapes `\ [ ] ( )` (link text / alt text).
  case markdown
  /// `& < > " '` as entities.
  case html
  /// JSON string content, without the surrounding quotes.
  case json
  /// Percent-encoded for a URL query value.
  case url
}

struct AutomationVariables: Equatable {
  /// Tokens offered in the editor's help popover, in display order.
  static let payloadTokens = [
    "{link}", "{text}", "{file.name}", "{file.basename}", "{file.ext}", "{file.path}",
    "{width}", "{height}", "{saved.path}", "{saved.relativePath}", "{saved.relativeURL}", "{automation}",
  ]
  static let namingTokens = [
    "{date}", "{time}", "{datetime}", "{appName}", "{timestamp}",
  ]

  private(set) var values: [String: String]

  init(values: [String: String] = [:]) {
    self.values = values
  }

  /// Values for the current payload; the first file stands for `{file.*}`.
  init(context: AutomationRunContext, payload: AutomationPayload, pixelSize: CGSize? = nil) {
    let captureContext = CaptureContext(appName: context.appName, windowTitle: context.windowTitle)
    var values = CaptureOutputNaming.tokenValues(
      kind: payload.files.first?.kind == .image ? .screenshot : .recording,
      date: context.startedAt,
      context: captureContext
    )
    values["{automation}"] = context.automationName
    values["{link}"] = payload.link?.absoluteString ?? ""
    values["{text}"] = payload.text ?? ""
    if let file = payload.files.first?.url {
      values["{file.name}"] = file.lastPathComponent
      values["{file.basename}"] = file.deletingPathExtension().lastPathComponent
      values["{file.ext}"] = file.pathExtension
      values["{file.path}"] = file.path
    }
    if let pixelSize {
      values["{width}"] = "\(Int(pixelSize.width))"
      values["{height}"] = "\(Int(pixelSize.height))"
    }
    if let saved = payload.savedFile {
      values["{saved.path}"] = saved.path
      let relative = Self.relativePath(of: saved, in: payload.savedFolder)
      values["{saved.relativePath}"] = relative
      // Percent-encoded for Markdown / HTML links (spaces in app names).
      values["{saved.relativeURL}"] = relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relative
    }
    self.values = values
  }

  subscript(token: String) -> String? {
    get { values[token] }
    set { values[token] = newValue }
  }

  /// Replaces every known `{token}`; unknown tokens are left as written.
  func render(_ template: String, escape: AutomationEscape = .none) -> String {
    var output = ""
    var index = template.startIndex
    while index < template.endIndex {
      guard template[index] == "{",
            let close = template[index...].firstIndex(of: "}")
      else {
        output.append(template[index])
        index = template.index(after: index)
        continue
      }
      let token = String(template[index...close])
      if let value = values[token] {
        output += Self.escaped(value, mode: escape)
        index = template.index(after: close)
      } else {
        output.append(template[index])
        index = template.index(after: index)
      }
    }
    return output
  }

  /// `render`, plus `{secret:NAME}` resolved through `resolveSecret` in the
  /// same pass, so a payload value that happens to contain `{secret:…}` (OCR
  /// text, a file name) is inserted literally and never resolved. Only for
  /// fields that allow secrets (webhook URL / headers / body, uploader headers).
  /// Returns the text and the secret values used (for masking).
  func renderAllowingSecrets(
    _ template: String,
    escape: AutomationEscape = .none,
    secretEscape: AutomationEscape? = nil,
    resolveSecret: (String) -> String?
  ) throws -> (text: String, secrets: [String]) {
    var output = ""
    var secrets: [String] = []
    var index = template.startIndex
    while index < template.endIndex {
      guard template[index] == "{",
            let close = template[index...].firstIndex(of: "}")
      else {
        output.append(template[index])
        index = template.index(after: index)
        continue
      }
      let token = String(template[index...close])
      if token.hasPrefix(Self.secretPrefix) {
        let name = String(token.dropFirst(Self.secretPrefix.count).dropLast())
        guard let value = resolveSecret(name) else { throw AutomationStepError.secretMissing(name) }
        secrets.append(value)
        output += Self.escaped(value, mode: secretEscape ?? escape)
        index = template.index(after: close)
      } else if let value = values[token] {
        output += Self.escaped(value, mode: escape)
        index = template.index(after: close)
      } else {
        output.append(template[index])
        index = template.index(after: index)
      }
    }
    return (output, secrets)
  }

  static let secretPrefix = "{secret:"

  static func escaped(_ value: String, mode: AutomationEscape) -> String {
    switch mode {
    case .none:
      return value
    case .markdown:
      var result = ""
      for character in value {
        if "\\[]()".contains(character) { result.append("\\") }
        result.append(character)
      }
      return result
    case .html:
      return value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
    case .json:
      guard let data = try? JSONEncoder().encode(value),
            let quoted = String(data: data, encoding: .utf8),
            quoted.count >= 2
      else { return value }
      return String(quoted.dropFirst().dropLast())
    case .url:
      var allowed = CharacterSet.urlQueryAllowed
      allowed.remove(charactersIn: "&=+?#")
      return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
  }

  /// `docs/img/shot.webp` relative to `folder`; the file name when unrelated.
  static func relativePath(of file: URL, in folder: URL?) -> String {
    guard let folder else { return file.lastPathComponent }
    let folderPath = folder.standardizedFileURL.path
    let filePath = file.standardizedFileURL.path
    guard filePath.hasPrefix(folderPath + "/") else { return file.lastPathComponent }
    return String(filePath.dropFirst(folderPath.count + 1))
  }
}
