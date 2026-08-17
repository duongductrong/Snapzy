import Foundation
import PluginKitCore

/// Something worth remembering about a plugin.
public struct DiagnosticEvent: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case discovered
        case rejected
        case unsatisfied
        case resolved
        case activated
        case deactivated
        case failed
        case quarantined
        case capabilityGranted
        case capabilityDenied
        case capabilityAttenuated
        case contractResolved
        case deprecationWarning
        case shadowed
    }

    public let kind: Kind
    public let plugin: PluginID?
    public let detail: String
    /// Wall time, when it matters — activation duration, contract resolution.
    public let duration: Duration?

    public init(kind: Kind, plugin: PluginID?, detail: String, duration: Duration? = nil) {
        self.kind = kind
        self.plugin = plugin
        self.detail = detail
        self.duration = duration
    }
}

/// A bounded, queryable record of plugin activity.
///
/// Bounded on purpose: a long-running host with a chatty plugin would otherwise
/// accumulate diagnostics forever, and an unbounded diagnostic buffer is a leak
/// with good intentions.
public actor PluginDiagnostics {
    public let capacity: Int
    private var events: [DiagnosticEvent] = []
    private var counts: [DiagnosticEvent.Kind: Int] = [:]
    private var activationDurations: [PluginID: Duration] = [:]

    public init(capacity: Int = 512) {
        self.capacity = capacity
    }

    public func record(_ event: DiagnosticEvent) {
        events.append(event)
        if events.count > capacity { events.removeFirst(events.count - capacity) }
        counts[event.kind, default: 0] += 1
        if event.kind == .activated, let plugin = event.plugin, let duration = event.duration {
            activationDurations[plugin] = duration
        }
    }

    public func all() -> [DiagnosticEvent] { events }

    public func events(for plugin: PluginID) -> [DiagnosticEvent] {
        events.filter { $0.plugin == plugin }
    }

    public func events(of kind: DiagnosticEvent.Kind) -> [DiagnosticEvent] {
        events.filter { $0.kind == kind }
    }

    public func count(of kind: DiagnosticEvent.Kind) -> Int { counts[kind] ?? 0 }

    /// Activation cost per plugin, slowest first.
    ///
    /// The number to reach for when launch time regresses and there are sixty
    /// plugins installed.
    public func activationCosts() -> [(plugin: PluginID, duration: Duration)] {
        activationDurations
            .map { (plugin: $0.key, duration: $0.value) }
            .sorted { $0.duration > $1.duration }
    }

    public func clear() {
        events.removeAll()
        counts.removeAll()
        activationDurations.removeAll()
    }
}

/// What the host publishes about its plugins, for a UI to observe.
public enum PluginManagerEvent: Sendable {
    case startedDiscovery
    case finishedDiscovery(discovered: Int, resolved: Int, rejected: Int)
    case phaseChanged(PluginID, from: PluginPhase, to: PluginPhase)
    case warningAdded(PluginID, PluginWarning)
    case failed(PluginID, reason: String)
    case registryChanged
}

/// Runs `operation` with a deadline, without waiting for an overrun to finish.
///
/// A task group would be wrong here: it awaits all its children, so a plugin whose
/// `deactivate()` never returns would hang the very timeout meant to contain it.
/// This races a latch instead and *abandons* the overrunning work — deliberately
/// leaking it, because an in-process plugin's objects may still be reachable from
/// the host and unloading it would turn a hang into a crash.
///
/// - Returns: `true` if the operation completed inside the budget.
func withDeadline(
    _ budget: Duration,
    operation: @escaping @Sendable () async -> Void
) async -> Bool {
    let latch = DeadlineLatch()

    let work = Task {
        await operation()
        await latch.settle(true)
    }
    let timer = Task {
        try? await Task.sleep(for: budget)
        await latch.settle(false)
    }

    let completed = await latch.wait()
    timer.cancel()
    if completed { work.cancel() }  // no-op if already finished; releases the task
    return completed
}

private actor DeadlineLatch {
    private var settled: Bool?
    private var continuation: CheckedContinuation<Bool, Never>?

    func wait() async -> Bool {
        if let settled { return settled }
        return await withCheckedContinuation { continuation = $0 }
    }

    func settle(_ value: Bool) {
        guard settled == nil else { return }
        settled = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}
