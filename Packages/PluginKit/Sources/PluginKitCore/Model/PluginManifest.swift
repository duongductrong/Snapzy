import Foundation

/// Everything a host needs to know about a plugin *without loading it*.
///
/// This is the load-bearing type of the whole framework. A host reads manifests
/// at launch, validates them, resolves dependencies, renders menus and settings
/// panes from them, and enforces capability disclosure against them — all
/// before a single line of plugin code is mapped into memory. Sixty installed
/// plugins should cost sixty small JSON reads at startup, not sixty `dlopen`s.
///
/// It is also *authoritative*. A plugin cannot contribute to a point, request a
/// capability, or publish a service it did not declare here. That is a drift
/// check for the honest case and a containment boundary for the dishonest one.
///
/// On disk this is `plugin.json` inside the plugin bundle:
///
/// ```json
/// {
///   "id": "com.example.wordcount",
///   "version": "1.0.0",
///   "displayName": "Word Count",
///   "sdkVersion": ">=1.0.0 <2.0.0",
///   "contracts": [
///     { "vocabulary": "com.acme.editor.api",
///       "builtAgainst": "1.0.0", "compatibleWith": ">=1.0.0 <2.0.0" }
///   ],
///   "runtime": { "kind": "inProcess", "entryPoint": "WordCountPlugin" },
///   "activation": { "kind": "onDemand" },
///   "capabilities": [
///     { "id": "fs.read", "required": false, "reason": "Counts words in the open file.",
///       "scope": { "roots": ["~/Documents"] } }
///   ],
///   "contributions": [
///     { "extensionPoint": "com.acme.editor.command", "name": "count",
///       "contractVersion": "1.0.0", "priority": 10,
///       "metadata": { "title": "Count Words", "category": "Text" } }
///   ]
/// }
/// ```
public struct PluginManifest: Hashable, Sendable, Codable {
    /// Reverse-DNS identity. Stable across versions.
    public var id: PluginID

    /// This build's version. Drives upgrade detection and config migration.
    public var version: SemanticVersion

    /// Shown in a plugin manager UI.
    public var displayName: String

    /// One or two sentences, also for the UI.
    public var summary: String?

    public var author: PluginAuthor?

    /// The PluginKit generation this plugin was built against. A host refuses
    /// anything outside its own supported range rather than loading it and
    /// hoping.
    public var sdkVersion: VersionRange

    /// Host vocabularies this plugin compiled against, and the versions it
    /// claims to support. Empty for a plugin that only uses PluginKit's own
    /// surface and contributes nothing.
    public var contracts: [ContractDependency]

    /// Where the author would like this to run. A *request*, not a decision —
    /// the host's ``RuntimeSelector`` has the final say, because a plugin
    /// choosing its own isolation level would defeat the point of having any.
    public var runtime: RuntimeRequirement

    public var activation: ActivationPolicy

    /// Host services this plugin needs, each with a user-facing reason. The
    /// complete set: anything not listed here is unreachable at runtime.
    public var capabilities: [CapabilityRequest]

    /// Other plugins this one needs.
    public var dependencies: [PluginDependency]

    /// Contracts this plugin publishes for other plugins to consume.
    public var provides: [ServiceDeclaration]

    /// What this plugin adds to the host, declaratively.
    public var contributions: [Contribution]

    /// Settings schema, so the host can render a preferences pane without
    /// loading code.
    public var configuration: ConfigurationSchema?

    /// Minimum macOS version, when the plugin needs more than the host does.
    public var minimumOSVersion: SemanticVersion?

    public init(
        id: PluginID,
        version: SemanticVersion,
        displayName: String,
        summary: String? = nil,
        author: PluginAuthor? = nil,
        sdkVersion: VersionRange = .any,
        contracts: [ContractDependency] = [],
        runtime: RuntimeRequirement = .inProcess(entryPoint: nil),
        activation: ActivationPolicy = .onDemand,
        capabilities: [CapabilityRequest] = [],
        dependencies: [PluginDependency] = [],
        provides: [ServiceDeclaration] = [],
        contributions: [Contribution] = [],
        configuration: ConfigurationSchema? = nil,
        minimumOSVersion: SemanticVersion? = nil
    ) {
        self.id = id
        self.version = version
        self.displayName = displayName
        self.summary = summary
        self.author = author
        self.sdkVersion = sdkVersion
        self.contracts = contracts
        self.runtime = runtime
        self.activation = activation
        self.capabilities = capabilities
        self.dependencies = dependencies
        self.provides = provides
        self.contributions = contributions
        self.configuration = configuration
        self.minimumOSVersion = minimumOSVersion
    }

