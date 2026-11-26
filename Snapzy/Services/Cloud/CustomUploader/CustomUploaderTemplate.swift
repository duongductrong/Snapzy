//
//  CustomUploaderTemplate.swift
//  Snapzy
//
//  Pure helpers for custom uploaders: `{token}` template parsing, the JSONPath
//  subset, regex extraction and URL validation. No I/O, unit-tested.
//

import Foundation

// MARK: - Template

nonisolated enum CustomUploaderTemplate {

  enum Segment: Equatable, Sendable {
    case literal(String)
    /// `{name}` or `{name:argument}`. `argument` is raw (escapes kept).
    case token(name: String, argument: String?)
  }

  /// Splits a template into literals and `{name[:argument]}` tokens.
  ///
  /// - A token name is letters, digits, `.`, `_` or `-`, starting with a letter.
  /// - Braces inside an argument nest (`{regex:\d{3}}`), and `\{` / `\}` inside an
  ///   argument are skipped when counting, so regex escapes survive untouched.
  /// - Outside tokens, `\{`, `\}` and `\\` are literal braces/backslash (ShareX escaping).
  /// - Anything that does not form a valid token stays literal.
  static func parse(_ template: String) -> [Segment] {
    let chars = Array(template)
    var segments: [Segment] = []
    var literal = ""
    var index = 0

    func flushLiteral() {
      if !literal.isEmpty {
        segments.append(.literal(literal))
        literal = ""
      }
    }

    while index < chars.count {
      let char = chars[index]
      if char == "\\", index + 1 < chars.count, "{}\\".contains(chars[index + 1]) {
        literal.append(chars[index + 1])
        index += 2
        continue
      }
      if char == "{", let (segment, end) = parseToken(chars, start: index) {
        flushLiteral()
        segments.append(segment)
        index = end + 1
        continue
      }
      literal.append(char)
      index += 1
    }
    flushLiteral()
    return segments
  }

  /// Renders a template, replacing every token through `resolve`.
  static func render(_ template: String, resolve: (_ name: String, _ argument: String?) throws -> String) rethrows -> String {
    var output = ""
    for segment in parse(template) {
      switch segment {
      case .literal(let text):
        output += text
      case .token(let name, let argument):
        output += try resolve(name, argument)
      }
    }
    return output
  }

  /// Every token in a template, in order.
  static func tokens(in template: String) -> [(name: String, argument: String?)] {
    parse(template).compactMap {
      if case .token(let name, let argument) = $0 { return (name, argument) }
      return nil
    }
  }

  private static func parseToken(_ chars: [Character], start: Int) -> (Segment, Int)? {
    var index = start + 1
    var name = ""
    while index < chars.count, isNameCharacter(chars[index], isFirst: name.isEmpty) {
      name.append(chars[index])
      index += 1
    }
    guard !name.isEmpty, index < chars.count else { return nil }

    if chars[index] == "}" {
      return (.token(name: name.lowercased(), argument: nil), index)
    }
    guard chars[index] == ":" else { return nil }

    index += 1
    var argument = ""
    var depth = 0
    while index < chars.count {
      let char = chars[index]
      if char == "\\", index + 1 < chars.count {
        argument.append(char)
        argument.append(chars[index + 1])
        index += 2
        continue
      }
      if char == "{" {
        depth += 1
      } else if char == "}" {
        if depth == 0 {
          return (.token(name: name.lowercased(), argument: argument), index)
        }
        depth -= 1
      }
      argument.append(char)
      index += 1
    }
    return nil
  }

  private static func isNameCharacter(_ char: Character, isFirst: Bool) -> Bool {
    guard char.isASCII else { return false }
    if char.isLetter { return true }
    if isFirst { return false }
    return char.isNumber || char == "." || char == "_" || char == "-"
  }
}

// MARK: - JSONPath subset

