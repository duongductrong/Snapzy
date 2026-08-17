import Foundation

// Author-side ergonomics. These live in the SDK rather than in Core on purpose:
// Core is the binary contract between a host and a plugin, and every symbol in it
// is a permanent commitment. Conveniences belong on the side that can add to them
// freely.

extension PluginContext {
    /// Claims a capability, returning `nil` instead of throwing when it is denied.
    ///
    /// The shape graceful degradation actually wants. A plugin that hides a
    /// button when clipboard access is refused is a better citizen than one that
    /// refuses to load, and this makes the good behaviour the shorter code:
    ///
    /// ```swift
    /// let clipboard = await context.optionalCapability((any ClipboardReading).self)
    /// if clipboard == nil {
    ///     context.logger.notice("Clipboard denied; paste is unavailable.")
    /// }
    /// ```
    ///
    /// A missing *declaration* still throws through ``capability(_:)`` — this
    /// swallows denials, not manifest mistakes, which are the author's bug and
    /// should be loud.
    public func optionalCapability<C: Capability>(_ type: C.Type) async -> C? {
        do {
            return try await capability(type)
        } catch let error as CapabilityError {
            switch error {
            case .undeclared:
                // The author forgot to declare it. Report it rather than
                // silently degrading — a plugin quietly missing a feature it
                // believes it has is far harder to debug than a log line.
                logger.error(
                    "'\(C.capabilityID)' was requested in code but is not declared in plugin.json."
                )
                return nil
            default:
                logger.info("'\(C.capabilityID)' unavailable: \(error.localizedDescription)")
                return nil
            }
        } catch {
            logger.info("'\(C.capabilityID)' unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    /// Resolves an optional peer service without throwing.
    public func optionalService<S: PluginService>(_ type: S.Type) async -> S? {
        try? await service(type)
    }

    /// Reads a setting.
    public func setting<Value: Codable & Sendable>(_ key: ConfigKey<Value>) async -> Value {
        await configuration.value(key)
    }

    /// Observes a setting, starting with its current value.
    ///
    /// Saves every plugin from writing the same "read once, then subscribe"
    /// dance — and from the race in the middle of it, where a change published
    /// between the read and the subscription is lost.
    public func settingUpdates<Value: Codable & Sendable>(
        _ key: ConfigKey<Value>
    ) -> AsyncStream<Value> {
        AsyncStream { continuation in
            let task = Task {
                let changes = configuration.changes()
                continuation.yield(await configuration.value(key))
                for await change in changes where change.name == key.name {
                    continuation.yield(await configuration.value(key))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
