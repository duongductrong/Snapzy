import Foundation

/// A typed socket a host publishes for plugins to plug into.
///
/// PluginKit ships **no** extension points. A host declares its own vocabulary —
/// commands, exporters, inspectors, linters, whatever it actually has — in a
/// package plugin authors can compile against. That is the mechanism behind
/// "adapts to different apps": the framework provides declaration, discovery,
/// ordering, versioning, and lazy resolution, and never learns a single domain
/// concept.
///
/// Each point has two halves:
///
/// - ``Metadata`` — declarative, lives in the manifest, read without loading code.
/// - ``Contract`` — the code a plugin provides, resolved on first use.
///
/// ```swift
/// public enum CommandPoint: RemotableExtensionPoint {
///     public typealias Contract = any Command
///     public struct Metadata: Codable, Sendable {
///         public let title: String
///         public let category: String
///     }
///     public static let extensionPointID: ExtensionPointID = "com.acme.editor.command"
///     public static let vocabulary: VocabularyID = "com.acme.editor.api"
///     public static let contractVersion: SemanticVersion = "1.0.0"
///
///     public typealias Request = RunCommand
///     public typealias Response = CommandResult
///     public static func invoke(
///         _ contract: Contract, with request: RunCommand
///     ) async throws -> CommandResult {
///         try await contract.handle(request)
///     }
/// }
/// ```
public protocol ExtensionPoint: Sendable {
    /// The code a contribution provides. Usually `any SomeProtocol`.
    associatedtype Contract: Sendable

    /// The declarative half. Defaults to ``EmptyMetadata`` for points that need
    /// no manifest payload.
    associatedtype Metadata: Codable & Sendable = EmptyMetadata

    static var extensionPointID: ExtensionPointID { get }

    /// Which published vocabulary this belongs to. Compatibility is computed per
    /// vocabulary, so a host can evolve an experimental point without forcing a
    /// major bump on its stable ones.
    static var vocabulary: VocabularyID { get }

    /// The contract's own version. Bumped by the rules in the framework's
    /// versioning documentation: adding an optional metadata field is a minor
    /// bump, changing a field's meaning is a major one.
    static var contractVersion: SemanticVersion { get }

    /// How many contributions are accepted, and in what order.
    static var arity: ExtensionPointArity { get }
}

extension ExtensionPoint {
    /// Most points want many contributions, priority-ordered. `.single` is the
    /// unusual case and should be stated deliberately.
    public static var arity: ExtensionPointArity { .many(ordering: .priority) }
}

/// A point whose contract can cross a process boundary.
///
/// **The default, and it should stay that way.** A remotable point can be hosted
/// in-process, over XPC, in an app extension, or in a script runtime without the
/// host or the plugin changing a line — which is what makes isolation a
/// deployment policy rather than a rewrite.
///
/// Remotability is expressed as a `Request`/`Response` pair plus an ``invoke``
/// shim rather than as a constraint on ``Contract``, for two reasons. The
/// mechanical one is that `Contract` is normally an existential (`any Command`),
/// and an existential does not conform to the protocol it erases, so
/// `where Contract: RemotableContract` cannot be written. The better one is that
/// ``invoke`` gives the framework a *uniform way to actually call* any remotable
/// contract — which is what a transport needs. A marker constraint would only
/// have labelled the point; this makes location transparency mechanically true.
///
/// The shim is one line per point.
public protocol RemotableExtensionPoint: ExtensionPoint {
    associatedtype Request: Codable & Sendable
    associatedtype Response: Codable & Sendable

    /// Applies `request` to a contract instance.
    ///
    /// Called directly in-process, and after a serialization round-trip by every
    /// other transport. `PluginHarness`'s serializing mode uses exactly this to
    /// prove a contract really is remotable, before anyone tries to ship it
    /// out-of-process.
    static func invoke(_ contract: Contract, with request: Request) async throws -> Response
}

/// A point whose contract cannot leave the host's address space.
///
/// The opt-out, and it costs something: a contribution to a local point can only
/// be hosted in-process, so a plugin the host does not trust enough to run
/// in-process is reported ``PluginPhase/unsatisfied`` instead of loading. That is
/// intentional friction — the escape hatch should be visible.
///
/// A legitimate use is vending live `NSView` instances into the host's view
/// hierarchy. Even that is remotable in principle via app-extension remote view
/// controllers at the cost of a narrower interaction model, so treat every
/// conformance here as a debt entry rather than a settled fact.
public protocol LocalExtensionPoint: ExtensionPoint {
    /// Why this cannot be remoted. Surfaced by `pluginkit describe` and in the
    /// emitted catalog, so an author discovers the constraint while choosing
    /// which point to target — not after their sandboxed plugin fails to load.
    static var localityReason: String { get }
}

/// How many contributions a point accepts, and how they are ordered.
public enum ExtensionPointArity: Hashable, Sendable, Codable {
    /// At most one wins. Ties break by priority, then by source precedence, so
    /// the outcome is deterministic rather than load-order dependent.
    case single
    case many(ordering: ContributionOrdering)

    private enum CodingKeys: String, CodingKey { case kind, ordering }
    private enum Kind: String, Codable { case single, many }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .single:
            self = .single
        case .many:
            self = .many(
                ordering: try container.decodeIfPresent(ContributionOrdering.self, forKey: .ordering)
                    ?? .priority
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .single:
            try container.encode(Kind.single, forKey: .kind)
        case .many(let ordering):
            try container.encode(Kind.many, forKey: .kind)
            try container.encode(ordering, forKey: .ordering)
        }
    }
}

public enum ContributionOrdering: String, Hashable, Sendable, Codable {
    /// Manifest order, then discovery order. For points where the plugin author
    /// knows best and the host has no opinion.
    case declared
    /// Descending ``Contribution/priority``. Ties fall back to `declared`.
    case priority
}

/// Whether a point's contract can cross a process boundary.
///
/// The erased form of the ``RemotableExtensionPoint`` / ``LocalExtensionPoint``
/// distinction, for the catalog and the emitted JSON — the framework has to
/// reason about locality without knowing the concrete point type.
public enum ContractLocality: Hashable, Sendable, Codable {
    case remotable
    case local(reason: String)

    public var requiresInProcess: Bool {
        if case .local = self { return true }
        return false
    }

    private enum CodingKeys: String, CodingKey { case kind, reason }
    private enum Kind: String, Codable { case remotable, local }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .remotable: self = .remotable
        case .local: self = .local(reason: try container.decode(String.self, forKey: .reason))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .remotable:
            try container.encode(Kind.remotable, forKey: .kind)
        case .local(let reason):
            try container.encode(Kind.local, forKey: .kind)
            try container.encode(reason, forKey: .reason)
        }
    }
}

/// The recommended shape for a remotable contract.
///
/// A single `handle(_:)` taking and returning `Codable` values. Verbose for a
/// multi-operation contract — model those as an enum `Request` — but it needs no
/// code generation, works identically across every transport, and is trivially
/// recordable and replayable in tests.
///
/// Richer multi-method remotable protocols need a generated proxy and skeleton;
/// see the roadmap. Nothing here blocks that later, because ``invoke`` already
/// abstracts how a call is delivered.
public protocol RemotableContract: Sendable {
    associatedtype Request: Codable & Sendable
    associatedtype Response: Codable & Sendable
    func handle(_ request: Request) async throws -> Response
}