    /// The identity a plugin sees for itself.
    public var identity: PluginIdentity {
        PluginIdentity(id: id, version: version, displayName: displayName)
    }

    // Optional keys decode as absent rather than requiring `null` in the JSON,
    // so a hand-written manifest can be as short as its author's actual needs.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(PluginID.self, forKey: .id)
        version = try container.decode(SemanticVersion.self, forKey: .version)
        displayName = try container.decode(String.self, forKey: .displayName)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        author = try container.decodeIfPresent(PluginAuthor.self, forKey: .author)
        sdkVersion = try container.decodeIfPresent(VersionRange.self, forKey: .sdkVersion) ?? .any
        contracts = try container.decodeIfPresent([ContractDependency].self, forKey: .contracts) ?? []
        runtime = try container.decodeIfPresent(RuntimeRequirement.self, forKey: .runtime)
            ?? .inProcess(entryPoint: nil)
        activation = try container.decodeIfPresent(ActivationPolicy.self, forKey: .activation) ?? .onDemand
        capabilities = try container.decodeIfPresent([CapabilityRequest].self, forKey: .capabilities) ?? []
        dependencies = try container.decodeIfPresent([PluginDependency].self, forKey: .dependencies) ?? []
        provides = try container.decodeIfPresent([ServiceDeclaration].self, forKey: .provides) ?? []
        contributions = try container.decodeIfPresent([Contribution].self, forKey: .contributions) ?? []
        configuration = try container.decodeIfPresent(ConfigurationSchema.self, forKey: .configuration)
        minimumOSVersion = try container.decodeIfPresent(SemanticVersion.self, forKey: .minimumOSVersion)
    }

    private enum CodingKeys: String, CodingKey {
        case id, version, displayName, summary, author, sdkVersion, contracts
        case runtime, activation, capabilities, dependencies, provides
        case contributions, configuration, minimumOSVersion
    }
}

// MARK: - Reading and writing

extension PluginManifest {
    /// Decodes a manifest from JSON.
    ///
    /// Wraps `DecodingError` in ``PluginManifestError`` because the raw message
    /// names Swift types the plugin author never wrote and cannot act on.
    public static func decode(from data: Data) throws -> PluginManifest {
        do {
            return try JSONDecoder().decode(PluginManifest.self, from: data)
        } catch let error as DecodingError {
            throw PluginManifestError.decodingFailed(reason: Self.describe(error))
        } catch {
            throw PluginManifestError.decodingFailed(reason: error.localizedDescription)
        }
    }

    public static func load(from url: URL) throws -> PluginManifest {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PluginManifestError.fileNotFound(url)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PluginManifestError.unreadable(reason: error.localizedDescription)
        }
        return try decode(from: data)
    }

    /// Stable, human-diffable JSON. Sorted keys and pretty printing because
    /// manifests live in version control and are reviewed by people.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Renders a `DecodingError` as something a plugin author can act on: which
    /// key, at which path, and what was wrong with it.
    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let joined = context.codingPath.map(\.stringValue).joined(separator: ".")
            return joined.isEmpty ? "(root)" : joined
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "missing required key '\(key.stringValue)' at \(path(context))"
        case .typeMismatch(let type, let context):
            return "expected \(type) at \(path(context)) — \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "expected a value of type \(type) at \(path(context))"
        case .dataCorrupted(let context):
            return "\(path(context)): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}

// MARK: - Structural validation

extension PluginManifest {
    /// Checks the invariants the rest of the framework assumes.
    ///
    /// Run once at discovery so that every later stage — resolution, brokering,
    /// registration — can treat a manifest as well-formed instead of
    /// re-validating defensively at each hop.
    public func validateStructure() throws {
        guard !id.rawValue.isEmpty else {
            throw PluginManifestError.invalid(reason: "The plugin identifier is empty.")
        }
        guard !displayName.isEmpty else {
            throw PluginManifestError.invalid(reason: "The plugin display name is empty.")
        }

        var seenContributions = Set<String>()
        for contribution in contributions {
            guard !contribution.name.isEmpty else {
                throw PluginManifestError.invalid(
                    reason: "A contribution to '\(contribution.extensionPoint)' has an empty name."
                )
            }
            let key = "\(contribution.extensionPoint)#\(contribution.name)"
            guard seenContributions.insert(key).inserted else {
                throw PluginManifestError.invalid(reason: "Duplicate contribution '\(key)'.")
            }
        }

        var seenCapabilities = Set<CapabilityID>()
        for request in capabilities {
            guard seenCapabilities.insert(request.id).inserted else {
                throw PluginManifestError.invalid(
                    reason: "Capability '\(request.id)' is requested more than once."
                )
            }
            // An empty reason is not a formatting nit: it is the entire text a
            // user is shown when deciding whether to grant access. The manifest
            // cannot know how sensitive a capability is — that is the host's
            // classification — so every request must justify itself.
            guard !request.reason.isEmpty else {
                throw PluginManifestError.invalid(
                    reason: "Capability '\(request.id)' needs a reason to show the user."
                )
            }
        }

        for dependency in dependencies where dependency.id == id {
            throw PluginManifestError.invalid(reason: "The plugin depends on itself.")
        }

        var seenServices = Set<ServiceID>()
        for service in provides {
            guard seenServices.insert(service.id).inserted else {
                throw PluginManifestError.invalid(reason: "Service '\(service.id)' is declared twice.")
            }
        }

        try configuration?.validateStructure()
    }

