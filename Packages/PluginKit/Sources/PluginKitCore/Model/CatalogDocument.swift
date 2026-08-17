import Foundation

/// A host's published vocabulary, as data.
///
/// The answer to "how does a plugin author find out what extension points exist
/// without reading the host's source?" A host emits this from its registered
/// extension points and ships it in its app bundle; `pluginkit describe` reads it
/// straight out of an *installed* app. So an author with nothing but
/// `/Applications/Acme.app` can enumerate the sockets, their contract versions,
/// their metadata shapes, and which of them are in-process only.
///
/// It lives in Core so the host emits and the CLI reads the same type — there is
/// no second, drifting definition of the format.
public struct CatalogDocument: Hashable, Sendable, Codable {
    /// Format version of this document, not of anything it describes.
    public var formatVersion: Int
    public var appIdentifier: String
    public var appVersion: SemanticVersion
    public var pluginKitVersion: SemanticVersion
    public var vocabularies: [VocabularyDescriptor]
    public var extensionPoints: [ExtensionPointDescriptor]
    public var capabilities: [CapabilityDescriptor]
    public var topics: [TopicDescriptor]

    public init(
        formatVersion: Int = 1,
        appIdentifier: String,
        appVersion: SemanticVersion,
        pluginKitVersion: SemanticVersion = PluginKitVersion.current,
        vocabularies: [VocabularyDescriptor] = [],
        extensionPoints: [ExtensionPointDescriptor] = [],
        capabilities: [CapabilityDescriptor] = [],
        topics: [TopicDescriptor] = []
    ) {
        self.formatVersion = formatVersion
        self.appIdentifier = appIdentifier
        self.appVersion = appVersion
        self.pluginKitVersion = pluginKitVersion
        self.vocabularies = vocabularies
        self.extensionPoints = extensionPoints
        self.capabilities = capabilities
        self.topics = topics
    }

    public static func load(from url: URL) throws -> CatalogDocument {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CatalogDocument.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func extensionPoint(_ id: ExtensionPointID) -> ExtensionPointDescriptor? {
        extensionPoints.first { $0.id == id }
    }

    public func vocabulary(_ id: VocabularyID) -> VocabularyDescriptor? {
        vocabularies.first { $0.id == id }
    }

    public func capability(_ id: CapabilityID) -> CapabilityDescriptor? {
        capabilities.first { $0.id == id }
    }
}

/// One published vocabulary and the range of it this host still accepts.
public struct VocabularyDescriptor: Hashable, Sendable, Codable {
    public var id: VocabularyID
    /// What the host is currently on.
    public var version: SemanticVersion
    /// What it still accepts plugins to have been built against. Wider than
    /// `version` whenever the host is keeping an older major alive.
    public var accepts: VersionRange

    public init(id: VocabularyID, version: SemanticVersion, accepts: VersionRange? = nil) {
        self.id = id
        self.version = version
        self.accepts = accepts ?? .series(of: version)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(VocabularyID.self, forKey: .id)
        let version = try container.decode(SemanticVersion.self, forKey: .version)
        let accepts = try container.decodeIfPresent(VersionRange.self, forKey: .accepts)
        self.init(id: id, version: version, accepts: accepts)
    }

    private enum CodingKeys: String, CodingKey { case id, version, accepts }
}

/// One extension point, described for an author who cannot read the host's code.
public struct ExtensionPointDescriptor: Hashable, Sendable, Codable {
    public var id: ExtensionPointID
    public var vocabulary: VocabularyID
    public var contractVersion: SemanticVersion
    public var accepts: VersionRange
    public var arity: ExtensionPointArity
    public var locality: ContractLocality
    /// A rendering of the `Metadata` type's fields. Best-effort documentation —
    /// authors get compile-time truth from the contract package; this is for
    /// discovery, and for anyone not writing Swift.
    public var metadataShape: [MetadataFieldDescriptor]
    public var summary: String?
    public var deprecations: [ContractDeprecation]

