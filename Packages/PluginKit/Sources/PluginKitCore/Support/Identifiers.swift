import Foundation

/// Shared behaviour for PluginKit's string-backed identifiers.
///
/// Every identity is nominally typed rather than a bare `String`, so a
/// ``CapabilityID`` can never be passed where an ``ExtensionPointID`` is
/// expected. That matters more here than in most domains: nearly every value
/// crossing the plugin boundary is a reverse-DNS string, and a transposed pair
/// of arguments would otherwise typecheck and fail at runtime in a host the
/// author cannot debug.
///
/// Conformances are three lines each; everything else is defaulted here.
public protocol StringIdentifier:
    RawRepresentable,
    Hashable,
    Sendable,
    Codable,
    CustomStringConvertible,
    ExpressibleByStringLiteral
where RawValue == String, StringLiteralType == String {
    init(rawValue: String)
}

extension StringIdentifier {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public init(_ value: String) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Stable identity of a plugin, by convention reverse-DNS
/// (`"com.example.wordcount"`).
///
/// A plugin's identity is independent of where it was found and of its version:
/// upgrading a plugin keeps the ID, which is how the host knows to migrate
/// configuration rather than treat the new build as a stranger.
public struct PluginID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Identifies a host's published extension-point vocabulary, e.g.
/// `"com.acme.editor.api"`.
///
/// One host may publish several — a stable core vocabulary and an experimental
/// one, versioned separately — so compatibility is computed per vocabulary
/// rather than against the app's marketing version.
public struct VocabularyID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Identifies one extension point within a vocabulary.
public struct ExtensionPointID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Identifies a capability a plugin may request, e.g. `"fs.read"`.
public struct CapabilityID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Identifies an event topic, e.g. `"document.opened"`.
public struct TopicID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Identifies a contract one plugin publishes for others to consume.
public struct ServiceID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Identifies a runtime backend, e.g. `"inProcess"`.
public struct RuntimeID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Loaded into the host's address space. Fastest, no isolation.
    public static let inProcess: RuntimeID = "inProcess"
    /// A sandboxed child process reached over XPC.
    public static let xpc: RuntimeID = "xpc"
    /// An OS-managed app extension.
    public static let appExtension: RuntimeID = "appExtension"
    /// An interpreted script.
    public static let script: RuntimeID = "script"
}

/// Identifies a place plugins are discovered from.
public struct SourceID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let builtIn: SourceID = "builtIn"
    public static let user: SourceID = "user"
    public static let machine: SourceID = "machine"
    public static let development: SourceID = "development"
    public static let registered: SourceID = "registered"
}

/// Who a plugin is, as seen from inside it.
///
/// Passed to a plugin through ``PluginContext`` and used by the host to scope
/// storage, logging, and capability grants. Carries the version because a
/// plugin's own migration code needs to know which build it is.
public struct PluginIdentity: Hashable, Sendable, Codable, CustomStringConvertible {
    public let id: PluginID
    public let version: SemanticVersion
    public let displayName: String

    public init(id: PluginID, version: SemanticVersion, displayName: String) {
        self.id = id
        self.version = version
        self.displayName = displayName
    }

    public var description: String { "\(id) \(version)" }
}

/// Fully qualifies one contribution: which plugin, to which point, under which
/// plugin-local name.
///
/// The local name only has to be unique within its plugin, so a plugin author
/// can pick readable names (`"render"`) without coordinating with anyone.
public struct ContributionKey: Hashable, Sendable, Codable, CustomStringConvertible {
    public let plugin: PluginID
    public let extensionPoint: ExtensionPointID
    /// Unique within `plugin` for `extensionPoint`.
    public let name: String

    public init(plugin: PluginID, extensionPoint: ExtensionPointID, name: String) {
        self.plugin = plugin
        self.extensionPoint = extensionPoint
        self.name = name
    }

    public var description: String { "\(plugin)/\(extensionPoint)#\(name)" }
}
