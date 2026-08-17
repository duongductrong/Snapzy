import Foundation

// The seams a host implements and a plugin consumes. They live in Core, not in
// the SDK and not in the Host target, because both sides need the *same* type —
// the host to provide it, the plugin to call it. Putting them anywhere else
// would either force a plugin to link the host machinery or force the host to
// link the authoring tooling, and both are exactly the coupling this package
// exists to avoid.

/// A plugin's settings and state.
///
/// Layered underneath: a lookup walks session → managed → user → bundled →
/// schema default and returns the first hit. The plugin sees one flat namespace
/// and does not know or care which layer answered.
public protocol ConfigurationStore: Sendable {
    /// Reads a value, falling back to the key's default.
    ///
    /// **Never throws.** A configuration read sits on the activation path, and a
    /// corrupt preferences file must not be able to stop a plugin from loading —
    /// it should produce default behaviour and a diagnostic. Failures that matter
    /// surface on write, where there is a user action to attach them to.
    func value<Value: Codable & Sendable>(_ key: ConfigKey<Value>) async -> Value

    /// Writes to the user layer.
    ///
    /// - Throws: when the key is fixed by a managed profile, or the value fails
    ///   the schema. Both are real, reportable conditions with a user action
    ///   behind them, which is why this side throws and reads do not.
    func set<Value: Codable & Sendable>(_ key: ConfigKey<Value>, to value: Value) async throws

    /// Whether a managed profile has fixed this key. A settings UI should show a
    /// lock rather than a control the user cannot actually change.
    func isLocked(_ name: String) async -> Bool

    /// Which layer currently answers for a key. For diagnostics and for
    /// explaining a surprising value to whoever is asking.
    func resolvedLayer(_ name: String) async -> ConfigurationLayer?

    func changes() -> AsyncStream<ConfigurationChange>
}

/// A plugin's private container.
///
/// Scoped to the plugin's identity and inescapable: ``containerURL`` resolves
/// under the host's plugin data directory, and the key-value calls cannot address
/// anything outside it. Secrets do not belong here — a token in a plist is a
/// token in a backup.
public protocol PluginStorage: Sendable {
    /// This plugin's directory, created on first access.
    var containerURL: URL { get }

    func data(forKey key: String) async throws -> Data?
    func setData(_ data: Data?, forKey key: String) async throws
    func keys() async throws -> [String]
}

extension PluginStorage {
    /// Convenience for the common case of storing a `Codable` value.
    public func value<Value: Decodable>(_ type: Value.Type, forKey key: String) async throws -> Value? {
        guard let data = try await data(forKey: key) else { return nil }
        return try JSONDecoder().decode(Value.self, from: data)
    }

    public func setValue<Value: Encodable>(_ value: Value?, forKey key: String) async throws {
        guard let value else {
            try await setData(nil, forKey: key)
            return
        }
        try await setData(try JSONEncoder().encode(value), forKey: key)
    }
}

/// Something a plugin or the host can broadcast.
///
/// `Codable` because an event must be able to reach a plugin running in another
/// process. A host that only ever runs plugins in-process still benefits: the
/// constraint is what keeps that option open later.
public protocol PluginEvent: Codable, Sendable {
    static var topic: TopicID { get }
}

/// Broadcast, one-way, no reply.
///
/// Publish and subscribe rights are per-topic capabilities, so a plugin cannot
/// forge a host event or listen to traffic unrelated to what it declared.
///
/// Delivery is best-effort by design. Each subscriber has a bounded buffer and
/// drops its oldest events when it falls behind — a slow subscriber must never be
/// able to stall a publisher, because the publisher is often the host's main
/// actor.
public protocol EventBus: Sendable {
    func publish<Event: PluginEvent>(_ event: Event) async throws
    func subscribe<Event: PluginEvent>(to type: Event.Type) -> AsyncStream<Event>
}

/// Records what the user has decided about capability requests.
///
/// Separate from ``ConfigurationStore`` because consent is not a preference: it
/// is attributable to a specific plugin, revocable independently, and must
/// survive a preferences reset.
public protocol ConsentStore: Sendable {
    /// A previously persisted answer, or `nil` if never asked.
    func decision(for plugin: PluginID, capability: CapabilityID) async -> ConsentDecision?

    /// Asks the user. Implementations without a UI — a daemon, a test — must
    /// fail closed and return a denial rather than blocking forever.
    func requestConsent(_ prompt: ConsentPrompt) async -> ConsentDecision

    func record(_ decision: ConsentDecision, for plugin: PluginID, capability: CapabilityID) async

    /// Forgets decisions. `capability` of `nil` revokes everything for the plugin.
    func revoke(for plugin: PluginID, capability: CapabilityID?) async
}
