import Foundation
import PluginKitCore

// Host-internal transport types for the Snapzy ↔ SnapzyPluginHost XPC channel.
//
// NOT part of the public plugin vocabulary: plugin authors never see or touch
// these. They live in this package only because the XPC helper target and the
// app target both compile against them and must agree byte-for-byte, and an
// SPM product is the cheapest way to share one Codable definition without
// duplicating files across targets.

public enum SnapzyPluginIPC {
  /// Service name under Contents/XPCServices/. Must match the helper's
  /// CFBundleIdentifier.
  public static let serviceName = "com.trongduong.snapzy.pluginhost"

  /// The result envelope shared by every reply.
  public enum Outcome: Codable, Sendable, Hashable {
    case success(JSONValue)
    case failure(code: String, message: String)
  }

  /// Helper for embedding binary data in a `JSONValue` payload: a
  /// single-key object `{ "base64": "<…>" }`. Unambiguous, so a text body
  /// can never be mistaken for bytes.
  public static func binary(_ data: Data) -> JSONValue {
    .object(["base64": .string(data.base64EncodedString())])
  }

  public static func binaryData(_ value: JSONValue) -> Data? {
    guard case .object(let object) = value,
      object.count == 1,
      case .string(let encoded)? = object["base64"]
    else { return nil }
    return Data(base64Encoded: encoded)
  }

  // MARK: Load

  /// App → helper: load and evaluate one plugin bundle.
  public struct LoadRequest: Codable, Sendable, Hashable {
    public let pluginID: String
    /// The manifest, as decoded JSON. Authoritative for what the helper
    /// reports; the host has already validated it.
    public let manifest: JSONValue
    /// Entry script name, e.g. "main.js".
    public let entry: String
    /// The bundled script source. Sent as bytes because the helper's sandbox
    /// cannot read the plugin directory — the host reads files; helpers get
    /// bytes.
    public let source: String
    /// Ceiling on the helper's memory (bytes) and execution time (seconds).
    public let memoryLimitBytes: UInt64
    public let executionTimeLimit: TimeInterval

    public init(
      pluginID: String,
      manifest: JSONValue,
      entry: String,
      source: String,
      memoryLimitBytes: UInt64,
      executionTimeLimit: TimeInterval
    ) {
      self.pluginID = pluginID
      self.manifest = manifest
      self.entry = entry
      self.source = source
      self.memoryLimitBytes = memoryLimitBytes
      self.executionTimeLimit = executionTimeLimit
    }
  }

  public struct LoadResponse: Codable, Sendable, Hashable {
    public let ok: Bool
    public let errorMessage: String?
    /// Whether JIT is active (for diagnostics; interpreter fallback is fine).
    public let jitAvailable: Bool

    public init(ok: Bool, errorMessage: String? = nil, jitAvailable: Bool = false) {
      self.ok = ok
      self.errorMessage = errorMessage
      self.jitAvailable = jitAvailable
    }
  }

  // MARK: Activation

  /// App → helper: activate one loaded plugin.
  public struct ActivateRequest: Codable, Sendable, Hashable {
    public let pluginID: String
    /// The plugin's configuration values (settings schema results), as JSON.
    public let options: JSONValue

    public init(pluginID: String, options: JSONValue) {
      self.pluginID = pluginID
      self.options = options
    }
  }

  // MARK: Command handling

  /// App → helper: run `plugin.handle(request, ctx)`.
  public struct CommandRequest: Codable, Sendable, Hashable {
    public let invocationID: UUID
    /// `SnapzyCommandRequest` encoded as JSON.
    public let request: JSONValue

    public init(invocationID: UUID, request: JSONValue) {
      self.invocationID = invocationID
      self.request = request
    }
  }

  /// Helper → app: the settled result of a command.
  public struct CommandResponse: Codable, Sendable, Hashable {
    public let invocationID: UUID
    public let outcome: Outcome

    public init(invocationID: UUID, outcome: Outcome) {
      self.invocationID = invocationID
      self.outcome = outcome
    }
  }

  // MARK: Host calls

  /// Helper → app: a brokered host-service call (every `ctx.*` method).
  public struct HostCall: Codable, Sendable, Hashable {
    public let callID: UUID
    public let pluginID: String
    /// Scopes `asset.read`; nil for calls outside an invocation.
    public let invocationID: UUID?
    /// "http.fetch", "asset.read", "ocr.recognize", "image.run", …
    public let service: String
    public let payload: JSONValue

    public init(
      callID: UUID,
      pluginID: String,
      invocationID: UUID?,
      service: String,
      payload: JSONValue
    ) {
      self.callID = callID
      self.pluginID = pluginID
      self.invocationID = invocationID
      self.service = service
      self.payload = payload
    }
  }

  public struct HostCallResult: Codable, Sendable, Hashable {
    public let callID: UUID
    public let outcome: Outcome

    public init(callID: UUID, outcome: Outcome) {
      self.callID = callID
      self.outcome = outcome
    }
  }

  // MARK: Progress

  /// Helper → app: progress on a live invocation (from `ctx.ui.progress`).
  public struct ProgressUpdate: Codable, Sendable, Hashable {
    public let invocationID: UUID
    public let fraction: Double?
    public let message: String?

    public init(invocationID: UUID, fraction: Double? = nil, message: String? = nil) {
      self.invocationID = invocationID
      self.fraction = fraction
      self.message = message
    }
  }

  // MARK: Cancellation

  public struct CancelRequest: Codable, Sendable, Hashable {
    public let invocationID: UUID

    public init(invocationID: UUID) {
      self.invocationID = invocationID
    }
  }

  // MARK: Health

  public struct HealthRequest: Codable, Sendable, Hashable {
    public let pluginID: String

    public init(pluginID: String) {
      self.pluginID = pluginID
    }
  }

  public struct HealthResponse: Codable, Sendable, Hashable {
    public let status: String // "ok" | "unresponsive" | "crashed"

    public init(status: String) {
      self.status = status
    }
  }

  // MARK: Sandbox self-check

  /// Helper → app: results of the helper attempting, *inside its own
  /// sandbox*, the exact operations it must be denied. The security claim,
  /// asserted by tests rather than prose.
  public struct SandboxSelfCheckRequest: Codable, Sendable, Hashable {
    public init() {}
  }

  public struct SandboxSelfCheckResult: Codable, Sendable, Hashable {
    /// A socket connect to a public DNS server must fail.
    public let networkDenied: Bool
    /// Reading ~/Desktop must fail.
    public let fileSystemDenied: Bool
    /// Screen capture via CGWindowListCreateImage must fail.
    public let screenCaptureDenied: Bool
    /// Keychain access must fail.
    public let keychainDenied: Bool
    /// The JS global must expose no process/require/fetch bindings.
    public let jsGlobalClean: Bool
    public let diagnostics: [String]

    public init(
      networkDenied: Bool,
      fileSystemDenied: Bool,
      screenCaptureDenied: Bool,
      keychainDenied: Bool,
      jsGlobalClean: Bool,
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

  // MARK: Deactivation

  public struct DeactivateRequest: Codable, Sendable, Hashable {
    public let pluginID: String

    public init(pluginID: String) {
      self.pluginID = pluginID
    }
  }
}
