//
//  ProtocolVersion.swift
//  SnapzyCLIProtocol
//
//  Wire protocol version exchanged in the hello handshake. Encoded as
//  "major.minor"; peers are compatible when the major versions match.
//

import Foundation

public struct ProtocolVersion: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
  public static let current = ProtocolVersion(major: 1, minor: 0)

  public let major: Int
  public let minor: Int

  public init(major: Int, minor: Int) {
    self.major = major
    self.minor = minor
  }

  public init?(string: String) {
    let parts = string.split(separator: ".", omittingEmptySubsequences: false)
    guard
      parts.count == 2,
      let major = Int(parts[0]), major >= 0,
      let minor = Int(parts[1]), minor >= 0
    else { return nil }
    self.init(major: major, minor: minor)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)
    guard let version = ProtocolVersion(string: string) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid protocol version \"\(string)\""
      )
    }
    self = version
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }

  public var description: String {
    "\(major).\(minor)"
  }

  public func isCompatible(with other: ProtocolVersion) -> Bool {
    major == other.major
  }

  public static func < (lhs: ProtocolVersion, rhs: ProtocolVersion) -> Bool {
    (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
  }
}
