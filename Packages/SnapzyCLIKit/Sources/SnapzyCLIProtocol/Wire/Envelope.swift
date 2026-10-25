//
//  Envelope.swift
//  SnapzyCLIProtocol
//
//  Request/response envelopes carried in each frame. A receiver decodes the
//  untyped header first to route by method, then decodes the same payload
//  again with the method's concrete params type.
//

import Foundation

public struct CLIRequestHeader: Decodable, Sendable, Equatable {
  public let id: UInt64
  public let method: String
}

public struct CLIRequestEnvelope<Params: Codable & Sendable>: Codable, Sendable {
  public let id: UInt64
  public let method: String
  public let params: Params

  public init(id: UInt64, method: CLIMethod, params: Params) {
    self.id = id
    self.method = method.rawValue
    self.params = params
  }
}

public struct CLIResponseEnvelope<Result: Codable & Sendable>: Codable, Sendable {
  public let id: UInt64
  public let result: Result?
  public let error: CLIError?

  public init(id: UInt64, result: Result) {
    self.id = id
    self.result = result
    error = nil
  }

  public init(id: UInt64, error: CLIError) {
    self.id = id
    result = nil
    self.error = error
  }
}

/// Params or result for methods that carry nothing.
public struct CLIEmpty: Codable, Sendable, Equatable {
  public init() {}
}