    public init(
        id: ExtensionPointID,
        vocabulary: VocabularyID,
        contractVersion: SemanticVersion,
        accepts: VersionRange,
        arity: ExtensionPointArity,
        locality: ContractLocality,
        metadataShape: [MetadataFieldDescriptor] = [],
        summary: String? = nil,
        deprecations: [ContractDeprecation] = []
    ) {
        self.id = id
        self.vocabulary = vocabulary
        self.contractVersion = contractVersion
        self.accepts = accepts
        self.arity = arity
        self.locality = locality
        self.metadataShape = metadataShape
        self.summary = summary
        self.deprecations = deprecations
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ExtensionPointID.self, forKey: .id)
        vocabulary = try container.decode(VocabularyID.self, forKey: .vocabulary)
        contractVersion = try container.decode(SemanticVersion.self, forKey: .contractVersion)
        accepts = try container.decode(VersionRange.self, forKey: .accepts)
        arity = try container.decode(ExtensionPointArity.self, forKey: .arity)
        locality = try container.decode(ContractLocality.self, forKey: .locality)
        metadataShape = try container.decodeIfPresent(
            [MetadataFieldDescriptor].self, forKey: .metadataShape
        ) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        deprecations = try container.decodeIfPresent(
            [ContractDeprecation].self, forKey: .deprecations
        ) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, vocabulary, contractVersion, accepts, arity, locality
        case metadataShape, summary, deprecations
    }
}

public struct MetadataFieldDescriptor: Hashable, Sendable, Codable {
    public var name: String
    public var type: String
    public var required: Bool
    public var summary: String?

    public init(name: String, type: String, required: Bool = true, summary: String? = nil) {
        self.name = name
        self.type = type
        self.required = required
        self.summary = summary
    }
}

/// A contract major series the host still accepts but intends to remove.
///
/// The bridge between "the host bumped a version" and "the author found out".
/// Attached to plugins as a ``PluginWarning`` at validation time, so a plugin on
/// a deprecated contract keeps working *and* says so — in the manager UI, in
/// diagnostics, and in `pluginkit validate`.
public struct ContractDeprecation: Hashable, Sendable, Codable {
    /// The major version being phased out.
    public var major: Int
    /// Vocabulary version that deprecated it.
    public var since: SemanticVersion
    /// Vocabulary version that will drop it. A host commits to keeping the
    /// previous major working for at least two minor releases.
    public var removedIn: SemanticVersion
    /// What the author should change. Shown verbatim, so write it for them.
    public var guidance: String

    public init(major: Int, since: SemanticVersion, removedIn: SemanticVersion, guidance: String) {
        self.major = major
        self.since = since
        self.removedIn = removedIn
        self.guidance = guidance
    }
}

/// One capability a host will consider granting.
public struct CapabilityDescriptor: Hashable, Sendable, Codable {
    public var id: CapabilityID
    public var sensitivity: CapabilitySensitivity
    public var summary: String?
    /// An example scope, so an author can see the shape without guessing.
    public var scopeExample: JSONValue?

    public init(
        id: CapabilityID,
        sensitivity: CapabilitySensitivity,
        summary: String? = nil,
        scopeExample: JSONValue? = nil
    ) {
        self.id = id
        self.sensitivity = sensitivity
        self.summary = summary
        self.scopeExample = scopeExample
    }
}

/// One event topic, and which direction traffic flows.
public struct TopicDescriptor: Hashable, Sendable, Codable {
    public var id: TopicID
    /// Whether a plugin may publish to it, or only listen. Host-authored events
    /// are usually listen-only: a plugin forging `document.saved` would be able
    /// to mislead every other plugin.
    public var pluginMayPublish: Bool
    public var summary: String?

    public init(id: TopicID, pluginMayPublish: Bool = false, summary: String? = nil) {
        self.id = id
        self.pluginMayPublish = pluginMayPublish
        self.summary = summary
    }
}
