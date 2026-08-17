import Foundation
import PluginKitCore

/// Refuses everything and never asks.
///
/// The default, and the only correct default for a host without a consent UI: a
/// daemon or a CLI has nobody to prompt, and a store that blocked waiting for an
/// answer would hang the launch path. Fail closed, log, carry on.
public struct DenyingConsentStore: ConsentStore {
    public init() {}

    public func decision(for plugin: PluginID, capability: CapabilityID) async -> ConsentDecision? {
        nil
    }

    public func requestConsent(_ prompt: ConsentPrompt) async -> ConsentDecision { .denyOnce }

    public func record(
        _ decision: ConsentDecision,
        for plugin: PluginID,
        capability: CapabilityID
    ) async {}

    public func revoke(for plugin: PluginID, capability: CapabilityID?) async {}
}

/// Approves everything without asking.
///
/// For tests, and for a host that only runs plugins it compiled itself. Using it
/// with third-party code would make every consent prompt in the design a no-op
/// while leaving the UI implying otherwise.
public struct AllowingConsentStore: ConsentStore {
    public init() {}

    public func decision(for plugin: PluginID, capability: CapabilityID) async -> ConsentDecision? {
        .allowAlways
    }

    public func requestConsent(_ prompt: ConsentPrompt) async -> ConsentDecision { .allowAlways }

    public func record(
        _ decision: ConsentDecision,
        for plugin: PluginID,
        capability: CapabilityID
    ) async {}

    public func revoke(for plugin: PluginID, capability: CapabilityID?) async {}
}

/// Defers to a host-supplied prompt, and remembers the answers.
///
/// The shape a real app wants: PluginKit decides *when* to ask and what the
/// question is; the app decides what the sheet looks like.
///
/// An actor because a prompt is inherently slow and re-entrant — two plugins can
/// activate concurrently and ask about the same capability, and the persisted
/// record has to be consistent afterwards.
public actor CallbackConsentStore: ConsentStore {
    private let prompt: @Sendable (ConsentPrompt) async -> ConsentDecision
    private let defaults: UserDefaults?
    private let storageKey: String
    private var cache: [String: ConsentDecision] = [:]

    /// - Parameters:
    ///   - defaults: where persistent answers are kept. `nil` keeps them in memory
    ///     only, which is right for tests and wrong for a shipping app.
    ///   - prompt: presents the request. Return an
    ///     ``ConsentDecision/allowAlways``-style answer to have it remembered.
    public init(
        defaults: UserDefaults? = .standard,
        storageKey: String = "PluginKit.consent",
        prompt: @escaping @Sendable (ConsentPrompt) async -> ConsentDecision
    ) {
        self.prompt = prompt
        self.defaults = defaults
        self.storageKey = storageKey
        if let stored = defaults?.dictionary(forKey: storageKey) as? [String: String] {
            cache = stored.compactMapValues(ConsentDecision.init(rawValue:))
        }
    }

    public func decision(for plugin: PluginID, capability: CapabilityID) async -> ConsentDecision? {
        cache[Self.key(plugin, capability)]
    }

    public func requestConsent(_ prompt: ConsentPrompt) async -> ConsentDecision {
        // Re-check under isolation: a concurrent activation may have answered
        // this exact question while we were suspended, and asking the user twice
        // for the same grant is the sort of detail that erodes trust in the whole
        // permission model.
        if let existing = cache[Self.key(prompt.plugin.id, prompt.capability)] {
            return existing
        }
        return await self.prompt(prompt)
    }

    public func record(
        _ decision: ConsentDecision,
        for plugin: PluginID,
        capability: CapabilityID
    ) async {
        guard decision.isPersistent else { return }
        cache[Self.key(plugin, capability)] = decision
        flush()
    }

    public func revoke(for plugin: PluginID, capability: CapabilityID?) async {
        if let capability {
            cache[Self.key(plugin, capability)] = nil
        } else {
            let prefix = "\(plugin.rawValue)|"
            for key in cache.keys where key.hasPrefix(prefix) { cache[key] = nil }
        }
        flush()
    }

    private func flush() {
        defaults?.set(cache.mapValues(\.rawValue), forKey: storageKey)
    }

    private static func key(_ plugin: PluginID, _ capability: CapabilityID) -> String {
        "\(plugin.rawValue)|\(capability.rawValue)"
    }
}

/// Remembers what it is told, asks nobody.
///
/// For tests that need to assert on what *would* have been prompted, and to
/// pre-seed decisions without a UI.
public actor InMemoryConsentStore: ConsentStore {
    private var decisions: [String: ConsentDecision] = [:]
    private let fallback: ConsentDecision
    /// Every prompt that was raised, in order. Lets a test assert that the user
    /// was asked at all — a broker that grants silently is a bug the happy path
    /// cannot see.
    public private(set) var prompts: [ConsentPrompt] = []

    public init(fallback: ConsentDecision = .denyOnce) {
        self.fallback = fallback
    }

    public func seed(_ decision: ConsentDecision, for plugin: PluginID, capability: CapabilityID) {
        decisions["\(plugin.rawValue)|\(capability.rawValue)"] = decision
    }

    public func decision(for plugin: PluginID, capability: CapabilityID) async -> ConsentDecision? {
        decisions["\(plugin.rawValue)|\(capability.rawValue)"]
    }

    public func requestConsent(_ prompt: ConsentPrompt) async -> ConsentDecision {
        prompts.append(prompt)
        return fallback
    }

    public func record(
        _ decision: ConsentDecision,
        for plugin: PluginID,
        capability: CapabilityID
    ) async {
        decisions["\(plugin.rawValue)|\(capability.rawValue)"] = decision
    }

    public func revoke(for plugin: PluginID, capability: CapabilityID?) async {
        if let capability {
            decisions["\(plugin.rawValue)|\(capability.rawValue)"] = nil
        } else {
            let prefix = "\(plugin.rawValue)|"
            for key in decisions.keys where key.hasPrefix(prefix) { decisions[key] = nil }
        }
    }
}
