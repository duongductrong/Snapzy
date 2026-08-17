import Foundation

/// Where a plugin sits in its lifecycle.
///
/// ```text
/// discovered → validated → resolved → loading → active → inactive → unloaded
///      ↓            ↓          ↓          ↓        ↓                    ↓
///  rejected    unsatisfied  (steady)   failed   failed           quarantined
/// ```
///
/// The important one is ``resolved``: a host with sixty installed plugins should
/// idle with sixty *resolved* and zero *loaded*. Contributions are queryable in
/// this phase — that is the whole point of the manifest — so a plugin only ever
/// reaches ``loading`` because something asked to use it.
public enum PluginPhase: String, Hashable, Sendable, Codable, CaseIterable {
    /// Manifest parsed. Nothing else has happened.
    case discovered
    /// Refused before loading: trust, signature, or a malformed manifest.
    case rejected
    /// Manifest is well-formed and the plugin is trusted enough to consider.
    case validated
    /// Well-formed and trusted, but something it needs is missing. A steady,
    /// visible state carrying an ``UnsatisfiedReason`` — never a silent drop.
    case unsatisfied
    /// Ready. Contributions are queryable; no code is loaded.
    case resolved
    /// Code is being mapped in, or a process spawned.
    case loading
    /// `activate()` returned successfully. Contracts are resolvable.
    case active
    /// Deactivated but still installed and resolvable again.
    case inactive
    /// Loading or activation threw. Retryable within the crash budget.
    case failed
    /// Auto-disabled after repeated crashes, so one bad plugin cannot make the
    /// app unusable.
    case quarantined

    /// Whether the host holds live plugin code for this phase.
    public var isLoaded: Bool {
        switch self {
        case .loading, .active: return true
        case .discovered, .rejected, .validated, .unsatisfied, .resolved,
             .inactive, .failed, .quarantined:
            return false
        }
    }

    /// Whether contributions can be listed. True well before any code loads,
    /// which is the property the launch path depends on.
    public var contributesToRegistry: Bool {
        switch self {
        case .resolved, .loading, .active, .inactive: return true
        case .discovered, .rejected, .validated, .unsatisfied, .failed, .quarantined: return false
        }
    }
}

/// A plugin's self-reported health.
public enum PluginHealth: Hashable, Sendable {
    case ok
    /// Working, but not fully. A plugin that was denied an optional capability
    /// should report this so the host can explain the reduced behaviour instead
    /// of the user discovering it.
    case degraded(reason: String)
    /// Stopped answering. Only diagnosable out-of-process.
    case unresponsive
    case crashed
}

/// What a plugin is told about the host's own lifecycle.
///
/// Deliberately coarse. A plugin does not get to observe the host's internals;
/// it gets the handful of transitions it might genuinely need to react to.
public enum HostLifecycleEvent: Hashable, Sendable {
    case willTerminate
    case didBecomeActive
    case didEnterBackground
    /// The host is about to deactivate this plugin. Last chance to flush.
    case willDeactivate
}

/// A warning attached to a plugin that runs but should not keep running as-is.
///
/// Carried on the plugin's record rather than only logged, so a plugin manager
/// UI can badge it and the author's `pluginkit doctor` can report it. A
/// deprecation nobody sees is a deprecation nobody acts on.
public struct PluginWarning: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable {
        /// Using a contract version the host has deprecated.
        case deprecatedContract
        /// Loaded in-process without isolation because no isolating runtime was
        /// available.
        case unisolated
        /// An optional capability was denied; the plugin is running reduced.
        case capabilityDenied
        /// An optional dependency is absent.
        case optionalDependencyMissing
        /// Shadowed a plugin with the same identity from a lower-precedence
        /// source.
        case shadowedAnotherPlugin
    }

    public let kind: Kind
    public let detail: String
    /// What the author or administrator should do about it, when there is a
    /// specific answer.
    public let guidance: String?

    public init(kind: Kind, detail: String, guidance: String? = nil) {
        self.kind = kind
        self.detail = detail
        self.guidance = guidance
    }
}
