import Foundation
import PluginKitCore

// The finite list of host services a plugin can ask for.
//
// Everything a plugin can make the host do is here. Anything not here is
// unreachable: the sandboxed helper cannot do it itself (zero entitlements)
// and the broker refuses undeclared calls. Adding to this list widens the
// sentence "a plugin can…" — treat every addition as a security decision.

// MARK: - Network

/// `snapzy.network` — `http.fetch`, scoped to an allowlist of hosts.
///
/// Dangerous: exfiltration is the failure mode. Consent copy names the hosts.
public struct SnapzyNetworkAccess: Capability {
  public struct Scope: CapabilityScope {
    /// Lowercased host names (no scheme, no port). `["*"]` means "anything" —
    /// which Snapzy policy narrows to an empty grant: never granted verbatim.
    public var hosts: [String]

    public init(hosts: [String] = []) {
      self.hosts = hosts.map { $0.lowercased() }
    }

    public static var unrestricted: Scope { Scope(hosts: ["*"]) }

    public func attenuated(to limit: Scope) -> Scope? {
      if limit.hosts.isEmpty { return nil }
      if hosts.contains("*") {
        // A wildcard request is only ever narrowed by an explicit host list.
        let narrowed = Scope(hosts: limit.hosts.contains("*") ? [] : limit.hosts)
        return narrowed.hosts.isEmpty ? nil : narrowed
      }
      let narrowed = Scope(hosts: limit.hosts.contains("*") ? hosts : hosts.filter { limit.hosts.contains($0) })
      return narrowed.hosts.isEmpty ? nil : narrowed
    }
  }

  public static let capabilityID: CapabilityID = "snapzy.network"
  public static let sensitivity: CapabilitySensitivity = .dangerous

  private let fetch: @Sendable (PluginHTTPRequest) async throws -> PluginHTTPResponse

  public init(fetch: @escaping @Sendable (PluginHTTPRequest) async throws -> PluginHTTPResponse) {
    self.fetch = fetch
  }

  public func fetch(_ request: PluginHTTPRequest) async throws -> PluginHTTPResponse {
    try await fetch(request)
  }
}

// MARK: - Asset read

/// `snapzy.asset.read` — bytes of the asset/document the user invoked on.
///
/// Per-invocation, never ambient: the handle is only valid while the
/// invocation that owns the token is live.
public struct SnapzyAssetRead: Capability {
  public struct Scope: CapabilityScope {
    /// Document kinds the plugin may read. Empty means unrestricted.
    public var kinds: [SnapzyDocumentKind]

    public init(kinds: [SnapzyDocumentKind] = []) {
      self.kinds = kinds
    }

    public static var unrestricted: Scope { Scope(kinds: []) }

    public func attenuated(to limit: Scope) -> Scope? {
      if limit.kinds.isEmpty { return self }
      if kinds.isEmpty { return limit }
      let narrowed = Scope(kinds: kinds.filter { limit.kinds.contains($0) })
      return narrowed.kinds.isEmpty ? nil : narrowed
    }
  }

  public static let capabilityID: CapabilityID = "snapzy.asset.read"
  public static let sensitivity: CapabilitySensitivity = .sensitive

  private let read: @Sendable () async throws -> Data

  public init(read: @escaping @Sendable () async throws -> Data) {
    self.read = read
  }

  /// The bytes of the current invocation's asset. Throws when the invocation
  /// is no longer live.
  public func read() async throws -> Data {
    try await read()
  }
}

// MARK: - Document write

/// `snapzy.document.write` — the patch channel, scoped to declared ops.
public struct SnapzyDocumentWrite: Capability {
  public struct Scope: CapabilityScope {
    /// Edit operations the plugin may emit.
    public var ops: [DocumentEditKind]

    public init(ops: [DocumentEditKind] = []) {
      self.ops = ops
    }

    public static var unrestricted: Scope { Scope(ops: []) }

    public func attenuated(to limit: Scope) -> Scope? {
      if limit.ops.isEmpty { return self }
      if ops.isEmpty { return limit }
      let narrowed = Scope(ops: ops.filter { limit.ops.contains($0) })
      return narrowed.ops.isEmpty ? nil : narrowed
    }
  }

  public static let capabilityID: CapabilityID = "snapzy.document.write"
  public static let sensitivity: CapabilitySensitivity = .sensitive

  private let write: @Sendable ([DocumentEdit]) async throws -> DocumentPatchResult

  public init(write: @escaping @Sendable ([DocumentEdit]) async throws -> DocumentPatchResult) {
    self.write = write
  }

  public func apply(_ edits: [DocumentEdit]) async throws -> DocumentPatchResult {
    try await write(edits)
  }
}

/// The host's report on an applied patch: what landed, what was skipped and why.
public struct DocumentPatchResult: Codable, Sendable {
  public let applied: Int
  public let skipped: [DocumentPatchSkip]

  public init(applied: Int, skipped: [DocumentPatchSkip] = []) {
    self.applied = applied
    self.skipped = skipped
  }
}

public struct DocumentPatchSkip: Codable, Sendable {
  /// Index of the edit in the submitted array.
  public let index: Int
  public let reason: String

  public init(index: Int, reason: String) {
    self.index = index
    self.reason = reason
  }
}

// MARK: - Benign local services

/// `snapzy.ocr` — local Vision OCR returning lines with boxes.
public struct SnapzyOCR: Capability {
  public static let capabilityID: CapabilityID = "snapzy.ocr"
  public static let sensitivity: CapabilitySensitivity = .benign

  private let recognize: @Sendable (PluginOCRRequest) async throws -> PluginOCRResult

