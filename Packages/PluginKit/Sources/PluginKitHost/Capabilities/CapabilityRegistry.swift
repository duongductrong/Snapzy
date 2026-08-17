import Foundation
import PluginKitCore

/// The host's catalogue of what it is willing to vend.
///
/// A capability exists only because a host registered a factory for it. There is
/// no built-in set — PluginKit has no opinion on whether your app should let
/// plugins read files, and inventing one would either be uselessly generic or
/// wrong for most hosts.
///
/// ```swift
/// registry.register((any FileReading).self) { scope, plugin in
///     ScopedFileReader(roots: scope.roots, plugin: plugin)
/// }
/// ```
///
/// The factory receives the *already-attenuated* scope, so an implementation
/// never has to remember to apply limits. Enforcement lives in one place instead
/// of being re-derived in every capability.
public struct CapabilityRegistry: Sendable {
    struct Entry: Sendable {
        let id: CapabilityID
        let sensitivity: CapabilitySensitivity
        let descriptor: CapabilityDescriptor
        /// Builds the handle from an attenuated scope.
        let make: @Sendable (JSONValue, PluginIdentity) async throws -> any Capability
        /// Intersects a requested scope with a policy limit. `nil` out means
        /// nothing remains.
        let attenuate: @Sendable (JSONValue, JSONValue?) throws -> JSONValue?
    }

    private var entries: [CapabilityID: Entry] = [:]

    public init() {}

    /// Registers a capability the host will vend.
    ///
    /// - Parameters:
    ///   - type: the capability protocol, e.g. `(any FileReading).self`.
    ///   - summary: shown in `pluginkit describe` and the emitted catalog.
    ///   - scopeExample: an example scope, so an author can see the shape without
    ///     reading the host's source.
    ///   - factory: builds the handle. Receives the attenuated scope.
    public mutating func register<C: Capability>(
        _ type: C.Type,
        summary: String? = nil,
        scopeExample: JSONValue? = nil,
        factory: @escaping @Sendable (C.Scope, PluginIdentity) async throws -> C
    ) {
        entries[C.capabilityID] = Entry(
            id: C.capabilityID,
            sensitivity: C.sensitivity,
            descriptor: CapabilityDescriptor(
                id: C.capabilityID,
                sensitivity: C.sensitivity,
                summary: summary,
                scopeExample: scopeExample
            ),
            make: { json, identity in
                try await factory(Self.decodeScope(C.Scope.self, from: json, id: C.capabilityID), identity)
            },
            attenuate: { requested, limit in
                let requestedScope = try Self.decodeScope(
                    C.Scope.self, from: requested, id: C.capabilityID
                )
                guard let limit else {
                    // No policy limit means the request stands as written.
                    return try JSONValue(encoding: requestedScope)
                }
                let limitScope = try Self.decodeScope(
                    C.Scope.self, from: limit, id: C.capabilityID
                )
                guard let narrowed = requestedScope.attenuated(to: limitScope) else { return nil }
                return try JSONValue(encoding: narrowed)
            }
        )
    }

    func entry(for id: CapabilityID) -> Entry? { entries[id] }

    public var registeredIDs: [CapabilityID] {
        entries.keys.sorted { $0.rawValue < $1.rawValue }
    }

    /// Descriptors for the emitted catalog.
    public var descriptors: [CapabilityDescriptor] {
        entries.values.map(\.descriptor).sorted { $0.id.rawValue < $1.id.rawValue }
    }

    /// Decodes a scope, treating an absent or empty payload as unrestricted.
    ///
    /// A manifest that names a capability without a `scope` means "as much as you
    /// will give me", not "a scope with every field missing". Without this,
    /// omitting an optional key would be a decoding error rather than the
    /// shorthand every author reasonably expects it to be.
    private static func decodeScope<Scope: CapabilityScope>(
        _ type: Scope.Type,
        from json: JSONValue,
        id: CapabilityID
    ) throws -> Scope {
        if json.isNull || json == .object([:]) { return .unrestricted }
        do {
            return try json.decode(as: Scope.self)
        } catch {
            throw CapabilityError.scopeMalformed(id, reason: String(describing: error))
        }
    }
}

/// Turns a declared request into a grant, a narrower grant, or a refusal.
///
/// A protocol so a host can replace the whole decision procedure — deferring to an
/// entitlement server, say — without reimplementing the registry or the lifecycle
/// around it.
public protocol CapabilityBroker: Sendable {
    func vend(
        _ request: CapabilityRequest,
        to plugin: PluginIdentity,
        trust: TrustLevel
    ) async -> CapabilityDecision
}

/// Host policy for capability requests.
///
/// Resolution runs **managed → per-plugin → per-capability → per-sensitivity →
/// default**, first match wins, and defaults to denial. Managed rulings cannot be
/// overridden by anything, including the user: that is what makes a fleet
/// deployment enforceable rather than advisory.
public struct CapabilityPolicy: Sendable {
    public enum Ruling: Sendable {
        /// Grant it, optionally narrowed to `limit`.
        case allow(limit: JSONValue?)
        /// Ask the user, then grant narrowed to `limit`.
        case requireConsent(limit: JSONValue?)
        case deny(reason: String)

        public static var allow: Ruling { .allow(limit: nil) }
        public static var requireConsent: Ruling { .requireConsent(limit: nil) }
    }

    /// Set by an administrator. Unoverridable.
    public var managed: [CapabilityID: Ruling]
    public var byPlugin: [PluginID: [CapabilityID: Ruling]]
    public var byCapability: [CapabilityID: Ruling]
    public var bySensitivity: [CapabilitySensitivity: Ruling]
    public var fallback: Ruling

