import Foundation
import PluginKitCore

/// Everything the host knows about one installed plugin.
///
/// The type a plugin manager UI binds to. It deliberately carries the *reasons*
/// alongside the state: a plugin that cannot run has an ``unsatisfied`` reason, one
/// running with caveats has ``warnings``, and one that failed has ``lastError``.
/// Nothing about a plugin's condition is only in a log file.
public struct PluginRecord: Sendable, Identifiable {
    public let manifest: PluginManifest
    public let source: SourceID
    public let location: PluginLocation
    public let trust: TrustLevel

    public var phase: PluginPhase
    /// Populated exactly when `phase == .unsatisfied`.
    public var unsatisfied: UnsatisfiedReason?
    /// Non-fatal conditions worth surfacing: a deprecated contract, a denied
    /// optional capability, running unisolated.
    public var warnings: [PluginWarning]
    /// Chosen once the plugin resolves.
    public var runtime: RuntimeID?
    public var lastError: String?
    /// Failed load or activation attempts, against the host's budget.
    public var failureCount: Int
    /// How long `activate()` took. A plugin costing 400ms of launch time should be
    /// visible as such, not merely suspected.
    public var activationDuration: Duration?
    /// Whether the user has explicitly enabled or disabled this plugin.
    public var userEnabled: Bool?

    public init(
        manifest: PluginManifest,
        source: SourceID,
        location: PluginLocation,
        trust: TrustLevel,
        phase: PluginPhase = .discovered,
        unsatisfied: UnsatisfiedReason? = nil,
        warnings: [PluginWarning] = [],
        runtime: RuntimeID? = nil,
        lastError: String? = nil,
        failureCount: Int = 0,
        activationDuration: Duration? = nil,
        userEnabled: Bool? = nil
    ) {
        self.manifest = manifest
        self.source = source
        self.location = location
        self.trust = trust
        self.phase = phase
        self.unsatisfied = unsatisfied
        self.warnings = warnings
        self.runtime = runtime
        self.lastError = lastError
        self.failureCount = failureCount
        self.activationDuration = activationDuration
        self.userEnabled = userEnabled
    }

    public var id: PluginID { manifest.id }
    public var identity: PluginIdentity { manifest.identity }

    /// Whether this plugin's contributions should appear in the registry.
    public var isAvailable: Bool { phase.contributesToRegistry }

    /// One line for a manager UI, honest about what the user is actually getting.
    ///
    /// The in-process case says "full app access" rather than listing permissions,
    /// because an in-process capability grant is a disclosure contract and not a
    /// boundary — implying containment that does not exist would be the most
    /// misleading thing this framework could do.
    public var trustSummary: String {
        switch trust {
        case .firstParty:
            return "Bundled with the app — full app access"
        case .verifiedDeveloper:
            return runtime == .inProcess
                ? "Verified developer — full app access, not sandboxed"
                : "Verified developer — sandboxed"
        case .sandboxedOnly:
            return "Third party — sandboxed"
        }
    }
}

/// A resolved reference to one contribution.
///
/// Handed out from the registry with metadata already decoded and **no code
/// loaded**. Calling ``resolve()`` is what triggers activation, which is why a host
/// can build its entire menu structure at launch for the cost of reading JSON.
public struct ExtensionHandle<P: ExtensionPoint>: Sendable, Identifiable {
    public let id: ContributionKey
    public let contributor: PluginIdentity
    /// Plugin-local contribution name.
    public let name: String
    /// The declarative half, already decoded into the point's own type.
    public let metadata: P.Metadata
    public let priority: Int

    private let resolver: @Sendable () async throws -> P.Contract

    public init(
        id: ContributionKey,
        contributor: PluginIdentity,
        name: String,
        metadata: P.Metadata,
        priority: Int,
        resolver: @escaping @Sendable () async throws -> P.Contract
    ) {
        self.id = id
        self.contributor = contributor
        self.name = name
        self.metadata = metadata
        self.priority = priority
        self.resolver = resolver
    }

    /// Loads and activates the contributing plugin if needed, then produces the
    /// contract. Memoised: repeated calls yield the same instance.
    public func resolve() async throws -> P.Contract {
        try await resolver()
    }
}

/// How many failures a plugin gets before it is taken out of rotation.
///
/// In-process, a plugin *crash* is the host's crash, so there is nothing left to
/// count — what this actually bounds is repeated load and activation failures. It
/// exists so that one plugin throwing on every launch cannot make the app feel
/// broken forever, and so the eventual out-of-process runtime has the accounting
/// already in place.
public struct CrashBudget: Sendable, Hashable {
    public let maximumFailures: Int
    /// Whether exceeding the budget quarantines the plugin, or merely records it.
    public let quarantines: Bool

    public init(maximumFailures: Int = 3, quarantines: Bool = true) {
        self.maximumFailures = maximumFailures
        self.quarantines = quarantines
    }

    public static let `default` = CrashBudget()
    /// Never quarantine. For development, where a plugin failing three times in a
    /// row is a normal afternoon.
    public static let lenient = CrashBudget(maximumFailures: .max, quarantines: false)
}
