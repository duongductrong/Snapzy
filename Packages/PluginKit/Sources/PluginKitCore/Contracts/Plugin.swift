import Foundation

/// What a plugin implements.
///
/// Four members, three of them defaulted. The smallness is deliberate: this type
/// sits on a binary boundary between separately-compiled code, so every
/// requirement added here is a requirement that can never be removed.
///
/// ```swift
/// actor WordCountPlugin: Plugin {
///     init() {}
///
///     func activate(_ context: any PluginContext) async throws {
///         let files = try await context.capability((any FileReading).self)
///         try await context.register(CommandPoint.self, name: "count") {
///             CountCommand(files: files)
///         }
///     }
///
///     func deactivate() async {}
/// }
/// ```
///
/// - Note: Prefer an `actor`. A plugin is called from the host's concurrency
///   domain at times the plugin does not choose — a menu click, a background
///   refresh, a deactivation on quit — and an actor removes that whole class of
///   race rather than documenting a locking discipline nobody will follow. A
///   `final class` marked `@unchecked Sendable` is fine for a stateless plugin.
public protocol Plugin: AnyObject, Sendable {
    /// The host constructs the plugin. Do no work here — nothing is available
    /// yet, and a plugin that fails in `init` cannot report why.
    init()

    /// Claim capabilities and register contributions.
    ///
    /// Throwing here fails the plugin cleanly: it moves to
    /// ``PluginPhase/failed`` with the error attached, the host keeps running,
    /// and everything else keeps working. Throw when a *required* capability is
    /// denied; degrade quietly when an optional one is.
    func activate(_ context: any PluginContext) async throws

    /// Release resources. **Must be idempotent** — the host may call it after a
    /// failed activation, on user disable, and again on quit.
    ///
    /// Runs under a deadline (see `HostConfiguration.deactivationBudget`).
    /// Overrunning escalates: an out-of-process plugin is killed, an in-process
    /// one is abandoned in place rather than unloaded, because its objects may
    /// still be reachable from the host.
    func deactivate() async

    /// Migrate state after an upgrade, before ``activate(_:)``.
    ///
    /// Only called when the host has previously run a different version of this
    /// plugin ID.
    func willUpgrade(from previousVersion: SemanticVersion, context: any PluginContext) async throws

    /// Report health for a manager UI. Say ``PluginHealth/degraded(reason:)``
    /// when an optional capability was denied — the user should learn about
    /// reduced behaviour from the UI, not by noticing a missing button.
    func healthCheck() async -> PluginHealth
}

extension Plugin {
    public func willUpgrade(
        from previousVersion: SemanticVersion,
        context: any PluginContext
    ) async throws {}

    public func healthCheck() async -> PluginHealth { .ok }
}

/// Everything a plugin can reach, and the only thing it can reach.
///
/// There is no `PluginKit.shared`, no global registry, and no ambient service
/// locator anywhere in the framework. A plugin's entire authority arrives through
/// this one value, scoped to its identity — which is what makes "what can this
/// plugin do?" a question with an answer.
///
/// The host implements this. A plugin only ever consumes it.
public protocol PluginContext: Sendable {
    /// This plugin, as the host sees it.
    var identity: PluginIdentity { get }

    /// The app hosting this plugin.
    var host: HostInfo { get }

    /// Log sink, pre-stamped with this plugin's ID.
    var logger: PluginLogger { get }

    /// This plugin's settings. Scoped: one plugin cannot read another's.
    var configuration: any ConfigurationStore { get }

    /// This plugin's private container. Scoped and inescapable.
    var storage: any PluginStorage { get }

    /// Pub/sub, gated per topic by capability.
    var events: any EventBus { get }

    /// Claims a capability declared in the manifest.
    ///
    /// - Throws: ``CapabilityError/undeclared(_:)`` if the manifest never asked
    ///   for it — the manifest is authoritative, so this is refused outright
    ///   rather than prompted for. Otherwise a denial reason.
    func capability<C: Capability>(_ type: C.Type) async throws -> C

    /// Resolves a contract published by another plugin.
    ///
    /// The host brokers it and hands back a proxy, never the provider's own
    /// object: so the wiring can be denied by policy, the provider can live
    /// out-of-process, and a provider crash arrives here as a thrown error
    /// instead of taking this plugin down with it.
    func service<S: PluginService>(_ type: S.Type) async throws -> S

    /// Publishes a contract for other plugins. Must be declared in `provides`.
    func provide<S: PluginService>(
        _ type: S.Type,
        _ factory: @escaping @Sendable () async throws -> S
    ) async throws

    /// Registers a contribution's factory.
    ///
    /// The factory is not called here — it runs the first time something
    /// actually resolves this contribution, and its result is memoised.
    ///
    /// - Throws: ``ExtensionPointError/contributionNotFound(_:)`` if
    ///   `(point, name)` is not declared in the manifest. A plugin cannot
    ///   contribute anything it did not disclose.
    func register<P: ExtensionPoint>(
        _ point: P.Type,
        name: String,
        factory: @escaping @Sendable () async throws -> P.Contract
    ) async throws

    /// Host transitions worth reacting to.
    func lifecycleEvents() -> AsyncStream<HostLifecycleEvent>
}

/// What a plugin is told about its host.
///
/// Enough to adapt, not enough to introspect. A plugin gets the app's identity,
/// version, and the vocabulary versions in play — it does not get a handle on the
/// application object, because that would be an ambient-authority backdoor
/// around every other boundary in the framework.
public struct HostInfo: Hashable, Sendable, Codable {
    /// The host app's bundle identifier.
    public let appIdentifier: String
    public let appVersion: SemanticVersion
    /// The PluginKit generation the host is running.
    public let pluginKitVersion: SemanticVersion
    /// Published vocabularies and their current versions, so a plugin
    /// supporting two host generations can branch without guessing.
    public let vocabularies: [VocabularyID: SemanticVersion]
    /// True when the plugin is running in the host's own address space. Lets an
    /// author avoid work that is only needed when serialising across a boundary.
    public let isInProcess: Bool

    public init(
        appIdentifier: String,
        appVersion: SemanticVersion,
        pluginKitVersion: SemanticVersion = PluginKitVersion.current,
        vocabularies: [VocabularyID: SemanticVersion] = [:],
        isInProcess: Bool
    ) {
        self.appIdentifier = appIdentifier
        self.appVersion = appVersion
        self.pluginKitVersion = pluginKitVersion
        self.vocabularies = vocabularies
        self.isInProcess = isInProcess
    }
}

/// This build of PluginKit.
public enum PluginKitVersion {
    /// The framework's own version. A plugin's `sdkVersion` range is checked
    /// against this at discovery, before anything is loaded.
    ///
    /// The git tag is the version of record; this constant follows it. The
    /// release path rewrites the line below via `Scripts/pluginkit-version set`
    /// before it builds, and CI fails if the two disagree — so edit it by hand
    /// only when you are also moving the tag.
    public static let current: SemanticVersion = "1.0.0"
}

/// A contract one plugin publishes for others.
///
/// Consumers reach it only through ``PluginContext/service(_:)``, so there is no
/// direct plugin-to-plugin edge anywhere in the graph. That keeps a provider
/// swappable, its failures containable, and the wiring subject to policy.
public protocol PluginService: Sendable {
    static var serviceID: ServiceID { get }
    static var serviceVersion: SemanticVersion { get }
}
