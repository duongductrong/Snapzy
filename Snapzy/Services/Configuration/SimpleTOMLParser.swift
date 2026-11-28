//
//  SimpleTOMLParser.swift
//  Snapzy
//
//  Small TOML parser for Snapzy config import. It supports comments, nested
//  tables, dotted keys, strings, booleans, numbers, and arrays.
//

import Foundation

enum SimpleTOMLParser {
  static func parse(_ source: String) throws -> SimpleTOMLDocument {
    var document = SimpleTOMLDocument()
    var currentPath: [String] = []

    for (index, rawLine) in source.components(separatedBy: .newlines).enumerated() {
      let lineNumber = index + 1
      let line = stripComment(from: rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else { continue }

      if line.hasPrefix("[") {
        guard line.hasSuffix("]"), !line.hasPrefix("[[") else {
          throw SimpleTOMLError.invalidLine(lineNumber, rawLine)
        }
        let inner = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        currentPath = try parseKeyPath(inner)
        try document.ensureTable(at: currentPath)
        continue
      }

      let parts = splitAssignment(line)
      guard let keyText = parts.key, let valueText = parts.value else {
        throw SimpleTOMLError.invalidLine(lineNumber, rawLine)
      }

      let keyPath = try currentPath + parseKeyPath(keyText)
      let value = try parseValue(valueText.trimmingCharacters(in: .whitespacesAndNewlines), line: lineNumber)
      try document.set(value, at: keyPath)
    }

    return document
  }

  private static func splitAssignment(_ line: String) -> (key: String?, value: String?) {
    var isInString = false
    var isEscaped = false

    for index in line.indices {
      let character = line[index]
      if isEscaped {
        isEscaped = false
        continue
      }
      if character == "\\" {
        isEscaped = isInString
        continue
      }
      if character == "\"" {
        isInString.toggle()
        continue
      }
      if character == "=", !isInString {
        let key = String(line[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(line[line.index(after: index)...])
        return (key, value)
      }
    }

    return (nil, nil)
  }

  private static func stripComment(from line: String) -> String {
    var result = ""
    var isInString = false
    var isEscaped = false

    for character in line {
      if isEscaped {
        result.append(character)
        isEscaped = false
        continue
      }
      if character == "\\" {
        result.append(character)
        isEscaped = isInString
        continue
      }
      if character == "\"" {
        result.append(character)
        isInString.toggle()
        continue
      }
      if character == "#", !isInString {
        break
      }
      result.append(character)
    }

    return result
  }

  private static func parseKeyPath(_ key: String) throws -> [String] {
    var rawParts: [String] = []
    var current = ""
    var isInString = false
    var isEscaped = false

    for character in key {
      if isEscaped {
        current.append(character)
        isEscaped = false
        continue
      }
      if character == "\\" {
        current.append(character)
        isEscaped = isInString
        continue
      }
      if character == "\"" {
        current.append(character)
        isInString.toggle()
        continue
      }
      if character == ".", !isInString {
        rawParts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        current = ""
        continue
      }
      current.append(character)
    }

    guard !isInString else {
      throw SimpleTOMLError.invalidKey(key)
    }
    rawParts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))

    guard !rawParts.isEmpty, rawParts.allSatisfy({ !$0.isEmpty }) else {
      throw SimpleTOMLError.invalidKey(key)
    }
    return rawParts.map { part in
      if part.count >= 2, part.hasPrefix("\""), part.hasSuffix("\"") {
        return unescape(String(part.dropFirst().dropLast()))
      }
      return part
    }
  }

  private static func parseValue(_ value: String, line: Int) throws -> SimpleTOMLValue {
    if value.hasPrefix("\"") {
      guard value.count >= 2, value.hasSuffix("\"") else { throw SimpleTOMLError.invalidValue(line, value) }
      return .string(unescape(String(value.dropFirst().dropLast())))
    }
    if value == "true" { return .bool(true) }
    if value == "false" { return .bool(false) }
    if value.hasPrefix("[") {
      guard value.hasSuffix("]") else { throw SimpleTOMLError.invalidValue(line, value) }
      let inner = String(value.dropFirst().dropLast())
      let values = try splitArray(inner, line: line, fullValue: value).map { try parseValue($0, line: line) }
      return .array(values)
    }
    if let intValue = Int(value) { return .integer(intValue) }
    if let doubleValue = Double(value) { return .double(doubleValue) }
    throw SimpleTOMLError.invalidValue(line, value)
  }

  private static func splitArray(_ value: String, line: Int, fullValue: String) throws -> [String] {
    var result: [String] = []
    var current = ""
    var isInString = false
    var isEscaped = false
    var depth = 0

    for character in value {
      if isEscaped {
        current.append(character)
        isEscaped = false
        continue
      }
      if character == "\\" {
        current.append(character)
        isEscaped = isInString
        continue
      }
      if character == "\"" {
        current.append(character)
        isInString.toggle()
        continue
      }
      if character == "[", !isInString { depth += 1 }
      if character == "]", !isInString {
        depth -= 1
        if depth < 0 {
          throw SimpleTOMLError.invalidValue(line, fullValue)
        }
      }
      if character == ",", !isInString, depth == 0 {
        let item = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !item.isEmpty { result.append(item) }
        current = ""
        continue
      }
      current.append(character)
    }

    guard !isInString, depth == 0 else {
      throw SimpleTOMLError.invalidValue(line, fullValue)
    }

    let item = current.trimmingCharacters(in: .whitespacesAndNewlines)
    if !item.isEmpty { result.append(item) }
    return result
  }

  /// Decodes TOML escape sequences in a single left-to-right pass.
  ///
  /// Each `\` is consumed together with the character that follows it, so a
  /// pass can never re-process output produced by an earlier pass. This is the
  /// exact inverse of `SimpleTOMLWriter.quote`, which makes export/import
  /// lossless — a value containing a backslash followed by `n`/`t` (e.g.
  /// `a\nb`) survives the round-trip instead of being turned into a real
  /// newline/tab. Unknown escapes (`\x`) and a trailing backslash are kept
  /// literal.
  private static func unescape(_ value: String) -> String {
    var result = ""
    result.reserveCapacity(value.count)
    var index = value.startIndex
    while index < value.endIndex {
      if value[index] == "\\" {
        let next = value.index(after: index)
        guard next < value.endIndex else {
          result.append("\\")
          break
        }
        switch value[next] {
        case "\"": result.append("\"")
        case "\\": result.append("\\")
        case "r": result.append("\r")
        case "n": result.append("\n")
        case "t": result.append("\t")
        default:
          result.append("\\")
          result.append(value[next])
        }
        index = value.index(after: next)
      } else {
        result.append(value[index])
        index = value.index(after: index)
      }
    }
    return result
  }
}
