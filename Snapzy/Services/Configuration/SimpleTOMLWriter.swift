//
//  SimpleTOMLWriter.swift
//  Snapzy
//
//  Deterministic TOML string helpers for Snapzy configuration export.
//

import Foundation

struct SimpleTOMLWriter {
  private var lines: [String] = []

  var output: String {
    lines.joined(separator: "\n") + "\n"
  }

  mutating func root(_ key: String, _ value: Int) {
    lines.append("\(key) = \(value)")
  }

  mutating func root(_ key: String, _ value: String) {
    lines.append("\(key) = \(quote(value))")
  }

  mutating func section(_ name: String) {
    if !lines.isEmpty, lines.last != "" {
      lines.append("")
    }
    lines.append("[\(name)]")
  }

  mutating func value(_ key: String, _ value: String) {
    lines.append("\(key) = \(quote(value))")
  }

  mutating func value(_ key: String, _ value: Bool) {
    lines.append("\(key) = \(value ? "true" : "false")")
  }

  mutating func value(_ key: String, _ value: Int) {
    lines.append("\(key) = \(value)")
  }

  mutating func value(_ key: String, _ value: Double) {
    let formatted = value.rounded() == value ? String(format: "%.1f", value) : String(value)
    lines.append("\(key) = \(formatted)")
  }

  mutating func stringArray(_ key: String, _ values: [String]) {
    let encoded = values.map(quote).joined(separator: ", ")
    lines.append("\(key) = [\(encoded)]")
  }

  private func quote(_ value: String) -> String {
    let escaped = value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\r", with: "\\r")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\t", with: "\\t")
    return "\"\(escaped)\""
  }
}
