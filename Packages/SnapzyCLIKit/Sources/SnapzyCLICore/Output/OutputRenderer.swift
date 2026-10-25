//
//  OutputRenderer.swift
//  SnapzyCLICore
//
//  JSON for agents and pipes, one readable line per item for people. Pure
//  string rendering; callers decide which stream to write to.
//

import Foundation
import SnapzyCLIProtocol

public protocol HumanReadable {
  var humanDescription: String { get }
}

public struct OutputRenderer: Sendable {
  public enum Mode: Equatable, Sendable {
    case json(pretty: Bool)
    case human
  }

  /// Not a terminal → compact JSON. Terminal → human text, or pretty JSON with `--json`.
  public static func mode(jsonFlag: Bool, stdoutIsTerminal: Bool) -> Mode {
    guard stdoutIsTerminal else { return .json(pretty: false) }
    return jsonFlag ? .json(pretty: true) : .human
  }

  public let mode: Mode

  public init(mode: Mode) {
    self.mode = mode
  }

  /// Rendered value with a trailing newline.
  public func render(_ value: some Encodable & HumanReadable) throws -> String {
    switch mode {
    case .json(let pretty):
      try Self.json(value, pretty: pretty) + "\n"
    case .human:
      value.humanDescription + "\n"
    }
  }

  public func render(error: CLIError) -> String {
    switch mode {
    case .json(let pretty):
      let body = (try? Self.json(ErrorDocument(error: error), pretty: pretty))
        ?? #"{"error":{"code":"internal","message":"Could not encode error"}}"#
      return body + "\n"
    case .human:
      var text = "error: \(error.message)\n"
      if let hint = error.hint {
        text += "hint: \(hint)\n"
      }
      return text
    }
  }

  static func json(_ value: some Encodable, pretty: Bool) throws -> String {
    let data = try CLIJSON.makeEncoder(prettyPrinted: pretty).encode(value)
    return String(decoding: data, as: UTF8.self)
  }

  private struct ErrorDocument: Encodable {
    let error: CLIError
  }
}
