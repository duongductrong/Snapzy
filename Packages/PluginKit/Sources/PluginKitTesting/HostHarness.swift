import Foundation
import PluginKitCore
import PluginKitHost
import PluginKitInProcess

/// Stands up a real ``PluginManager`` over in-memory everything.
///
/// The host-facing half of the testing story. Everything is real except where the
/// plugins come from and where their data goes, so a test exercises the actual
/// discovery, validation, resolution, and lazy-activation paths rather than a
/// simplified stand-in.
///
/// ```swift
/// let manager = HostHarness.manager(
///     plugins: [(manifest, { WordCountPlugin() })]
/// ) { configuration in
///     configuration.extensionPoints.register(CommandPoint.self)
/// }
/// await manager.start()
/// ```
public enum HostHarness {
    /// Builds a manager hosting the given plugins.
    ///
    /// - Parameters:
    ///   - plugins: manifest and factory pairs. The factory is only ever called if
    ///     something resolves one of the plugin's contributions, which is what makes
    ///     "nothing loaded until used" testable — count the calls.
    ///   - trust: trust level to report. ``TrustLevel/firstParty`` by default so
    ///     in-process hosting is permitted; drop it to
    ///     ``TrustLevel/sandboxedOnly`` to test the refusal path.
    ///   - configure: register extension points and capabilities here.
    public static func manager(
        plugins: [(manifest: PluginManifest, factory: @Sendable () -> any Plugin)],
        trust: TrustLevel = .firstParty,
        appIdentifier: String = "com.example.host",
        appVersion: SemanticVersion = "1.0.0",
        configure: (inout HostConfiguration) -> Void = { _ in }
    ) -> PluginManager {
        var factories: [PluginID: @Sendable () -> any Plugin] = [:]
        for entry in plugins { factories[entry.manifest.id] = entry.factory }

        var configuration = HostConfiguration.inMemory(
            appIdentifier: appIdentifier,
            appVersion: appVersion
        )
        configuration.sources = [
            RegisteredPluginSource(
                trustHint: Self.hint(for: trust),
                manifests: plugins.map(\.manifest)
            )
        ]
        configuration.runtimes = [InProcessPluginRuntime.registering(factories)]
        configuration.trustPolicy = FixedTrustPolicy(level: trust)
        // Wide-open topics: a test asserting on event delivery should not also have
        // to configure an ACL, and the ACL itself is tested separately.
        configuration.defaultPublishableTopics = ["*"]
        configuration.defaultSubscribableTopics = ["*"]
        configure(&configuration)
        return PluginManager(configuration: configuration)
    }

    private static func hint(for trust: TrustLevel) -> TrustHint {
        switch trust {
        case .firstParty: return .firstParty
        case .verifiedDeveloper: return .managed
        case .sandboxedOnly: return .userInstalled
        }
    }
}

/// Reports one trust level for everything.
///
/// Lets a test drive trust-dependent behaviour — locality violations, refused
/// in-process hosting — without producing signed bundles on disk.
public struct FixedTrustPolicy: TrustPolicy {
    public let level: TrustLevel

    public init(level: TrustLevel) { self.level = level }

    public func evaluate(_ candidate: DiscoveredPlugin) async -> TrustDecision {
        .trusted(level)
    }
}

/// Blocks everything, with a stated reason.
public struct BlockingTrustPolicy: TrustPolicy {
    public let reason: PluginTrustError

    public init(reason: PluginTrustError = .unsigned) { self.reason = reason }

    public func evaluate(_ candidate: DiscoveredPlugin) async -> TrustDecision {
        .blocked(reason: reason)
    }
}

/// Counts how many times a plugin type was constructed.
///
/// The instrument for the laziness guarantee: a host that lists sixty plugins'
/// contributions should have constructed zero of them.
///
/// Lock-backed rather than an actor because a plugin factory is *synchronous* — an
/// actor would force a fire-and-forget `Task` to record into, which races the very
/// assertion this exists to make.
public final class InstantiationCounter: @unchecked Sendable {
    private var counts: [PluginID: Int] = [:]
    private let lock = NSLock()

    public init() {}

    public func record(_ id: PluginID) {
        lock.withLock { counts[id, default: 0] += 1 }
    }

    public func count(for id: PluginID) -> Int {
        lock.withLock { counts[id] ?? 0 }
    }

    public var total: Int {
        lock.withLock { counts.values.reduce(0, +) }
    }

    /// Wraps a factory so construction is recorded.
    public func tracking(
        _ id: PluginID,
        _ factory: @escaping @Sendable () -> any Plugin
    ) -> @Sendable () -> any Plugin {
        { [self] in
            record(id)
            return factory()
        }
    }
}
