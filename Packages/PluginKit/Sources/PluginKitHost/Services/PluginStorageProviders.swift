import Foundation
import PluginKitCore

/// A directory per plugin, under a host-chosen root.
///
/// Keys are sanitised into filenames, and the sanitisation is not cosmetic: a key
/// containing `../` would otherwise let a plugin write outside its own container,
/// which is exactly the escape the scoping exists to prevent.
public actor FileSystemPluginStorage: PluginStorage {
    public let containerURL: URL
    private var didCreateDirectory = false

    public init(containerURL: URL) {
        self.containerURL = containerURL
    }

    public func data(forKey key: String) async throws -> Data? {
        let url = try fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func setData(_ data: Data?, forKey key: String) async throws {
        let url = try fileURL(for: key)
        guard let data else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try ensureDirectory()
        try data.write(to: url, options: .atomic)
    }

    public func keys() async throws -> [String] {
        guard FileManager.default.fileExists(atPath: containerURL.path) else { return [] }
        let contents = try FileManager.default.contentsOfDirectory(
            at: containerURL,
            includingPropertiesForKeys: nil
        )
        return contents
            .filter { $0.pathExtension == "data" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    private func ensureDirectory() throws {
        guard !didCreateDirectory else { return }
        try FileManager.default.createDirectory(
            at: containerURL,
            withIntermediateDirectories: true
        )
        didCreateDirectory = true
    }

    private func fileURL(for key: String) throws -> URL {
        let safe = Self.sanitise(key)
        guard !safe.isEmpty else {
            throw PluginKitError.misconfigured(reason: "'\(key)' is not a usable storage key.")
        }
        return containerURL.appendingPathComponent("\(safe).data")
    }

    /// Keeps a key inside its container. Only alphanumerics and a few safe
    /// punctuation marks survive, so no key can express a path component.
    static func sanitise(_ key: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let filtered = String(
            String.UnicodeScalarView(key.unicodeScalars.filter(allowed.contains))
        )
        // A leading dot would produce a hidden file, and `.` or `..` alone would
        // name the directory itself or its parent.
        return filtered.hasPrefix(".") ? String(filtered.drop(while: { $0 == "." })) : filtered
    }
}

/// In-memory storage. For tests, and for plugins whose state should not survive a
/// launch.
public actor InMemoryPluginStorage: PluginStorage {
    public let containerURL: URL
    private var storage: [String: Data] = [:]

    public init(containerURL: URL = URL(fileURLWithPath: "/dev/null")) {
        self.containerURL = containerURL
    }

    public func data(forKey key: String) async throws -> Data? { storage[key] }

    public func setData(_ data: Data?, forKey key: String) async throws {
        storage[key] = data
    }

    public func keys() async throws -> [String] { storage.keys.sorted() }
}

/// Hands each plugin a directory under `root`.
public struct FileSystemStorageFactory: PluginStorageFactory {
    public let root: URL

    public init(root: URL) { self.root = root }

    public func makeStorage(for identity: PluginIdentity) throws -> any PluginStorage {
        FileSystemPluginStorage(
            containerURL: root.appendingPathComponent(identity.id.rawValue, isDirectory: true)
        )
    }
}

public struct InMemoryStorageFactory: PluginStorageFactory {
    public init() {}

    public func makeStorage(for identity: PluginIdentity) throws -> any PluginStorage {
        InMemoryPluginStorage()
    }
}

/// Remembers which plugins the user has turned off.
///
/// Separate from ``ConfigurationStore`` because enablement is the host's state
/// about a plugin, not the plugin's own — it has to survive the plugin being
/// uninstalled and reinstalled, and a plugin must not be able to re-enable itself.
public protocol PluginEnablementStore: Sendable {
    /// `nil` means the user has never expressed a preference, so the plugin's own
    /// default applies.
    func isEnabled(_ id: PluginID) async -> Bool?
    func setEnabled(_ id: PluginID, _ enabled: Bool) async
}

/// `UserDefaults` is thread-safe but not `Sendable`, so the unchecked conformance
/// is accurate rather than a shortcut: the class holds no other mutable state.
public final class UserDefaultsEnablementStore: PluginEnablementStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let storageKey: String

    public init(defaults: UserDefaults = .standard, storageKey: String = "PluginKit.enabled") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    public func isEnabled(_ id: PluginID) async -> Bool? {
        (defaults.dictionary(forKey: storageKey) as? [String: Bool])?[id.rawValue]
    }

    public func setEnabled(_ id: PluginID, _ enabled: Bool) async {
        var current = (defaults.dictionary(forKey: storageKey) as? [String: Bool]) ?? [:]
        current[id.rawValue] = enabled
        defaults.set(current, forKey: storageKey)
    }
}

public actor InMemoryEnablementStore: PluginEnablementStore {
    private var storage: [PluginID: Bool] = [:]

    public init(initial: [PluginID: Bool] = [:]) { self.storage = initial }

    public func isEnabled(_ id: PluginID) async -> Bool? { storage[id] }

    public func setEnabled(_ id: PluginID, _ enabled: Bool) async { storage[id] = enabled }
}
