import Foundation

/// A host service a plugin can be granted access to.
///
/// A capability is the *handle* a plugin receives — a protocol with methods on
/// it — not a permission flag. That distinction is the whole design: a plugin
/// that was denied `fs.read` does not get a handle with a `false` somewhere
/// inside it, it gets a thrown error and no handle at all, so there is no path
/// through the code where an ungranted capability is reachable.
///
/// Declare a capability as a **concrete type whose implementation is injected**,
/// not as a protocol:
///
/// ```swift
/// public struct FileReading: Capability {
///     public struct Scope: CapabilityScope { public var roots: [String] /* … */ }
///     public static let capabilityID: CapabilityID = "fs.read"
///     public static let sensitivity: CapabilitySensitivity = .sensitive
///
///     private let read: @Sendable (String) async throws -> Data
///     public init(read: @escaping @Sendable (String) async throws -> Data) {
///         self.read = read
///     }
///     public func contents(of path: String) async throws -> Data { try await read(path) }
/// }
/// ```
///
/// A protocol would read more naturally and does not work: `any FileReading` does
/// not conform to `FileReading`, so it could never satisfy the `C: Capability`
/// constraint on ``PluginContext/capability(_:)``. The concrete-handle-plus-closure
/// shape gives the same substitutability — the host injects the real reader, a test
/// injects a stub — while staying usable in a generic position.
///
/// - Important: In-process, a capability is a **policy and disclosure** contract,
///   not a security boundary — native code sharing an address space with the host
///   can call `FileManager` directly and ignore the broker entirely. It becomes
///   real enforcement only out-of-process, where the child's sandbox profile is
///   derived from the granted set. A host UI must not imply containment it does
///   not have; see the framework documentation on trust levels.
public protocol Capability: Sendable {
    /// How the grant is attenuated. Defaults to unattenuated for capabilities
    /// where narrowing is meaningless.
    associatedtype Scope: CapabilityScope = UnscopedCapability

    static var capabilityID: CapabilityID { get }
    static var sensitivity: CapabilitySensitivity { get }
}

extension Capability {
    /// Fail-safe default. A capability author who does not think about
    /// sensitivity gets the classification that prompts, not the one that
    /// silently allows.
    public static var sensitivity: CapabilitySensitivity { .sensitive }
}

/// How much a capability needs to be gated.
public enum CapabilitySensitivity: Int, Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    /// No user-visible risk. Logging, the plugin's own storage.
    case benign = 0
    /// Touches user data or the network. Warrants consent.
    case sensitive = 1
    /// Irreversible, or reaches something the user would be alarmed to learn
    /// about. Warrants consent plus an explicit confirmation.
    case dangerous = 2

    public static func < (lhs: CapabilitySensitivity, rhs: CapabilitySensitivity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .benign: return "benign"
        case .sensitive: return "sensitive"
        case .dangerous: return "dangerous"
        }
    }
}

/// The attenuation attached to a grant.
///
/// Capabilities are never vended raw. Not "filesystem access" but "read access
/// to these roots, for these extensions". ``attenuated(to:)`` must only ever
/// *shrink* — that monotonicity is what lets a host layer policy on top of a
/// request without auditing every capability implementation for whether it
/// respects limits.
public protocol CapabilityScope: Codable, Sendable, Equatable {
    /// The widest possible scope. What a request means when it names none.
    static var unrestricted: Self { get }

    /// Narrows `self` to what `limit` permits.
    ///
    /// - Returns: the intersection, or `nil` when nothing remains — which the
    ///   broker reports as ``CapabilityError/scopeEmpty(_:)`` rather than
    ///   granting an empty capability that fails on every call.
    func attenuated(to limit: Self) -> Self?
}

/// The scope for capabilities that cannot be narrowed.
///
/// Use it when attenuation is genuinely meaningless — `notifications.post`, say.
/// Reach for it reluctantly: an unattenuable capability is one a host can only
/// answer yes or no to.
public struct UnscopedCapability: CapabilityScope {
    public init() {}
    public static var unrestricted: UnscopedCapability { UnscopedCapability() }
    public func attenuated(to limit: UnscopedCapability) -> UnscopedCapability? { self }
}

/// The outcome of a capability request.
public enum CapabilityDecision: Sendable {
    case granted(any Capability)
    /// Granted, but narrower than asked for. The plugin is told, so it can adapt
    /// rather than discovering the limit as a series of failed calls.
    case attenuated(any Capability, requested: JSONValue, granted: JSONValue)
    case denied(CapabilityError)

    public var capability: (any Capability)? {
        switch self {
        case .granted(let capability): return capability
        case .attenuated(let capability, _, _): return capability
        case .denied: return nil
        }
    }
}

/// What a user was asked, and about which plugin.
///
/// The prompt names the plugin and quotes its own stated reason. That is not a
/// nicety: without it, a consent dialog triggered by a plugin appears to come
/// from the host app, and the user's decision is attributed to the wrong party
/// and cannot be meaningfully revoked.
public struct ConsentPrompt: Hashable, Sendable {
    public let plugin: PluginIdentity
    public let capability: CapabilityID
    public let sensitivity: CapabilitySensitivity
    /// The plugin's own words, from its manifest.
    public let reason: String
    /// The scope actually being asked for, after policy narrowing, so the user
    /// consents to what will really be granted.
    public let scope: JSONValue

    public init(
        plugin: PluginIdentity,
        capability: CapabilityID,
        sensitivity: CapabilitySensitivity,
        reason: String,
        scope: JSONValue
    ) {
        self.plugin = plugin
        self.capability = capability
        self.sensitivity = sensitivity
        self.reason = reason
        self.scope = scope
    }
}

/// A recorded consent decision.
public enum ConsentDecision: String, Hashable, Sendable, Codable {
    case allowOnce
    case allowAlways
    case denyOnce
    case denyAlways

    public var isAllowed: Bool { self == .allowOnce || self == .allowAlways }
    /// Whether the answer should outlive this launch.
    public var isPersistent: Bool { self == .allowAlways || self == .denyAlways }
}