nonisolated enum CustomUploaderJSONPath {

  enum Component: Equatable, Sendable {
    case key(String)
    case index(Int)
  }

  /// Parses `a.b[0].c`, `[0].url`, `$.data.url`, `files[0][1]`, `data["odd key"]`.
  /// Returns nil for malformed paths.
  static func parse(_ path: String) -> [Component]? {
    var chars = Array(path.trimmingCharacters(in: .whitespacesAndNewlines))
    if chars.first == "$" {
      chars.removeFirst()
      if chars.first == "." { chars.removeFirst() }
    }
    guard !chars.isEmpty else { return [] }

    var components: [Component] = []
    var index = 0
    var key = ""
    var expectsKey = true

    func flushKey() -> Bool {
      if key.isEmpty { return !expectsKey }
      components.append(.key(key))
      key = ""
      expectsKey = false
      return true
    }

    while index < chars.count {
      let char = chars[index]
      switch char {
      case ".":
        guard flushKey() else { return nil }
        expectsKey = true
        index += 1
        if index >= chars.count { return nil }
      case "[":
        if !key.isEmpty { _ = flushKey() }
        guard let close = chars[index...].firstIndex(of: "]") else { return nil }
        let inner = String(chars[(index + 1)..<close]).trimmingCharacters(in: .whitespaces)
        if let number = Int(inner), number >= 0 {
          components.append(.index(number))
        } else if inner.count >= 2,
          let quote = inner.first, quote == "\"" || quote == "'", inner.last == quote
        {
          components.append(.key(String(inner.dropFirst().dropLast())))
        } else {
          return nil
        }
        expectsKey = false
        index = close + 1
      case "]":
        return nil
      default:
        key.append(char)
        index += 1
      }
    }
    if !key.isEmpty { components.append(.key(key)) }
    return components
  }

  /// Evaluates a path on a parsed JSON value (`JSONSerialization` output).
  static func evaluate(_ path: String, in json: Any) -> Any? {
    guard let components = parse(path) else { return nil }
    var current: Any = json
    for component in components {
      switch component {
      case .key(let key):
        guard let object = current as? [String: Any], let next = object[key] else { return nil }
        current = next
      case .index(let index):
        guard let array = current as? [Any], index < array.count else { return nil }
        current = array[index]
      }
    }
    return current is NSNull ? nil : current
  }

  /// Evaluates a path on raw JSON data and returns the value as text.
  static func string(at path: String, inJSON data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
      let value = evaluate(path, in: json)
    else { return nil }
    return stringify(value)
  }

  static func stringify(_ value: Any) -> String {
    switch value {
    case let string as String:
      return string
    case let number as NSNumber:
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return number.boolValue ? "true" : "false"
      }
      return number.stringValue
    default:
      if JSONSerialization.isValidJSONObject(value),
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
        let text = String(data: data, encoding: .utf8)
      {
        return text
      }
      return "\(value)"
    }
  }
}

// MARK: - Regex

nonisolated enum CustomUploaderRegex {

  /// First capture group of the first match, else the whole match.
  /// Throws for an invalid pattern; returns nil when nothing matches.
  static func firstMatch(_ pattern: String, in text: String, group: Int? = nil) throws -> String? {
    let regex: NSRegularExpression
    do {
      regex = try NSRegularExpression(pattern: pattern, options: [])
    } catch {
      throw CustomUploaderError.invalidRegex(pattern)
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }

    let groupIndex: Int
    if let group {
      guard group <= regex.numberOfCaptureGroups else { return nil }
      groupIndex = group
    } else {
      groupIndex = regex.numberOfCaptureGroups >= 1 ? 1 : 0
    }
    let groupRange = match.range(at: groupIndex)
    guard groupRange.location != NSNotFound, let swiftRange = Range(groupRange, in: text) else { return nil }
    return String(text[swiftRange])
  }

  /// Splits a ShareX `{regex:pattern|group}` argument. The group suffix is used only
  /// when it is all digits, so alternations like `a|b` stay part of the pattern.
  static func splitArgument(_ argument: String) -> (pattern: String, group: Int?) {
    guard let bar = argument.lastIndex(of: "|") else { return (argument, nil) }
    let suffix = argument[argument.index(after: bar)...]
    guard !suffix.isEmpty, suffix.allSatisfy(\.isASCII), suffix.allSatisfy(\.isNumber), let group = Int(suffix) else {
      return (argument, nil)
    }
    return (String(argument[..<bar]), group)
  }
}

// MARK: - URL Validation

nonisolated enum CustomUploaderURLValidator {
  /// Only absolute http/https URLs with a host are accepted as upload results.
  /// `file:`, `javascript:`, `data:` and relative values are rejected.
  static func validatedWebURL(_ raw: String) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let url = URL(string: trimmed),
      let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
      let host = url.host, !host.isEmpty
    else { return nil }
    return url
  }
}
