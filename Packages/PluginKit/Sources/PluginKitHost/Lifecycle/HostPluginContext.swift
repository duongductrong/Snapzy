import Foundation
import PluginKitCore

/// The host's implementation of ``PluginContext``.
///
/// Everything a plugin can reach, assembled per plugin and scoped to its identity.
/// Nothing here consults a global; the whole graph is passed in, which is what
/// makes a plugin's authority enumerable and a fake context in a test trivially
/// constructible.
public final class HostPluginContext: PluginContext {
    public let identity: PluginIdentity
    public let host: HostInfo
    public let logger: PluginLogger
    public let configuration: any ConfigurationStore
    public let storage: any PluginStorage
    public let events: any EventBus

    private let manifest: PluginManifest
    private let trust: TrustLevel
    private let broker: any CapabilityBroker
    let registrar: ContributionRegistrar
    /// Resolves a peer plugin's service. Supplied by the manager rather than held
    /// as a reference to it, so the context has no way to reach the manager's own
    /// API — a plugin cannot enumerate or disable its neighbours.
    private let serviceResolver: @Sendable (ServiceID, PluginID) async throws -> any Sendable
    private let lifecycle: @Sendable () -> AsyncStream<HostLifecycleEvent>

    /// Capability handles are cached per plugin: a second `capability(_:)` call
    /// must not re-prompt the user or rebuild a handle that may own a file
    /// descriptor.
    ///
    /// A lock-guarded box rather than an actor, because ``PluginContext`` exposes
    /// non-`async` properties that actor isolation could not satisfy.
    private let capabilityCache = CapabilityCache()

    /// The designated initialiser. Internal because it takes the manager's own
    /// registrar — an external caller wants the convenience initialiser below,
    /// which makes one.
    init(
        manifest: PluginManifest,
        trust: TrustLevel,
        host: HostInfo,
        logger: PluginLogger,
        configuration: any ConfigurationStore,
        storage: any PluginStorage,
        events: any EventBus,
        broker: any CapabilityBroker,
        registrar: ContributionRegistrar,
        serviceResolver: @escaping @Sendable (ServiceID, PluginID) async throws -> any Sendable,
        lifecycle: @escaping @Sendable () -> AsyncStream<HostLifecycleEvent>
    ) {
        self.identity = manifest.identity
        self.manifest = manifest
        self.trust = trust
        self.host = host
        self.logger = logger
        self.configuration = configuration
        self.storage = storage
        self.events = events
        self.broker = broker
        self.registrar = registrar
        self.serviceResolver = serviceResolver
        self.lifecycle = lifecycle
    }

    /// Builds a context with a fresh registrar.
    ///
    /// The designated initialiser takes a registrar the manager already owns. This
    /// one exists for anything standing a single plugin up on its own — the author
    /// harness above all — so that a test exercises *this* class rather than a
    /// parallel reimplementation of it. A fake context that drifts from the real one
    /// tests nothing worth knowing.
    public convenience init(
        manifest: PluginManifest,
        trust: TrustLevel,
        host: HostInfo,
        logger: PluginLogger,
        configuration: any ConfigurationStore,
        storage: any PluginStorage,
        events: any EventBus,
        broker: any CapabilityBroker,
        serviceResolver: @escaping @Sendable (ServiceID, PluginID) async throws -> any Sendable
            = PluginContextDefaults.noServices,
        lifecycle: @escaping @Sendable () -> AsyncStream<HostLifecycleEvent>
            = PluginContextDefaults.noLifecycleEvents
    ) {
        self.init(
            manifest: manifest,
            trust: trust,
            host: host,
            logger: logger,
            configuration: configuration,
            storage: storage,
            events: events,
            broker: broker,
            registrar: ContributionRegistrar(manifest: manifest),
            serviceResolver: serviceResolver,
            lifecycle: lifecycle
        )
    }

    public func capability<C: Capability>(_ type: C.Type) async throws -> C {
        let id = C.capabilityID
        await registrar.noteCapabilityRequest(id)

        if let cached = capabilityCache.value(for: id) {
            guard let typed = cached as? C else {
                throw CapabilityError.unavailable(id)
            }
            return typed
        }

        // Manifest authority. Not "prompt anyway because the code asked" — a
        // plugin must not be able to reach past its own published disclosure, so
        // an undeclared request is refused before policy is even consulted.
        guard let request = manifest.capabilityRequest(for: id) else {
            throw CapabilityError.undeclared(id)
        }

        let decision = await broker.vend(request, to: identity, trust: trust)
        switch decision {
        case .denied(let error):
            throw error

        case .granted(let capability), .attenuated(let capability, _, _):
            if case .attenuated(_, let requested, let granted) = decision {
                logger.notice("'\(id)' was narrowed from \(requested) to \(granted).")
            }
            guard let typed = capability as? C else {
                // The host registered a factory whose type does not match the
                // capability protocol the plugin asked for. A host bug, but it
                // surfaces on the plugin's side, so name both types.
                throw CapabilityError.scopeMalformed(
                    id,
                    reason: "The host vended \(Swift.type(of: capability)), not \(C.self)."
                )
            }
            capabilityCache.store(typed, for: id)
            return typed
        }
    }

    public func service<S: PluginService>(_ type: S.Type) async throws -> S {
        let value = try await serviceResolver(S.serviceID, identity.id)
        guard let typed = value as? S else {
            throw PluginKitError.misconfigured(
                reason: "Service '\(S.serviceID)' resolved to \(Swift.type(of: value)), not \(S.self)."
            )
        }
        return typed
    }

    public func provide<S: PluginService>(
        _ type: S.Type,
        _ factory: @escaping @Sendable () async throws -> S
    ) async throws {
        try await registrar.provide(service: S.serviceID) { try await factory() }
    }

    public func register<P: ExtensionPoint>(
        _ point: P.Type,
        name: String,
        factory: @escaping @Sendable () async throws -> P.Contract
    ) async throws {
        try await registrar.register(
            point: P.extensionPointID,
            name: name,
            factory: { try await factory() }
        )
    }

    public func lifecycleEvents() -> AsyncStream<HostLifecycleEvent> { lifecycle() }
}

/// Stand-ins for the parts of a context that only a full host can supply.
///
/// Named values rather than inline closures because a throwing closure cannot be a
/// default argument — and naming them makes what a bare context *cannot* do
/// explicit: resolve a peer's service, or observe host lifecycle.
public enum PluginContextDefaults {
    /// There is no peer to ask.
    public static let noServices:
        @Sendable (ServiceID, PluginID) async throws -> any Sendable = { id, _ in
            throw PluginKitError.misconfigured(reason: "No provider for service '\(id)'.")
        }

    /// A stream that finishes immediately, so a plugin's `for await` loop exits
    /// rather than hanging.
    public static let noLifecycleEvents: @Sendable () -> AsyncStream<HostLifecycleEvent> = {
        AsyncStream { $0.finish() }
    }
}

/// Lock-guarded store for a plugin's vended capability handles.
private final class CapabilityCache: @unchecked Sendable {
    private var storage: [CapabilityID: any Capability] = [:]
    private let lock = NSLock()

    func value(for id: CapabilityID) -> (any Capability)? {
        lock.withLock { storage[id] }
    }

    func store(_ capability: any Capability, for id: CapabilityID) {
        lock.withLock { storage[id] = capability }
    }
}
