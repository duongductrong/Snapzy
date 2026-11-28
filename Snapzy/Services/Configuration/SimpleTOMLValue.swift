//
//  SimpleTOMLValue.swift
//  Snapzy
//
//  Minimal TOML value tree for Snapzy's user-editable configuration.
//

import Foundation

enum SimpleTOMLValue: Equatable {
  case string(String)
  case bool(Bool)
  case integer(Int)
  case double(Double)
  case array([SimpleTOMLValue])
  case table([String: SimpleTOMLValue])

  var stringValue: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  var boolValue: Bool? {
    if case .bool(let value) = self { return value }
    return nil
  }

  var intValue: Int? {
    switch self {
    case .integer(let value):
      return value
    case .double(let value):
      return Int(exactly: value)
    default:
      return nil
    }
  }

  var doubleValue: Double? {
    switch self {
    case .double(let value):
      return value
    case .integer(let value):
      return Double(value)
    default:
      return nil
    }
  }

  var stringArrayValue: [String]? {
    guard case .array(let values) = self else { return nil }
    var strings: [String] = []
    for value in values {
      guard let string = value.stringValue else { return nil }
      strings.append(string)
    }
    return strings
  }
}

struct SimpleTOMLDocument {
  private(set) var root: [String: SimpleTOMLValue] = [:]

  func value(at path: String...) -> SimpleTOMLValue? {
    value(at: path)
  }

  func value(at path: [String]) -> SimpleTOMLValue? {
    guard !path.isEmpty else { return .table(root) }
    var current = root

    for segment in path.dropLast() {
      guard case .table(let next)? = current[segment] else { return nil }
      current = next
    }

    return current[path[path.count - 1]]
  }

  mutating func set(_ value: SimpleTOMLValue, at path: [String]) throws {
    guard !path.isEmpty else { throw SimpleTOMLError.invalidKey("Empty TOML key") }
    try Self.set(value, at: path[...], in: &root)
  }

  mutating func ensureTable(at path: [String]) throws {
    guard !path.isEmpty else { return }
    try Self.ensureTable(at: path[...], in: &root)
  }

  private static func set(
    _ value: SimpleTOMLValue,
    at path: ArraySlice<String>,
    in table: inout [String: SimpleTOMLValue]
  ) throws {
    guard let head = path.first else { return }
    if path.count == 1 {
      table[head] = value
      return
    }

    var child: [String: SimpleTOMLValue]
    if case .table(let existing)? = table[head] {
      child = existing
    } else {
      child = [:]
    }

    try Self.set(value, at: path.dropFirst(), in: &child)
    table[head] = .table(child)
  }

  private static func ensureTable(
    at path: ArraySlice<String>,
    in table: inout [String: SimpleTOMLValue]
  ) throws {
    guard let head = path.first else { return }

    var child: [String: SimpleTOMLValue]
    if case .table(let existing)? = table[head] {
      child = existing
    } else if table[head] == nil {
      child = [:]
    } else {
      throw SimpleTOMLError.invalidKey(path.joined(separator: "."))
    }

    if path.count > 1 {
      try Self.ensureTable(at: path.dropFirst(), in: &child)
    }
    table[head] = .table(child)
  }
}

enum SimpleTOMLError: LocalizedError, Equatable {
  case invalidLine(Int, String)
  case invalidKey(String)
  case invalidValue(Int, String)

  var errorDescription: String? {
    switch self {
    case .invalidLine(let line, let text):
      return "Invalid TOML at line \(line): \(text)"
    case .invalidKey(let text):
      return "Invalid TOML key: \(text)"
    case .invalidValue(let line, let text):
      return "Invalid TOML value at line \(line): \(text)"
    }
  }
}
