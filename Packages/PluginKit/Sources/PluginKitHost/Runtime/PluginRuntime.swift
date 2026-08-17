import Foundation
import PluginKitCore

/// A way of hosting plugin code.
///
/// Every backend — in-process, XPC, app extension, script — converges on this
/// protocol and on ``PluginInstance``. That convergence is what makes isolation a
/// configuration choice: the manager, the registry, and the lifecycle machinery
/// never learn which one they are talking to.
public protocol PluginRuntime: Sendable {
    var runtimeID: RuntimeID { get }

    /// Whether this backend can host the plugin as found.
    ///
    /// Consulted before selection, so a manifest asking for a runtime the host
    /// does not ship produces a clear ``UnsatisfiedReason`` instead of a load
    /// failure halfway through startup.
    func canHost(_ manifest: PluginManifest, at location: PluginLocation) -> Bool

    /// Prepares an instance. Must not call `activate()`.
    ///
    /// Split from activation so the manager owns the state transition, the timing
    /// measurement, and the failure accounting in one place rather than trusting
    /// each backend to report them consistently.
    func load(
        _ plugin: ResolvedPlugin,
        context: any PluginContext
    ) async throws -> any PluginInstance
}

/// A loaded plugin, whatever and wherever it actually is.
public protocol PluginInstance: Sendable {
    var identity: PluginIdentity { get }

    func activate() async throws

    /// Release. Idempotent, and called under a deadline the manager enforces.
    func deactivate() async

    /// Produces the contract for one contribution, memoised per contribution.
    ///
    /// Erased to `any Sendable` because the concrete contract type belongs to the
    /// host's vocabulary, which no runtime backend can know — and because the value
    /// crosses actor boundaries on its way back, so plain `Any` would be a lie the
    /// compiler correctly refuses. The manager casts it and
    /// reports ``ExtensionPointError/contractTypeMismatch(point:expected:found:)``
    /// with both type names on failure — the plugin author cannot see the host's
    /// stack, so the error has to carry enough to act on.
    func contract(for point: ExtensionPointID, contribution name: String) async throws -> any Sendable

    /// Resolves a service the plugin published.
    func service(_ id: ServiceID) async throws -> any Sendable

    func health() async -> PluginHealth
}

extension PluginInstance {
    public func health() async -> PluginHealth { .ok }
}

/// Everything a runtime needs to bring a plugin up.
///
/// Assembled by the manager after validation and resolution, so a backend never
/// re-derives trust, never re-reads a manifest, and cannot disagree with the
/// manager about either.
public struct ResolvedPlugin: Sendable {
    public let manifest: PluginManifest
    public let location: PluginLocation
    public let source: SourceID
    public let trust: TrustLevel
    public let runtime: RuntimeID
    /// The version of this plugin ID the host last ran, when it is different.
    /// Drives ``Plugin/willUpgrade(from:context:)``.
    public let previousVersion: SemanticVersion?

    public init(
        manifest: PluginManifest,
        location: PluginLocation,
        source: SourceID,
        trust: TrustLevel,
        runtime: RuntimeID,
        previousVersion: SemanticVersion? = nil
    ) {
        self.manifest = manifest
        self.location = location
        self.source = source
        self.trust = trust
        self.runtime = runtime
        self.previousVersion = previousVersion
    }

    public var identity: PluginIdentity { manifest.identity }
}

/// Chooses where a plugin runs.
///
/// A separate seam from ``PluginRuntime`` because *what backends exist* and *which
/// one a given plugin is allowed to use* are different decisions with different
/// owners: the first is what the host shipped, the second is policy.
public protocol RuntimeSelector: Sendable {
    /// - Parameters:
    ///   - requiresInProcess: the plugin contributes to a ``LocalExtensionPoint``,
    ///     so isolation is not an option for it.
    ///   - available: runtimes that reported ``PluginRuntime/canHost(_:at:)``.
    /// - Returns: the chosen runtime, or `nil` to leave the plugin unsatisfied.
    func selectRuntime(
        for manifest: PluginManifest,
        trust: TrustLevel,
        requiresInProcess: Bool,
        available: [RuntimeID]
    ) -> RuntimeID?
}

/// The default selection policy.
///
/// One rule matters: **a plugin does not choose its own isolation.** The manifest
/// states a preference and this decides, because a runtime a plugin could pick for
/// itself would make isolation decorative.
public struct DefaultRuntimeSelector: RuntimeSelector {
    /// The lowest trust level allowed to share the host's address space.
    ///
    /// Defaults to ``TrustLevel/verifiedDeveloper``, so a merely user-installed
    /// bundle is refused in-process hosting.
    public let minimumTrustForInProcess: TrustLevel

    /// Runtimes considered isolating, in preference order. Only these are offered
    /// to a plugin below ``minimumTrustForInProcess``.
    public let isolatingRuntimes: [RuntimeID]

    /// Whether to fall back to in-process when nothing isolating is available.
    ///
    /// Defaults to `false`: fail closed. Until an isolating runtime ships, a
    /// low-trust plugin is reported unsatisfied with a readable reason rather than
    /// quietly given full authority — the honest outcome, and one a host has to
    /// opt out of deliberately.
    public let allowsUnisolatedFallback: Bool

    public init(
        minimumTrustForInProcess: TrustLevel = .verifiedDeveloper,
        isolatingRuntimes: [RuntimeID] = [.xpc, .appExtension, .script],
        allowsUnisolatedFallback: Bool = false
    ) {
        self.minimumTrustForInProcess = minimumTrustForInProcess
        self.isolatingRuntimes = isolatingRuntimes
        self.allowsUnisolatedFallback = allowsUnisolatedFallback
    }

    public func selectRuntime(
        for manifest: PluginManifest,
        trust: TrustLevel,
        requiresInProcess: Bool,
        available: [RuntimeID]
    ) -> RuntimeID? {
        let permitsInProcess = trust >= minimumTrustForInProcess

        // A local-only contract can only run in-process, so trust decides
        // outright. The catalog has already reported this as a locality violation
        // at validation; returning nil here keeps the two consistent.
        if requiresInProcess {
            guard permitsInProcess, available.contains(.inProcess) else { return nil }
            return .inProcess
        }

        if permitsInProcess {
            // Honour the author's preference when it is available. They know
            // whether their plugin is latency-sensitive; the host has already
            // decided they are trusted enough for the choice to be theirs.
            let preferred = manifest.runtime.preferredRuntime
            if available.contains(preferred) { return preferred }
            if available.contains(.inProcess) { return .inProcess }
            return available.first
        }

        if let isolating = isolatingRuntimes.first(where: available.contains) {
            return isolating
        }
        return allowsUnisolatedFallback ? available.first { $0 == .inProcess } : nil
    }
}