  public init(recognize: @escaping @Sendable (PluginOCRRequest) async throws -> PluginOCRResult) {
    self.recognize = recognize
  }

  public func recognize(_ request: PluginOCRRequest) async throws -> PluginOCRResult {
    try await recognize(request)
  }
}

/// `snapzy.image` — host-side image decode/resize/crop/encode.
public struct SnapzyImage: Capability {
  public static let capabilityID: CapabilityID = "snapzy.image"
  public static let sensitivity: CapabilitySensitivity = .benign

  private let run: @Sendable (PluginImageOperation) async throws -> PluginImageResult

  public init(run: @escaping @Sendable (PluginImageOperation) async throws -> PluginImageResult) {
    self.run = run
  }

  public func run(_ operation: PluginImageOperation) async throws -> PluginImageResult {
    try await run(operation)
  }
}

/// `snapzy.media` — host-side media inspection/extraction (AVFoundation).
public struct SnapzyMedia: Capability {
  public static let capabilityID: CapabilityID = "snapzy.media"
  public static let sensitivity: CapabilitySensitivity = .benign

  private let run: @Sendable (PluginMediaOperation) async throws -> PluginMediaResult

  public init(run: @escaping @Sendable (PluginMediaOperation) async throws -> PluginMediaResult) {
    self.run = run
  }

  public func run(_ operation: PluginMediaOperation) async throws -> PluginMediaResult {
    try await run(operation)
  }
}

/// `snapzy.ui` — declarative host-rendered UI. A plugin never draws.
public struct SnapzyUI: Capability {
  public static let capabilityID: CapabilityID = "snapzy.ui"
  public static let sensitivity: CapabilitySensitivity = .benign

  private let run: @Sendable (PluginUIRequest) async throws -> PluginUIResult

  public init(run: @escaping @Sendable (PluginUIRequest) async throws -> PluginUIResult) {
    self.run = run
  }

  public func run(_ request: PluginUIRequest) async throws -> PluginUIResult {
    try await run(request)
  }
}

/// `snapzy.notify` — a notification / toast.
public struct SnapzyNotify: Capability {
  public static let capabilityID: CapabilityID = "snapzy.notify"
  public static let sensitivity: CapabilitySensitivity = .benign

  private let post: @Sendable (String, String) async throws -> Void

  public init(post: @escaping @Sendable (String, String) async throws -> Void) {
    self.post = post
  }

  public func post(title: String, body: String) async throws {
    try await post(title, body)
  }
}

/// `snapzy.storage` — the plugin's own scoped container.
public struct SnapzyStorage: Capability {
  public static let capabilityID: CapabilityID = "snapzy.storage"
  public static let sensitivity: CapabilitySensitivity = .benign

  private let get: @Sendable (String) async throws -> Data?
  private let set: @Sendable (String, Data?) async throws -> Void

  public init(
    get: @escaping @Sendable (String) async throws -> Data?,
    set: @escaping @Sendable (String, Data?) async throws -> Void
  ) {
    self.get = get
    self.set = set
  }

  public func get(_ key: String) async throws -> Data? {
    try await get(key)
  }

  public func set(_ key: String, to data: Data?) async throws {
    try await set(key, data)
  }
}

// MARK: - Sensitive local services

/// `snapzy.clipboard.write` — write only, by design. The clipboard is a
/// cross-application secret store; a plugin that needs its contents should
/// have the user paste into a host-rendered form.
public struct SnapzyClipboardWrite: Capability {
  public static let capabilityID: CapabilityID = "snapzy.clipboard.write"
  public static let sensitivity: CapabilitySensitivity = .sensitive

  private let writeText: @Sendable (String) async throws -> Void
  private let writeImage: @Sendable (Data) async throws -> Void

  public init(
    writeText: @escaping @Sendable (String) async throws -> Void,
    writeImage: @escaping @Sendable (Data) async throws -> Void
  ) {
    self.writeText = writeText
    self.writeImage = writeImage
  }

  public func writeText(_ text: String) async throws {
    try await writeText(text)
  }

  public func writeImage(_ data: Data) async throws {
    try await writeImage(data)
  }
}

/// `snapzy.secrets` — one Keychain item per plugin, never read back into the
/// helper except as the values the plugin itself wrote.
public struct SnapzySecretsAccess: Capability {
  public static let capabilityID: CapabilityID = "snapzy.secrets"
  public static let sensitivity: CapabilitySensitivity = .sensitive

  private let get: @Sendable (String) async throws -> String?
  private let set: @Sendable (String, String?) async throws -> Void

  public init(
    get: @escaping @Sendable (String) async throws -> String?,
    set: @escaping @Sendable (String, String?) async throws -> Void
  ) {
    self.get = get
    self.set = set
  }

  public func get(_ name: String) async throws -> String? {
    try await get(name)
  }

  public func set(_ name: String, to value: String?) async throws {
    try await set(name, value)
  }
}

// MARK: - Policy

/// Host-side attenuation policy: a manifest asking for `hosts: ["*"]` is
/// narrowed or denied, never granted verbatim.
public enum SnapzyCapabilityPolicy {
  /// The effective network scope for a requested scope under host policy.
  /// `nil` means nothing remains — the request is denied with `scopeEmpty`.
  public static func effectiveNetworkScope(
    requestedHosts: [String],
    policyLimit: [String]?
  ) -> [String]? {
    var hosts = requestedHosts.map { $0.lowercased() }
    if hosts.contains("*") {
      guard let limit = policyLimit, !limit.contains("*") else { return nil }
      hosts = limit
    }
    if let limit = policyLimit {
      hosts = hosts.filter { limit.contains($0) }
    }
    return hosts.isEmpty ? nil : hosts
  }
}
