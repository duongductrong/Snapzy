import Foundation
import PluginKitCore

/// Builds a configuration store per plugin.
///
/// A factory rather than one shared store because each plugin's namespace must be
/// separate and inescapable — a plugin able to name another's keys could read its
/// settings, and there is no legitimate reason to allow it.
public protocol ConfigurationStoreFactory: Sendable {
    func makeStore(
        for identity: PluginIdentity,
        schema: ConfigurationSchema?
    ) throws -> any ConfigurationStore
}

/// Builds a private container per plugin.
public protocol PluginStorageFactory: Sendable {
    func makeStorage(for identity: PluginIdentity) throws -> any PluginStorage
}

/// The layered store: session → managed → user → bundled → schema default.
///
/// Reads never throw. That is a deliberate asymmetry — a configuration read sits
/// on the activation path, and a corrupt preferences file must not be able to stop
/// a plugin loading. Writes throw, because a locked key or a schema violation is a
/// real condition with a user action behind it.
public actor LayeredConfigurationStore: ConfigurationStore {
    private let identity: PluginIdentity
    private let schema: ConfigurationSchema?
    private var layers: [ConfigurationLayer: [String: JSONValue]]
    private let persistence: (any ConfigurationPersistence)?
    private var observers: [UUID: AsyncStream<ConfigurationChange>.Continuation] = [:]

    public init(
        identity: PluginIdentity,
        schema: ConfigurationSchema?,
        session: [String: JSONValue] = [:],
        managed: [String: JSONValue] = [:],
        user: [String: JSONValue] = [:],
        bundled: [String: JSONValue] = [:],
        persistence: (any ConfigurationPersistence)? = nil
    ) {
        self.identity = identity
        self.schema = schema
        self.persistence = persistence
        self.layers = [
            .session: session,
            .managed: managed,
            .user: user,
            .bundled: bundled,
            .schemaDefault: schema?.defaults ?? [:],
        ]
    }

    public func value<Value: Codable & Sendable>(_ key: ConfigKey<Value>) async -> Value {
        for layer in ConfigurationLayer.resolutionOrder {
            guard let raw = layers[layer]?[key.name] else { continue }
            if let decoded = try? raw.decode(as: Value.self) { return decoded }
            // A value of the wrong type is a real problem, but not one worth
            // failing a plugin's activation over. Fall through to the next layer;
            // the plugin gets sane behaviour and the mismatch is still visible via
            // `resolvedLayer(_:)`.
        }
        return key.defaultValue
    }

    public func set<Value: Codable & Sendable>(_ key: ConfigKey<Value>, to value: Value) async throws {
        guard layers[.managed]?[key.name] == nil else {
            throw PluginKitError.misconfigured(
                reason: "'\(key.name)' is fixed by a managed configuration profile."
            )
        }

        let encoded = try JSONValue(encoding: value)
        if let descriptor = schema?.descriptor(named: key.name), !descriptor.accepts(encoded) {
            throw PluginKitError.misconfigured(
                reason: "\(encoded) is not a valid value for '\(key.name)'."
            )
        }

        layers[.user, default: [:]][key.name] = encoded
        try await persistence?.write(layers[.user] ?? [:], for: identity)
        broadcast(ConfigurationChange(name: key.name, newValue: encoded, layer: .user))
    }

    public func isLocked(_ name: String) async -> Bool {
        layers[.managed]?[name] != nil
    }

    public func resolvedLayer(_ name: String) async -> ConfigurationLayer? {
        ConfigurationLayer.resolutionOrder.first { layers[$0]?[name] != nil }
    }

    /// Nonisolated so that ``ConfigurationStore/changes()`` can stay synchronous:
    /// a plugin observing a setting should not have to `await` to start watching.
    /// Registration completes on the actor a moment later, so a change published in
    /// that window is missed — acceptable, because every consumer reads the current
    /// value on subscribe anyway (see `PluginContext.settingUpdates(_:)`).
    public nonisolated func changes() -> AsyncStream<ConfigurationChange> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addObserver(id, continuation) }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(id) }
            }
        }
    }

    private func addObserver(
        _ id: UUID,
        _ continuation: AsyncStream<ConfigurationChange>.Continuation
    ) {
        observers[id] = continuation
    }

    /// Replaces a whole layer. How a host applies a freshly fetched managed
    /// profile, or how a test injects a session override.
    public func replace(layer: ConfigurationLayer, with values: [String: JSONValue]) {
        let previous = layers[layer] ?? [:]
        layers[layer] = values
        for name in Set(previous.keys).union(values.keys) where previous[name] != values[name] {
            broadcast(ConfigurationChange(name: name, newValue: values[name], layer: layer))
        }
    }

    private func removeObserver(_ id: UUID) { observers[id] = nil }

    private func broadcast(_ change: ConfigurationChange) {
        for continuation in observers.values { continuation.yield(change) }
    }
}

