import Foundation

/// The handshake vocabulary: host information, the sandbox self-check report,
/// and the two opening frames.
///
/// The report travels in `handshakeAck` so the *host* decides what a probe
/// result means on the OS it is running on (see reports/01-spawn-spike.md:
/// on macOS 26 two of the four probes report allowed). The protocol mandates
/// that the report exist; policy — refuse, warn, or record — belongs to the
/// host's trust tier, not to the wire.
public struct HostInfo: Codable, Sendable, Hashable {
  public let appVersion: String
  public let appBuild: String
  public let osVersion: String
  public let hostID: String

  public init(appVersion: String, appBuild: String, osVersion: String, hostID: String) {
    self.appVersion = appVersion
    self.appBuild = appBuild
    self.osVersion = osVersion
    self.hostID = hostID
  }
}

/// The plugin's self-attestation of containment: the four probes the design
/// claims are denied, run inside the plugin's own process on every launch.
/// `jsGlobalClean` exists only for the legacy script runtime's report; the
/// native SDK omits it and the host treats it as absent.
public struct SandboxSelfCheckReport: Codable, Sendable, Hashable {
  public let networkDenied: Bool
  public let fileSystemDenied: Bool
  public let screenCaptureDenied: Bool
  public let keychainDenied: Bool
  public let jsGlobalClean: Bool?
  public let diagnostics: [String]

  public init(
    networkDenied: Bool,
    fileSystemDenied: Bool,
    screenCaptureDenied: Bool,
    keychainDenied: Bool,
    jsGlobalClean: Bool? = nil,
    diagnostics: [String] = []
  ) {
    self.networkDenied = networkDenied
    self.fileSystemDenied = fileSystemDenied
    self.screenCaptureDenied = screenCaptureDenied
    self.keychainDenied = keychainDenied
    self.jsGlobalClean = jsGlobalClean
    self.diagnostics = diagnostics
  }
}

/// Host → plugin, the first frame. Carries the host's protocol version, its
/// identity, and the contract vocabulary it serves as a JSON object
/// (`{"com.snapzy.api": "1.0.0"}`). `contracts` is intentionally untyped
/// JSON: the protocol layer validates JSON-ness, the host validates
/// semantics against `PluginKitCore`.
public struct HandshakeRequest: Codable, Sendable, Hashable {
  public let protocolVersion: String
  public let host: HostInfo
  public let contracts: JSONValue

  public init(protocolVersion: ProtocolVersion, host: HostInfo, contracts: JSONValue) {
    self.protocolVersion = protocolVersion.string
    self.host = host
    self.contracts = contracts
  }
}

/// Plugin → host, the reply to `handshake`. `declaredContracts` mirrors the
/// binary's view of its `plugin.json` contracts as a JSON array, so the host
/// can catch a stale rebuild without activating.
public struct HandshakeAck: Codable, Sendable, Hashable {
  public let protocolVersion: String
  public let sdkVersion: String
  public let declaredContracts: JSONValue
  public let sandboxSelfCheck: SandboxSelfCheckReport

  public init(
    protocolVersion: ProtocolVersion,
    sdkVersion: String,
    declaredContracts: JSONValue,
    sandboxSelfCheck: SandboxSelfCheckReport
  ) {
    self.protocolVersion = protocolVersion.string
    self.sdkVersion = sdkVersion
    self.declaredContracts = declaredContracts
    self.sandboxSelfCheck = sandboxSelfCheck
  }
}

/// A log line the plugin sends; the host stamps the plugin id when it writes
/// it to the diagnostic log. Levels match the host's DiagnosticLogger.
public struct PluginLogEntry: Codable, Sendable, Hashable {
  public let level: String
  public let message: String
  public let invocationID: UUID?

  public init(level: String, message: String, invocationID: UUID? = nil) {
    self.level = level
    self.message = message
    self.invocationID = invocationID
  }
}
