import Foundation

/// One declared addition to a host extension point.
///
/// A contribution has two halves, and the split is the point of it:
///
/// - **``metadata``** — declarative, readable from the manifest. Everything the
///   host needs to *present* the contribution: a menu title, a file type, a
///   category, a sort key.
/// - **the contract** — code, produced by a factory the plugin registers during
///   activation, and resolved only when the contribution is actually used.
///
/// So a host builds its entire command palette from `metadata` at launch and
/// loads a plugin the first time someone picks one of its commands. A plugin the
/// user never invokes never executes.
public struct Contribution: Hashable, Sendable, Codable {
    /// Which host extension point this targets.
    public var extensionPoint: ExtensionPointID

    /// Unique within this plugin, for this point. Chosen by the author; it only
    /// has to be locally unique, so no coordination with anyone is needed.
    public var name: String

    /// The point's contract version the author compiled against.
    ///
    /// Checked against the host's accepted range *before loading*, so a plugin
    /// built for an incompatible contract is reported with a version mismatch
    /// rather than crashing when its factory returns the wrong type.
    public var contractVersion: SemanticVersion

    /// Sort key for points with `.many(ordering: .priority)`. Higher first.
    public var priority: Int

    /// Declarative payload, decoded into the point's `Metadata` type by the host.
    public var metadata: JSONValue

    public init(
        extensionPoint: ExtensionPointID,
        name: String,
        contractVersion: SemanticVersion,
        priority: Int = 0,
        metadata: JSONValue = .object([:])
    ) {
        self.extensionPoint = extensionPoint
        self.name = name
        self.contractVersion = contractVersion
        self.priority = priority
        self.metadata = metadata
    }

    /// Convenience for authors: builds `metadata` from a typed value, so the
    /// contribution and the host's `Metadata` type stay in step at compile time
    /// on the author's side too.
    ///
    /// Labelled `encoding:` rather than overloading `metadata:` because
    /// ``JSONValue`` is itself `Encodable`, and an overload pair that differs only
    /// in a generic constraint would resolve to the throwing one for every caller.
    public init<Metadata: Encodable>(
        extensionPoint: ExtensionPointID,
        name: String,
        contractVersion: SemanticVersion,
        priority: Int = 0,
        encoding metadata: Metadata
    ) throws {
        self.init(
            extensionPoint: extensionPoint,
            name: name,
            contractVersion: contractVersion,
            priority: priority,
            metadata: try JSONValue(encoding: metadata)
        )
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        extensionPoint = try container.decode(ExtensionPointID.self, forKey: .extensionPoint)
        name = try container.decode(String.self, forKey: .name)
        contractVersion = try container.decode(SemanticVersion.self, forKey: .contractVersion)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        metadata = try container.decodeIfPresent(JSONValue.self, forKey: .metadata) ?? .object([:])
    }

    private enum CodingKeys: String, CodingKey {
        case extensionPoint, name, contractVersion, priority, metadata
    }
}

/// A host service a plugin asks for, with the scope it wants and the reason it
/// wants it.
///
/// Declared in the manifest, which means a user or an administrator can read the
/// complete list of what a plugin will ever ask for before installing it, and
/// the host can refuse anything not on the list at runtime.
public struct CapabilityRequest: Hashable, Sendable, Codable {
    public var id: CapabilityID

    /// The attenuation the plugin is asking for — a set of directory roots, an
    /// allowlist of hosts, a topic pattern. Interpreted by the capability's own
    /// `Scope` type; opaque to PluginKit.
    ///
    /// Policy can only ever narrow this, never widen it.
    public var scope: JSONValue

    /// When `false`, denial degrades the plugin rather than blocking it.
    ///
    /// Authors should prefer `false` and handle the throw: a plugin that refuses
    /// to load without clipboard access is a worse experience than one that
    /// hides a paste button.
    public var required: Bool

    /// Shown verbatim in the consent prompt. Write it for the user, not for the
    /// log.
    public var reason: String

    public init(
        id: CapabilityID,
        scope: JSONValue = .object([:]),
        required: Bool = false,
        reason: String
    ) {
        self.id = id
        self.scope = scope
        self.required = required
        self.reason = reason
    }

    /// Labelled `encoding:` for the same reason as ``Contribution``'s typed
    /// initialiser: ``JSONValue`` is `Encodable`, so a bare overload would capture
    /// every call.
    public init<Scope: Encodable>(
        id: CapabilityID,
        encoding scope: Scope,
        required: Bool = false,
        reason: String
    ) throws {
        self.init(
            id: id,
            scope: try JSONValue(encoding: scope),
            required: required,
            reason: reason
        )
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(CapabilityID.self, forKey: .id)
        scope = try container.decodeIfPresent(JSONValue.self, forKey: .scope) ?? .object([:])
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case id, scope, required, reason }
}