    /// Looks up a declared contribution. The host consults this on every
    /// registration attempt, which is how manifest authority is enforced.
    public func contribution(to point: ExtensionPointID, named name: String) -> Contribution? {
        contributions.first { $0.extensionPoint == point && $0.name == name }
    }

    public func capabilityRequest(for id: CapabilityID) -> CapabilityRequest? {
        capabilities.first { $0.id == id }
    }

    public func declaresService(_ id: ServiceID) -> Bool {
        provides.contains { $0.id == id }
    }
}

/// Who wrote a plugin. Display-only; never a trust input — trust comes from the
/// code signature, which cannot be typed into a JSON file.
public struct PluginAuthor: Hashable, Sendable, Codable {
    public var name: String
    public var email: String?
    public var url: URL?

    public init(name: String, email: String? = nil, url: URL? = nil) {
        self.name = name
        self.email = email
        self.url = url
    }
}

/// A host vocabulary the plugin was compiled against.
///
/// `builtAgainst` is exact and `compatibleWith` is a claim. Recording both is
/// what turns a version mismatch from "this plugin silently stopped appearing"
/// into "built against 1.4.0, this host provides 2.1.0, which is outside the
/// >=1.0.0 <2.0.0 range you declared" — a message the author can act on.
public struct ContractDependency: Hashable, Sendable, Codable {
    public var vocabulary: VocabularyID
    public var builtAgainst: SemanticVersion
    public var compatibleWith: VersionRange

    public init(
        vocabulary: VocabularyID,
        builtAgainst: SemanticVersion,
        compatibleWith: VersionRange? = nil
    ) {
        self.vocabulary = vocabulary
        self.builtAgainst = builtAgainst
        // Defaulting to the major series of what it was built against is the
        // claim almost every author means, and the one semver licenses.
        self.compatibleWith = compatibleWith ?? .compatible(with: builtAgainst)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let vocabulary = try container.decode(VocabularyID.self, forKey: .vocabulary)
        let builtAgainst = try container.decode(SemanticVersion.self, forKey: .builtAgainst)
        let compatibleWith = try container.decodeIfPresent(VersionRange.self, forKey: .compatibleWith)
        self.init(vocabulary: vocabulary, builtAgainst: builtAgainst, compatibleWith: compatibleWith)
    }

    private enum CodingKeys: String, CodingKey {
        case vocabulary, builtAgainst, compatibleWith
    }
}

/// A dependency on another plugin.
public struct PluginDependency: Hashable, Sendable, Codable {
    public var id: PluginID
    public var versions: VersionRange
    /// When `false`, the dependent still loads if this is missing — it just does
    /// less. Optional dependencies are how a plugin integrates with another
    /// plugin the user may not have installed.
    public var required: Bool

    public init(id: PluginID, versions: VersionRange = .any, required: Bool = true) {
        self.id = id
        self.versions = versions
        self.required = required
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(PluginID.self, forKey: .id)
        versions = try container.decodeIfPresent(VersionRange.self, forKey: .versions) ?? .any
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? true
    }

    private enum CodingKeys: String, CodingKey { case id, versions, required }
}

/// A contract this plugin publishes for other plugins.
///
/// Consumers never receive the provider's object — the host brokers a proxy — so
/// this declaration is what the host matches a consumer's request against.
public struct ServiceDeclaration: Hashable, Sendable, Codable {
    public var id: ServiceID
    public var version: SemanticVersion
    public var summary: String?

    public init(id: ServiceID, version: SemanticVersion, summary: String? = nil) {
        self.id = id
        self.version = version
        self.summary = summary
    }
}
