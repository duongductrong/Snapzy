import Foundation
@_exported import PluginKitCore
import PluginKitHost
import PluginKitSDK

/// Runs one plugin against a fake host.
///
/// The author-facing half of the testing story. A plugin author does not have a
/// host app to test against, and cannot attach a debugger to a shipped one, so
/// without this the only way to find out whether a plugin activates cleanly under a
/// denied capability is to ship it.
///
/// It is built from the *real* ``HostPluginContext``, the real
/// ``PolicyCapabilityBroker``, and the real layered configuration store. That is
/// deliberate: a hand-written fake context would drift from the host's behaviour and
/// then confidently report a passing test.
///
/// ```swift
/// let harness = PluginHarness(manifest: manifest)
/// await harness.grant((any FileReading).self, StubFileReader(files: ["a.md": "# Hi"]))
/// await harness.deny("net.http")
///
/// try await harness.activate(WordCountPlugin())
///
/// let result = try await harness.invoke(CommandPoint.self, name: "count", RunCommand(...))
/// #expect(result.didHandle)
/// #expect(await harness.drift().isEmpty)
/// ```
public actor PluginHarness {
    /// How contract calls are delivered.
    public enum Transport: String, Sendable, CaseIterable {
        /// Straight through. Fastest, and what an in-process host does.
        case direct

        /// Every request and response is round-tripped through JSON first.
        ///
        /// The check worth running in CI. It catches the assumptions that make a
        /// contract quietly un-remotable — a reference type smuggled through, a
        /// `Codable` that does not round-trip, an identity comparison that survives
        /// in-process and breaks over XPC — without any of the setup an actual
        /// out-of-process test needs. Get this passing and moving the plugin behind
        /// an isolation boundary later stops being a surprise.
        case serializing
    }

    public let manifest: PluginManifest
    public var transport: Transport

    private let identity: PluginIdentity
    private var registry = CapabilityRegistry()
    private var policy = CapabilityPolicy(fallback: .allow)
    private let consent = AllowingConsentStore()
    private let recorder = LogRecorder()
    private let bus = RecordingEventBus()

    private var settings: [String: JSONValue] = [:]
    private var managed: [String: JSONValue] = [:]
    private let store: LayeredConfigurationStore
    private let pluginStorage = InMemoryPluginStorage()

    private var context: HostPluginContext?
    private var plugin: (any Plugin)?
    private var deactivationCount = 0

    public init(
        manifest: PluginManifest,
        transport: Transport = .direct,
        appIdentifier: String = "com.example.host",
        appVersion: SemanticVersion = "1.0.0"
    ) {
        self.manifest = manifest
        self.transport = transport
        self.identity = manifest.identity
        self.store = LayeredConfigurationStore(
            identity: manifest.identity,
            schema: manifest.configuration
        )
    }

    // MARK: - Arranging the world

    /// Makes a capability available, backed by whatever stub the author supplies.
    ///
    /// The manifest still has to declare it. A harness that granted an undeclared
    /// capability would hide exactly the drift the host will refuse at runtime.
    public func grant<C: Capability>(_ type: C.Type, _ instance: C) {
        registry.register(C.self) { _, _ in instance }
    }

    /// Makes a capability available through a factory, so the author can assert on
    /// the attenuated scope the host would actually pass.
    public func grant<C: Capability>(
        _ type: C.Type,
        factory: @escaping @Sendable (C.Scope, PluginIdentity) async throws -> C
    ) {
        registry.register(C.self, factory: factory)
    }

    /// Refuses a capability, as a host's policy would.
    public func deny(_ id: CapabilityID, reason: String = "Denied by the harness.") {
        policy.byCapability[id] = .deny(reason: reason)
    }

    /// Grants a capability but narrows it, to test what the plugin does with less
    /// than it asked for.
    public func limit(_ id: CapabilityID, to scope: JSONValue) {
        policy.byCapability[id] = .allow(limit: scope)
    }

    /// Seeds the user configuration layer.
    public func setSetting(_ name: String, to value: JSONValue) async {
        settings[name] = value
        await store.replace(layer: .user, with: settings)
    }

    /// Seeds the managed layer, which the plugin cannot write to.
    public func setManagedSetting(_ name: String, to value: JSONValue) async {
        managed[name] = value
        await store.replace(layer: .managed, with: managed)
    }

    // MARK: - Driving the plugin

    /// Activates the plugin against the configured world.
    ///
    /// - Throws: whatever the plugin throws, and whatever the broker refuses. A
    ///   required-capability denial surfacing here is the correct behaviour, not a
    ///   harness failure.
    @discardableResult
    public func activate(_ plugin: any Plugin) async throws -> any PluginContext {
        let context = HostPluginContext(
            manifest: manifest,
            trust: .firstParty,
            host: HostInfo(
                appIdentifier: "com.example.host",
                appVersion: "1.0.0",
                vocabularies: Dictionary(
                    manifest.contracts.map { ($0.vocabulary, $0.builtAgainst) },
                    uniquingKeysWith: max
                ),
                // Reported as in-process even under `.serializing`, because that is
                // what a plugin would see in the runtime being simulated. Lying the
                // other way would let an author gate the very code the serializing
                // transport exists to exercise.
                isInProcess: true
            ),
            logger: PluginLogger(sink: recorder, plugin: identity.id),
            configuration: store,
            storage: pluginStorage,
            events: bus,
            broker: PolicyCapabilityBroker(
                registry: registry, policy: policy, consent: consent
            )
        )

        self.context = context
        self.plugin = plugin
        try await plugin.activate(context)
        return context
    }

    /// Deactivates, counting the calls so idempotence can be asserted.
    public func deactivate() async {
        deactivationCount += 1
        await plugin?.deactivate()
    }

    public var timesDeactivated: Int { deactivationCount }

    /// The contract for one registered contribution.
    public func contract<P: ExtensionPoint>(
        _ point: P.Type,
        name: String
    ) async throws -> P.Contract {
        guard let context else {
            throw PluginKitError.misconfigured(reason: "Call activate(_:) first.")
        }
        let value = try await context.resolveContribution(point: P.extensionPointID, name: name)
        guard let typed = value as? P.Contract else {
            throw PluginKitError.extensionPoint(
                .contractTypeMismatch(
                    point: P.extensionPointID,
                    expected: String(describing: P.Contract.self),
                    found: String(describing: type(of: value))
                )
            )
        }
        return typed
    }

    /// Calls a remotable contribution, honouring ``transport``.
    ///
    /// Under ``Transport/serializing`` both the request and the response cross a
    /// JSON round-trip, which is what makes this a remotability check rather than
    /// just a call.
    public func invoke<P: RemotableExtensionPoint>(
        _ point: P.Type,
        name: String,
        _ request: P.Request
    ) async throws -> P.Response {
        let contract = try await contract(P.self, name: name)

        switch transport {
        case .direct:
            return try await P.invoke(contract, with: request)
        case .serializing:
            let wireRequest = try Self.roundTrip(request)
            let response = try await P.invoke(contract, with: wireRequest)
            return try Self.roundTrip(response)
        }
    }

    /// A service the plugin published.
    public func service<S: PluginService>(_ type: S.Type) async throws -> S {
        guard let context else {
            throw PluginKitError.misconfigured(reason: "Call activate(_:) first.")
        }
        let value = try await context.resolveProvidedService(S.serviceID)
        guard let typed = value as? S else {
            throw PluginKitError.misconfigured(
                reason: "Service '\(S.serviceID)' resolved to \(Swift.type(of: value))."
            )
        }
        return typed
    }

    // MARK: - Assertions

    /// Differences between what the manifest declares and what the code did.
    ///
    /// Manifest *generation* from code needs macro machinery. Detecting drift needs
    /// none — activate the plugin, record what it registers and requests, diff. So
    /// the invariant is available now, and a build step can fail on it.
    public func drift() async -> [ManifestDrift] {
        guard let context else { return [] }
        let observed = await context.activationRecord()
        var findings: [ManifestDrift] = []

        let declaredContributions = Set(
            manifest.contributions.map { "\($0.extensionPoint)#\($0.name)" }
        )
        let registered = Set(observed.contributions.map { "\($0.extensionPoint)#\($0.name)" })

        for contribution in manifest.contributions
        where !registered.contains("\(contribution.extensionPoint)#\(contribution.name)") {
            findings.append(
                .declaredButNotRegistered(
                    point: contribution.extensionPoint, name: contribution.name
                )
            )
        }
        for key in observed.contributions
        where !declaredContributions.contains("\(key.extensionPoint)#\(key.name)") {
            findings.append(
                .registeredButNotDeclared(point: key.extensionPoint, name: key.name)
            )
        }

        let declaredCapabilities = Set(manifest.capabilities.map(\.id))
        for id in observed.capabilities.subtracting(declaredCapabilities) {
            findings.append(.capabilityUsedButNotDeclared(id))
        }
        for id in declaredCapabilities.subtracting(observed.capabilities) {
            findings.append(.capabilityDeclaredButUnused(id))
        }

        let declaredServices = Set(manifest.provides.map(\.id))
        for id in Set(observed.services).subtracting(declaredServices) {
            findings.append(.serviceProvidedButNotDeclared(id))
        }

        return findings.sorted { $0.description < $1.description }
    }

    /// Everything the plugin logged.
    public func messages() async -> [String] { await recorder.messages() }

    /// Everything the plugin published.
    public func published<Event: PluginEvent>(_ type: Event.Type) async -> [Event] {
        await bus.events(of: type)
    }

    public func storage() -> any PluginStorage { pluginStorage }

    public func configuration() -> any ConfigurationStore { store }

    /// Round-trips through JSON, wrapped in an array so that a top-level scalar
    /// `Request` works on every Foundation version rather than only where
    /// fragment encoding is permitted.
    private static func roundTrip<Value: Codable & Sendable>(_ value: Value) throws -> Value {
        let data = try JSONEncoder().encode([value])
        guard let decoded = try JSONDecoder().decode([Value].self, from: data).first else {
            throw PluginKitError.misconfigured(
                reason: "\(Value.self) did not survive a JSON round-trip."
            )
        }
        return decoded
    }
}

/// Collects log output for assertions.
private actor LogStore {
    var lines: [String] = []
    func append(_ line: String) { lines.append(line) }
}

/// `PluginLogging` is synchronous, so the sink buffers under a lock and the actor
/// above is not needed — but tests want an `await`-able accessor, so this keeps both.
final class LogRecorder: PluginLogging, @unchecked Sendable {
    private var lines: [String] = []
    private let lock = NSLock()

    func log(
        _ level: PluginLogLevel,
        plugin: PluginID?,
        _ message: @autoclosure () -> String
    ) {
        let line = "[\(level)] \(plugin?.rawValue ?? "host"): \(message())"
        lock.withLock { lines.append(line) }
    }

    func messages() async -> [String] { lock.withLock { lines } }
}
