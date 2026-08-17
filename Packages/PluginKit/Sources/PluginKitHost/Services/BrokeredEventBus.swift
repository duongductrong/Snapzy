import Foundation
import PluginKitCore

/// The host's event bus, with per-topic access control.
///
/// One bus shared by the host and every plugin, handing out per-plugin *views*
/// (``scoped(to:publishing:subscribing:)``) that enforce what each may publish and
/// see. A plugin able to publish `document.saved` could mislead every other
/// plugin, so publish rights are granted per topic rather than assumed.
///
/// Delivery is intentionally lossy. Each subscriber has a bounded buffer and drops
/// its oldest events when it falls behind, because the alternative — backpressure —
/// means a slow plugin can stall the publisher, and the publisher is usually the
/// host's main actor.
public actor BrokeredEventBus {
    /// How many events a subscriber may fall behind before the oldest are dropped.
    public let bufferSize: Int

    private struct Subscription {
        let topic: TopicID
        let subscriber: PluginID?
        /// Type-erased delivery. Yields only if the payload matches the stream's
        /// event type.
        let deliver: @Sendable (Any) -> Void
    }

    private var subscriptions: [UUID: Subscription] = [:]
    private var droppedCounts: [TopicID: Int] = [:]
    private let log: any PluginLogging

    public init(bufferSize: Int = 64, log: any PluginLogging = SilentPluginLog()) {
        self.bufferSize = bufferSize
        self.log = log
    }

    /// Publishes from the host itself, bypassing topic checks.
    public func publishFromHost<Event: PluginEvent>(_ event: Event) {
        deliver(event, topic: Event.topic)
    }

    /// A view of the bus scoped to one plugin.
    ///
    /// - Parameters:
    ///   - publishing: topics the plugin may publish to. Patterns support a
    ///     trailing `*` (`"document.*"`).
    ///   - subscribing: topics it may observe.
    public func scoped(
        to plugin: PluginID,
        publishing publishable: [String],
        subscribing subscribable: [String]
    ) -> any EventBus {
        ScopedEventBus(
            bus: self,
            plugin: plugin,
            publishable: publishable,
            subscribable: subscribable
        )
    }

    /// A view with no restrictions, for the host's own components.
    public func unrestricted() -> any EventBus {
        ScopedEventBus(bus: self, plugin: nil, publishable: ["*"], subscribable: ["*"])
    }

    // MARK: - Internals used by the scoped view

    func publish<Event: PluginEvent>(
        _ event: Event,
        from plugin: PluginID?,
        allowed: [String]
    ) throws {
        guard Self.matches(Event.topic, patterns: allowed) else {
            throw PluginKitError.misconfigured(
                reason: "'\(plugin?.rawValue ?? "host")' may not publish to '\(Event.topic)'."
            )
        }
        deliver(event, topic: Event.topic)
    }

    func subscribe<Event: PluginEvent>(
        to type: Event.Type,
        from plugin: PluginID?,
        allowed: [String]
    ) -> AsyncStream<Event> {
        guard Self.matches(Event.topic, patterns: allowed) else {
            // Refusing by returning an empty stream rather than throwing keeps
            // `subscribe` non-throwing for every caller, at the cost of one log
            // line for a plugin that asked for something it cannot have.
            log.log(
                .notice, plugin: plugin,
                "Subscription to '\(Event.topic)' refused: not in the plugin's granted topics."
            )
            return AsyncStream { $0.finish() }
        }

        return AsyncStream(bufferingPolicy: .bufferingNewest(bufferSize)) { continuation in
            let id = UUID()
            let subscription = Subscription(
                topic: Event.topic,
                subscriber: plugin,
                deliver: { payload in
                    guard let typed = payload as? Event else { return }
                    if case .terminated = continuation.yield(typed) {
                        // Consumer is gone; cleanup happens via onTermination.
                    }
                }
            )
            Task { await self.add(subscription, id: id) }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.remove(id) }
            }
        }
    }

    private func add(_ subscription: Subscription, id: UUID) {
        subscriptions[id] = subscription
    }

    private func remove(_ id: UUID) {
        subscriptions[id] = nil
    }

    private func deliver(_ event: any PluginEvent, topic: TopicID) {
        for subscription in subscriptions.values where subscription.topic == topic {
            subscription.deliver(event)
        }
    }

    /// Number of events dropped for a topic. Surfaced in diagnostics — silent loss
    /// is acceptable, *invisible* loss is not.
    public func droppedCount(for topic: TopicID) -> Int { droppedCounts[topic] ?? 0 }

    /// Matches a topic against patterns, supporting a trailing `*`.
    static func matches(_ topic: TopicID, patterns: [String]) -> Bool {
        for pattern in patterns {
            if pattern == "*" { return true }
            if pattern.hasSuffix("*") {
                let prefix = String(pattern.dropLast())
                if topic.rawValue.hasPrefix(prefix) { return true }
            } else if pattern == topic.rawValue {
                return true
            }
        }
        return false
    }
}

/// One plugin's view of the bus.
private struct ScopedEventBus: EventBus {
    let bus: BrokeredEventBus
    let plugin: PluginID?
    let publishable: [String]
    let subscribable: [String]

    func publish<Event: PluginEvent>(_ event: Event) async throws {
        try await bus.publish(event, from: plugin, allowed: publishable)
    }

    func subscribe<Event: PluginEvent>(to type: Event.Type) -> AsyncStream<Event> {
        // `subscribe` is synchronous in the protocol — a plugin observing a topic
        // should not have to await — so the stream is created eagerly and its
        // registration completes on the actor a moment later. Events published in
        // that window are missed, which is consistent with the bus being
        // best-effort rather than a queue.
        AsyncStream { continuation in
            let task = Task {
                for await event in await bus.subscribe(
                    to: type, from: plugin, allowed: subscribable
                ) {
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Records everything published, delivers nothing. For tests that assert on
/// emissions without wiring up subscribers.
public actor RecordingEventBus: EventBus {
    public private(set) var published: [(topic: TopicID, payload: any PluginEvent)] = []

    public init() {}

    public func publish<Event: PluginEvent>(_ event: Event) async throws {
        published.append((Event.topic, event))
    }

    /// Nonisolated because ``EventBus/subscribe(to:)`` is synchronous and this
    /// recorder has nothing to deliver — it touches no isolated state.
    public nonisolated func subscribe<Event: PluginEvent>(
        to type: Event.Type
    ) -> AsyncStream<Event> {
        AsyncStream { $0.finish() }
    }

    /// Everything published of a given type.
    public func events<Event: PluginEvent>(of type: Event.Type) -> [Event] {
        published.compactMap { $0.payload as? Event }
    }

    public func count(for topic: TopicID) -> Int {
        published.filter { $0.topic == topic }.count
    }
}
