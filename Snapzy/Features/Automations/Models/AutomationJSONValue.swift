//
//  AutomationJSONValue.swift
//  Snapzy
//
//  Untyped JSON value used to keep automation parts this build does not know
//  (a trigger, source or step added by a newer Snapzy) byte-for-byte intact
//  when the automation is decoded and saved again.
//

import Foundation

nonisolated enum AutomationJSONValue: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([AutomationJSONValue])
  case object([String: AutomationJSONValue])

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([AutomationJSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: AutomationJSONValue].self))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }

  /// The `kind` member of an object, used to label unsupported parts in the UI and logs.
  var kind: String? {
    guard case .object(let members) = self, case .string(let kind)? = members["kind"] else { return nil }
    return kind
  }
}
