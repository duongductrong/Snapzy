import Foundation
import Testing
import SnapzyPluginProtocol

@Suite struct VersionTests {
  @Test func parsing() throws {
    #expect(try ProtocolVersion("1.0.0") == ProtocolVersion(major: 1, minor: 0, patch: 0))
    #expect(try ProtocolVersion("1.10.3").minor == 10)
    #expect(throws: (any Error).self) { try ProtocolVersion("1.0") }
    #expect(throws: (any Error).self) { try ProtocolVersion("x.y.z") }
    #expect(throws: (any Error).self) { try ProtocolVersion("1.0.0-rc1") }
    #expect(throws: (any Error).self) { try ProtocolVersion("-1.0.0") }
  }

  @Test func compatibilityMatrix() throws {
    // (host, plugin, shouldServe) — the full matrix from the phase spec.
    let matrix: [(String, String, Bool)] = [
      ("1.0.0", "1.0.0", true),
      ("1.1.0", "1.0.0", true),
      ("1.1.0", "1.1.0", true),
      ("1.0.0", "1.1.0", false),  // plugin needs newer minor than host has
      ("1.0.9", "1.1.0", false),
      ("2.0.0", "1.0.0", false),  // major mismatch, both directions
      ("1.0.0", "2.0.0", false),
      ("2.0.0", "2.1.0", false),
      ("2.1.0", "2.0.0", true),
    ]
    for (host, plugin, shouldServe) in matrix {
      let hostVersion = try ProtocolVersion(host)
      let pluginVersion = try ProtocolVersion(plugin)
      #expect(
        ProtocolVersion.isCompatible(host: hostVersion, plugin: pluginVersion) == shouldServe,
        "host \(host) plugin \(plugin)"
      )
    }
  }

  @Test func refusalReasonIsReadable() throws {
    let reason = ProtocolVersion.incompatibilityReason(
      host: try ProtocolVersion("1.0.0"), plugin: try ProtocolVersion("1.1.0")
    )
    #expect(reason.contains("1.0.0") && reason.contains("1.1.0"))
    let majorReason = ProtocolVersion.incompatibilityReason(
      host: try ProtocolVersion("1.0.0"), plugin: try ProtocolVersion("2.0.0")
    )
    #expect(majorReason.contains("major"))
  }

  @Test func currentIsCompatibleWithItself() {
    #expect(ProtocolVersion.isCompatible(host: .current, plugin: .current))
  }
}