    public init(
        managed: [CapabilityID: Ruling] = [:],
        byPlugin: [PluginID: [CapabilityID: Ruling]] = [:],
        byCapability: [CapabilityID: Ruling] = [:],
        bySensitivity: [CapabilitySensitivity: Ruling] = [:],
        fallback: Ruling = .deny(reason: "No policy permits this capability.")
    ) {
        self.managed = managed
        self.byPlugin = byPlugin
        self.byCapability = byCapability
        self.bySensitivity = bySensitivity
        self.fallback = fallback
    }

    /// Deny everything. The safest starting point, and the one a host should have
    /// to consciously move away from.
    public static let denyAll = CapabilityPolicy()

    /// Benign capabilities pass, anything sensitive asks the user.
    ///
    /// The reasonable default for an app with a consent UI.
    public static let promptForSensitive = CapabilityPolicy(
        bySensitivity: [
            .benign: .allow,
            .sensitive: .requireConsent,
            .dangerous: .requireConsent,
        ]
    )

    /// Grant everything without asking.
    ///
    /// For a host that only runs plugins it compiled itself — where the
    /// capability system is documentation and API shape rather than a boundary —
    /// and for tests. Never for third-party code.
    public static let allowAll = CapabilityPolicy(fallback: .allow)

    /// The applicable ruling, and whether it came from managed policy.
    public func ruling(
        for capability: CapabilityID,
        plugin: PluginID,
        sensitivity: CapabilitySensitivity
    ) -> (ruling: Ruling, isManaged: Bool) {
        if let managedRuling = managed[capability] { return (managedRuling, true) }
        if let pluginRuling = byPlugin[plugin]?[capability] { return (pluginRuling, false) }
        if let capabilityRuling = byCapability[capability] { return (capabilityRuling, false) }
        if let sensitivityRuling = bySensitivity[sensitivity] { return (sensitivityRuling, false) }
        return (fallback, false)
    }
}

/// The default broker: registry for construction, ``CapabilityPolicy`` for the
/// decision, ``ConsentStore`` for the user's part.
public struct PolicyCapabilityBroker: CapabilityBroker {
    private let registry: CapabilityRegistry
    private let policy: CapabilityPolicy
    private let consent: any ConsentStore

    public init(
        registry: CapabilityRegistry,
        policy: CapabilityPolicy,
        consent: any ConsentStore
    ) {
        self.registry = registry
        self.policy = policy
        self.consent = consent
    }

    public func vend(
        _ request: CapabilityRequest,
        to plugin: PluginIdentity,
        trust: TrustLevel
    ) async -> CapabilityDecision {
        guard let entry = registry.entry(for: request.id) else {
            return .denied(.unavailable(request.id))
        }

        let (ruling, isManaged) = policy.ruling(
            for: request.id,
            plugin: plugin.id,
            sensitivity: entry.sensitivity
        )

        switch ruling {
        case .deny(let reason):
            return .denied(
                isManaged
                    ? .deniedByManagedPolicy(request.id, reason: reason)
                    : .deniedByPolicy(request.id, reason: reason)
            )

        case .allow(let limit):
            return await grant(request, entry: entry, limit: limit, to: plugin)

        case .requireConsent(let limit):
            // Attenuate *before* prompting, so the user is asked about what will
            // actually be granted rather than about the plugin's opening bid.
            let narrowed: JSONValue
            do {
                guard let result = try entry.attenuate(request.scope, limit) else {
                    return .denied(.scopeEmpty(request.id))
                }
                narrowed = result
            } catch let error as CapabilityError {
                return .denied(error)
            } catch {
                return .denied(.scopeMalformed(request.id, reason: error.localizedDescription))
            }

            if let existing = await consent.decision(for: plugin.id, capability: request.id) {
                guard existing.isAllowed else { return .denied(.deniedByUser(request.id)) }
                return await materialise(
                    entry: entry, requested: request.scope, granted: narrowed, to: plugin
                )
            }

            let decision = await consent.requestConsent(
                ConsentPrompt(
                    plugin: plugin,
                    capability: request.id,
                    sensitivity: entry.sensitivity,
                    reason: request.reason,
                    scope: narrowed
                )
            )
            if decision.isPersistent {
                await consent.record(decision, for: plugin.id, capability: request.id)
            }
            guard decision.isAllowed else { return .denied(.deniedByUser(request.id)) }
            return await materialise(
                entry: entry, requested: request.scope, granted: narrowed, to: plugin
            )
        }
    }

    private func grant(
        _ request: CapabilityRequest,
        entry: CapabilityRegistry.Entry,
        limit: JSONValue?,
        to plugin: PluginIdentity
    ) async -> CapabilityDecision {
        do {
            guard let narrowed = try entry.attenuate(request.scope, limit) else {
                return .denied(.scopeEmpty(request.id))
            }
            return await materialise(
                entry: entry, requested: request.scope, granted: narrowed, to: plugin
            )
        } catch let error as CapabilityError {
            return .denied(error)
        } catch {
            return .denied(.scopeMalformed(request.id, reason: error.localizedDescription))
        }
    }

    private func materialise(
        entry: CapabilityRegistry.Entry,
        requested: JSONValue,
        granted: JSONValue,
        to plugin: PluginIdentity
    ) async -> CapabilityDecision {
        do {
            let capability = try await entry.make(granted, plugin)
            // Telling the plugin it was narrowed lets it adapt up front instead of
            // discovering the boundary as a series of failed calls.
            if granted == requested || requested == .object([:]) {
                return .granted(capability)
            }
            return .attenuated(capability, requested: requested, granted: granted)
        } catch let error as CapabilityError {
            return .denied(error)
        } catch {
            return .denied(.scopeMalformed(entry.id, reason: error.localizedDescription))
        }
    }
}