/// Where the user layer is persisted.
///
/// Separate from the store so the layering logic is testable without touching the
/// filesystem, and so a host can keep plugin settings wherever it already keeps
/// its own.
public protocol ConfigurationPersistence: Sendable {
    func read(for identity: PluginIdentity) async throws -> [String: JSONValue]
    func write(_ values: [String: JSONValue], for identity: PluginIdentity) async throws
}

/// Persists each plugin's user layer as a plist-style JSON file in its container.
public struct FileConfigurationPersistence: ConfigurationPersistence {
    public let root: URL

    public init(root: URL) { self.root = root }

    public func read(for identity: PluginIdentity) async throws -> [String: JSONValue] {
        let url = fileURL(for: identity)
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: JSONValue].self, from: data)) ?? [:]
    }

    public func write(_ values: [String: JSONValue], for identity: PluginIdentity) async throws {
        let url = fileURL(for: identity)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(values).write(to: url, options: .atomic)
    }

    private func fileURL(for identity: PluginIdentity) -> URL {
        root.appendingPathComponent(identity.id.rawValue, isDirectory: true)
            .appendingPathComponent("settings.json")
    }
}

/// The default factory: layered stores backed by files under `root`.
public struct FileConfigurationStoreFactory: ConfigurationStoreFactory {
    public let root: URL
    /// Managed values per plugin, normally read from an MDM profile.
    public let managed: [PluginID: [String: JSONValue]]
    /// Session overrides per plugin, normally from a launch argument.
    public let session: [PluginID: [String: JSONValue]]

    public init(
        root: URL,
        managed: [PluginID: [String: JSONValue]] = [:],
        session: [PluginID: [String: JSONValue]] = [:]
    ) {
        self.root = root
        self.managed = managed
        self.session = session
    }

    public func makeStore(
        for identity: PluginIdentity,
        schema: ConfigurationSchema?
    ) throws -> any ConfigurationStore {
        let persistence = FileConfigurationPersistence(root: root)
        let store = LayeredConfigurationStore(
            identity: identity,
            schema: schema,
            session: session[identity.id] ?? [:],
            managed: managed[identity.id] ?? [:],
            persistence: persistence
        )
        // Load the user layer in the background: `makeStore` is called on the
        // activation path, and a plugin reading a setting a few microseconds early
        // gets its schema default, which is the documented fallback anyway.
        Task {
            let stored = try? await persistence.read(for: identity)
            await store.replace(layer: .user, with: stored ?? [:])
        }
        return store
    }
}

/// In-memory stores. For tests, and for a host that deliberately keeps no plugin
/// settings.
public struct InMemoryConfigurationStoreFactory: ConfigurationStoreFactory {
    public let managed: [PluginID: [String: JSONValue]]
    public let session: [PluginID: [String: JSONValue]]
    public let user: [PluginID: [String: JSONValue]]

    public init(
        managed: [PluginID: [String: JSONValue]] = [:],
        session: [PluginID: [String: JSONValue]] = [:],
        user: [PluginID: [String: JSONValue]] = [:]
    ) {
        self.managed = managed
        self.session = session
        self.user = user
    }

    public func makeStore(
        for identity: PluginIdentity,
        schema: ConfigurationSchema?
    ) throws -> any ConfigurationStore {
        LayeredConfigurationStore(
            identity: identity,
            schema: schema,
            session: session[identity.id] ?? [:],
            managed: managed[identity.id] ?? [:],
            user: user[identity.id] ?? [:]
        )
    }
}
