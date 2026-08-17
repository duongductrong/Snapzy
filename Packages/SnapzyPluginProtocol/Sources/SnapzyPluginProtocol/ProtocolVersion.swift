import Foundation

/// A semver triple with the one compatibility rule the wire needs.
///
/// The rule is deliberately simple because it is load-bearing: a plugin
/// built against protocol 2.x talking to a 1.x host must get a *readable
/// refusal*, not a hang on a frame nobody understands. Anything more
/// expressive (ranges, prereleases) buys nothing here and costs a fuzzable
/// surface.
public struct ProtocolVersion: Sendable, Hashable, Comparable {
  public let major: Int
  public let minor: Int
  public let patch: Int

  public static let current = ProtocolVersion(major: 1, minor: 0, patch: 0)

  public init(major: Int, minor: Int, patch: Int) {
    self.major = major
    self.minor = minor
    self.patch = patch
  }

  /// Parses "1.2.3". Anything else throws; the wire never sees a version that
  /// was not parseable.
  public init(_ string: String) throws {
    let parts = string.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3,
      let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]),
      major >= 0, minor >= 0, patch >= 0
    else { throw ProtocolError.protocolViolation("unparseable protocol version: \(string)") }
    self.init(major: major, minor: minor, patch: patch)
  }

  public var string: String { "\(major).\(minor).\(patch)" }

  public static func < (lhs: ProtocolVersion, rhs: ProtocolVersion) -> Bool {
    (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
  }

  /// Whether `host` can serve a plugin that declares `plugin`.
  ///
  /// Same major, and the host's minor must be at least the plugin's. Patch
  /// never gates compatibility.
  public static func isCompatible(host: ProtocolVersion, plugin: ProtocolVersion) -> Bool {
    host.major == plugin.major && host.minor >= plugin.minor
  }

  /// The readable refusal produced when the compatibility rule fails.
  public static func incompatibilityReason(host: ProtocolVersion, plugin: ProtocolVersion) -> String {
    if host.major != plugin.major {
      return "protocol major mismatch: host speaks \(host.string), plugin declares \(plugin.string)"
    }
    return "plugin requires newer protocol: host speaks \(host.string), plugin declares \(plugin.string)"
  }
}