/// When a plugin's code is loaded and activated.
public enum ActivationPolicy: Hashable, Sendable, Codable {
    /// At host start. Costs launch time for every user whether or not the plugin
    /// is ever used, so it carries a mandatory justification that a plugin
    /// manager UI can display — visible cost, visible reason.
    case eager(reason: String)

    /// The default and the right answer almost always: load on the first
    /// `resolve()` of one of this plugin's contributions.
    case onDemand

    /// Load when the host publishes a matching event, e.g. a document of a
    /// particular type being opened.
    case onEvent(patterns: [String])

    private enum CodingKeys: String, CodingKey { case kind, reason, patterns }
    private enum Kind: String, Codable { case eager, onDemand, onEvent }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .eager:
            self = .eager(reason: try container.decodeIfPresent(String.self, forKey: .reason) ?? "")
        case .onDemand:
            self = .onDemand
        case .onEvent:
            self = .onEvent(patterns: try container.decode([String].self, forKey: .patterns))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .eager(let reason):
            try container.encode(Kind.eager, forKey: .kind)
            try container.encode(reason, forKey: .reason)
        case .onDemand:
            try container.encode(Kind.onDemand, forKey: .kind)
        case .onEvent(let patterns):
            try container.encode(Kind.onEvent, forKey: .kind)
            try container.encode(patterns, forKey: .patterns)
        }
    }

    /// Whether the host must load this plugin during startup.
    public var isEager: Bool {
        if case .eager = self { return true }
        return false
    }
}

/// Where the author would like the plugin to run.
///
/// A request, never a decision. ``RuntimeSelector`` resolves it against the
/// plugin's trust level and the runtimes the host actually ships — a plugin that
/// could pick its own isolation would make isolation meaningless.
public enum RuntimeRequirement: Hashable, Sendable, Codable {
    /// In the host's address space. `entryPoint` names the principal class in
    /// the bundle; `nil` means "use the bundle's declared principal class".
    case inProcess(entryPoint: String?)
    /// A sandboxed child process.
    case xpc(serviceName: String)
    /// An OS-managed app extension.
    case appExtension(pointIdentifier: String)
    /// An interpreted script.
    case script(engine: String, entry: String)
    /// A runtime the host registered itself. The escape hatch that lets a host
    /// adapt a legacy plugin loader without patching PluginKit.
    case custom(RuntimeID, options: JSONValue)

    private enum CodingKeys: String, CodingKey {
        case kind, entryPoint, serviceName, pointIdentifier, engine, entry, runtimeID, options
    }
    private enum Kind: String, Codable { case inProcess, xpc, appExtension, script, custom }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .inProcess:
            self = .inProcess(entryPoint: try container.decodeIfPresent(String.self, forKey: .entryPoint))
        case .xpc:
            self = .xpc(serviceName: try container.decode(String.self, forKey: .serviceName))
        case .appExtension:
            self = .appExtension(
                pointIdentifier: try container.decode(String.self, forKey: .pointIdentifier)
            )
        case .script:
            self = .script(
                engine: try container.decode(String.self, forKey: .engine),
                entry: try container.decode(String.self, forKey: .entry)
            )
        case .custom:
            self = .custom(
                try container.decode(RuntimeID.self, forKey: .runtimeID),
                options: try container.decodeIfPresent(JSONValue.self, forKey: .options) ?? .object([:])
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inProcess(let entryPoint):
            try container.encode(Kind.inProcess, forKey: .kind)
            try container.encodeIfPresent(entryPoint, forKey: .entryPoint)
        case .xpc(let serviceName):
            try container.encode(Kind.xpc, forKey: .kind)
            try container.encode(serviceName, forKey: .serviceName)
        case .appExtension(let pointIdentifier):
            try container.encode(Kind.appExtension, forKey: .kind)
            try container.encode(pointIdentifier, forKey: .pointIdentifier)
        case .script(let engine, let entry):
            try container.encode(Kind.script, forKey: .kind)
            try container.encode(engine, forKey: .engine)
            try container.encode(entry, forKey: .entry)
        case .custom(let id, let options):
            try container.encode(Kind.custom, forKey: .kind)
            try container.encode(id, forKey: .runtimeID)
            try container.encode(options, forKey: .options)
        }
    }

    /// The runtime the author asked for, when it maps to a well-known one.
    public var preferredRuntime: RuntimeID {
        switch self {
        case .inProcess: return .inProcess
        case .xpc: return .xpc
        case .appExtension: return .appExtension
        case .script: return .script
        case .custom(let id, _): return id
        }
    }
}
