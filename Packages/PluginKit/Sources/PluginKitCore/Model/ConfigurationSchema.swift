import Foundation

/// A plugin's settings, described declaratively.
///
/// Same payoff as declarative contribution metadata: a host can render a
/// complete preferences pane for a plugin whose code has never been loaded, and
/// an administrator can write a managed-configuration profile against a schema
/// they can read without running anything.
public struct ConfigurationSchema: Hashable, Sendable, Codable {
    /// Bumped when keys are added, removed, or change meaning. Drives migration
    /// on upgrade.
    public var version: Int
    public var keys: [ConfigurationKeyDescriptor]

    public init(version: Int = 1, keys: [ConfigurationKeyDescriptor] = []) {
        self.version = version
        self.keys = keys
    }

    public func descriptor(named name: String) -> ConfigurationKeyDescriptor? {
        keys.first { $0.name == name }
    }

    /// Default values for every declared key, as the bottom configuration layer.
    public var defaults: [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        for key in keys where key.defaultValue != nil {
            result[key.name] = key.defaultValue
        }
        return result
    }

    public func validateStructure() throws {
        var seen = Set<String>()
        for key in keys {
            guard !key.name.isEmpty else {
                throw PluginManifestError.invalid(reason: "A configuration key has an empty name.")
            }
            guard seen.insert(key.name).inserted else {
                throw PluginManifestError.invalid(
                    reason: "Configuration key '\(key.name)' is declared twice."
                )
            }
            if let defaultValue = key.defaultValue, !key.type.accepts(defaultValue) {
                throw PluginManifestError.invalid(
                    reason: "The default for '\(key.name)' is not a \(key.type.rawValue)."
                )
            }
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        keys = try container.decodeIfPresent([ConfigurationKeyDescriptor].self, forKey: .keys) ?? []
    }

    private enum CodingKeys: String, CodingKey { case version, keys }
}

/// One declared setting.
public struct ConfigurationKeyDescriptor: Hashable, Sendable, Codable {
    public var name: String
    public var type: ConfigurationValueType
    public var defaultValue: JSONValue?
    /// Label for a settings UI.
    public var title: String?
    public var summary: String?
    /// Which storage class this belongs to. Only ``ConfigurationScope/settings``
    /// keys appear in a preferences UI or a managed profile.
    public var scope: ConfigurationScope
    /// For enumerated settings; a value outside this list is rejected on write.
    public var allowedValues: [JSONValue]?

    public init(
        name: String,
        type: ConfigurationValueType,
        defaultValue: JSONValue? = nil,
        title: String? = nil,
        summary: String? = nil,
        scope: ConfigurationScope = .settings,
        allowedValues: [JSONValue]? = nil
    ) {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
        self.title = title
        self.summary = summary
        self.scope = scope
        self.allowedValues = allowedValues
    }

    /// Whether `value` is acceptable for this key.
    public func accepts(_ value: JSONValue) -> Bool {
        guard type.accepts(value) else { return false }
        guard let allowedValues else { return true }
        return allowedValues.contains(value)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(ConfigurationValueType.self, forKey: .type)
        defaultValue = try container.decodeIfPresent(JSONValue.self, forKey: .defaultValue)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        scope = try container.decodeIfPresent(ConfigurationScope.self, forKey: .scope) ?? .settings
        allowedValues = try container.decodeIfPresent([JSONValue].self, forKey: .allowedValues)
    }

    private enum CodingKeys: String, CodingKey {
        case name, type, defaultValue, title, summary, scope, allowedValues
    }
}

public enum ConfigurationValueType: String, Hashable, Sendable, Codable {
    case bool, int, double, string, json

    public func accepts(_ value: JSONValue) -> Bool {
        switch (self, value) {
        case (.bool, .bool), (.int, .int), (.string, .string):
            return true
        // An `int` written by a JSON encoder can come back as a `double`, so a
        // double-typed key must accept both rather than rejecting `3`.
        case (.double, .double), (.double, .int):
            return true
        case (.json, _):
            return true
        default:
            return false
        }
    }
}

/// Which of the three storage classes a value belongs to.
///
/// Kept explicit because conflating them is the usual cause of two bugs: window
/// positions syncing between machines, and access tokens ending up in a plist.
public enum ConfigurationScope: String, Hashable, Sendable, Codable {
    /// User-facing preferences. Schema-described, syncable, shown in UI.
    case settings
    /// Caches, window frames, opaque per-machine state. Never shown, never synced.
    case state
}

/// Where a resolved configuration value came from.
///
/// Surfaced so a settings UI can show why a control is disabled — a value fixed
/// by a managed profile is not a bug the user should try to work around.
public enum ConfigurationLayer: String, Hashable, Sendable, Codable, Comparable, CaseIterable {
    /// Injected for one run: a launch flag, or a test.
    case session
    /// An MDM configuration profile. Not user-overridable, by design.
    case managed
    /// What the user set.
    case user
    /// Shipped inside the plugin bundle.
    case bundled
    /// The schema's declared default.
    case schemaDefault

    /// Earlier cases win. Ordering *is* the resolution rule, so it lives with
    /// the type rather than in whichever store happens to implement lookup.
    private var precedence: Int {
        switch self {
        case .session: return 0
        case .managed: return 1
        case .user: return 2
        case .bundled: return 3
        case .schemaDefault: return 4
        }
    }

    public static func < (lhs: ConfigurationLayer, rhs: ConfigurationLayer) -> Bool {
        lhs.precedence < rhs.precedence
    }

    /// Highest precedence first — the order a lookup should walk.
    public static var resolutionOrder: [ConfigurationLayer] { allCases.sorted() }
}

/// A configuration change, as delivered to a plugin.
public struct ConfigurationChange: Hashable, Sendable {
    public let name: String
    public let newValue: JSONValue?
    public let layer: ConfigurationLayer

    public init(name: String, newValue: JSONValue?, layer: ConfigurationLayer) {
        self.name = name
        self.newValue = newValue
        self.layer = layer
    }
}

/// A typed handle on one setting.
///
/// Carries its own default so a read can never fail — see
/// ``ConfigurationStore/value(_:)`` for why that is deliberate.
public struct ConfigKey<Value: Codable & Sendable>: Sendable {
    public let name: String
    public let defaultValue: Value
    public let scope: ConfigurationScope

    public init(_ name: String, default defaultValue: Value, scope: ConfigurationScope = .settings) {
        self.name = name
        self.defaultValue = defaultValue
        self.scope = scope
    }
}
