import Foundation
import PluginKitCore

/// The host's declaration of its own vocabulary.
///
/// Registering a point does three things a plugin can then be checked against
/// *without loading it*: fixes the contract versions the host accepts, captures a
/// decoder for the point's `Metadata` type, and records whether the contract can
/// leave the host's address space.
///
/// The metadata decoder is the interesting one. The framework never knows a
/// host's metadata types, but the closure captured here does — so a contribution
/// whose declarative payload does not match its point is rejected at discovery,
/// with a message naming the offending field, before any plugin code exists in
/// the process.
public struct ExtensionPointCatalog: Sendable {
    /// The erased form of a registered extension point.
    public struct Entry: Sendable {
        public let id: ExtensionPointID
        public let vocabulary: VocabularyID
        /// The version the host is currently on.
        public let contractVersion: SemanticVersion
        /// What it accepts plugins to have been built against — wider than
        /// `contractVersion` whenever an older major is being kept alive.
        public let accepts: VersionRange
        public let arity: ExtensionPointArity
        public let locality: ContractLocality
        public let deprecations: [ContractDeprecation]
        public let summary: String?
        public let metadataShape: [MetadataFieldDescriptor]

        /// Decodes declarative metadata into the point's `Metadata` type.
        let validateMetadata: @Sendable (JSONValue) throws -> Void
        /// For the mismatch diagnostic, which is read by someone who cannot see
        /// the host's types.
        let contractTypeName: String
    }

    private var entries: [ExtensionPointID: Entry] = [:]

    public init() {}

    /// Registers a remotable point — the default, and the one that keeps every
    /// runtime available.
    public mutating func register<P: RemotableExtensionPoint>(
        _ point: P.Type,
        accepting: VersionRange? = nil,
        summary: String? = nil,
        metadataShape: [MetadataFieldDescriptor] = [],
        deprecations: [ContractDeprecation] = []
    ) {
        insert(
            point,
            locality: .remotable,
            accepting: accepting,
            summary: summary,
            metadataShape: metadataShape,
            deprecations: deprecations
        )
    }

    /// Registers an in-process-only point.
    ///
    /// A plugin contributing here can never be isolated, so one whose trust level
    /// forbids in-process hosting is reported ``PluginPhase/unsatisfied`` rather
    /// than loaded. The friction is the feature.
    public mutating func register<P: LocalExtensionPoint>(
        _ point: P.Type,
        accepting: VersionRange? = nil,
        summary: String? = nil,
        metadataShape: [MetadataFieldDescriptor] = [],
        deprecations: [ContractDeprecation] = []
    ) {
        insert(
            point,
            locality: .local(reason: P.localityReason),
            accepting: accepting,
            summary: summary,
            metadataShape: metadataShape,
            deprecations: deprecations
        )
    }

    private mutating func insert<P: ExtensionPoint>(
        _ point: P.Type,
        locality: ContractLocality,
        accepting: VersionRange?,
        summary: String?,
        metadataShape: [MetadataFieldDescriptor],
        deprecations: [ContractDeprecation]
    ) {
        entries[P.extensionPointID] = Entry(
            id: P.extensionPointID,
            vocabulary: P.vocabulary,
            contractVersion: P.contractVersion,
            // Defaulting to the whole current compatibility series is the
            // accurate reading of semver and spares every host from restating it.
            accepts: accepting ?? .series(of: P.contractVersion),
            arity: P.arity,
            locality: locality,
            deprecations: deprecations,
            summary: summary,
            metadataShape: metadataShape,
            validateMetadata: { json in
                _ = try json.decode(as: P.Metadata.self)
            },
            contractTypeName: String(describing: P.Contract.self)
        )
    }

    public func entry(for id: ExtensionPointID) -> Entry? { entries[id] }

    public var allEntries: [Entry] { entries.values.sorted { $0.id.rawValue < $1.id.rawValue } }

    public var isEmpty: Bool { entries.isEmpty }

    /// Checks one declared contribution against this catalog.
    ///
    /// Runs at discovery time, so every failure here is reported with the plugin
    /// still listed and inert, not as a crash mid-session.
    ///
    /// - Parameter permitsInProcess: whether the plugin's trust level allows
    ///   in-process hosting. Passed in rather than looked up so the catalog stays
    ///   free of trust-policy knowledge.
    /// - Returns: the failure, or `nil` if the contribution is acceptable.
    public func validate(
        _ contribution: Contribution,
        permitsInProcess: Bool
    ) -> ExtensionPointError? {
        guard let entry = entries[contribution.extensionPoint] else {
            return .unknownExtensionPoint(contribution.extensionPoint)
        }

        guard entry.accepts.contains(contribution.contractVersion) else {
            return .contractVersionUnsupported(
                point: entry.id,
                pluginBuiltAgainst: contribution.contractVersion,
                hostAccepts: entry.accepts
            )
        }

        if case .local(let reason) = entry.locality, !permitsInProcess {
            return .localityViolation(point: entry.id, reason: reason)
        }

        do {
            try entry.validateMetadata(contribution.metadata)
        } catch {
            return .metadataDecodingFailed(
                point: entry.id,
                reason: Self.describeMetadataFailure(error)
            )
        }

        return nil
    }

    /// Any deprecation warning that applies to a contribution.
    ///
    /// Returned rather than logged so it can be attached to the plugin's record
    /// and badged in a manager UI. A deprecation only in a log file is a
    /// deprecation nobody acts on.
    public func deprecationWarning(for contribution: Contribution) -> PluginWarning? {
        guard let entry = entries[contribution.extensionPoint],
              let deprecation = entry.deprecations.first(
                  where: { $0.major == contribution.contractVersion.major }
              )
        else { return nil }

        return PluginWarning(
            kind: .deprecatedContract,
            detail: "'\(entry.id)' contract \(contribution.contractVersion) is deprecated "
                + "since \(entry.vocabulary) \(deprecation.since) and will be removed in "
                + "\(deprecation.removedIn).",
            guidance: deprecation.guidance
        )
    }

    /// Whether any of a plugin's contributions force in-process hosting.
    public func requiresInProcess(_ contributions: [Contribution]) -> Bool {
        contributions.contains { contribution in
            entries[contribution.extensionPoint]?.locality.requiresInProcess ?? false
        }
    }

    /// The contract type name for a point, for the type-mismatch diagnostic.
    func contractTypeName(for id: ExtensionPointID) -> String {
        entries[id]?.contractTypeName ?? "unknown"
    }

    private static func describeMetadataFailure(_ error: any Error) -> String {
        guard let decodingError = error as? DecodingError else { return error.localizedDescription }
        switch decodingError {
        case .keyNotFound(let key, _):
            return "missing required field '\(key.stringValue)'"
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "field '\(path)' should be \(type)"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "field '\(path)' is null but must be \(type)"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return decodingError.localizedDescription
        }
    }
}

extension ExtensionPointCatalog {
    /// `Range`-literal spelling of `accepting:`, so a host can write
    /// `accepting: "1.0.0" ..< "3.0.0"`.
    public mutating func register<P: RemotableExtensionPoint>(
        _ point: P.Type,
        accepting range: Range<SemanticVersion>,
        summary: String? = nil,
        metadataShape: [MetadataFieldDescriptor] = [],
        deprecations: [ContractDeprecation] = []
    ) {
        register(
            point,
            accepting: VersionRange(range),
            summary: summary,
            metadataShape: metadataShape,
            deprecations: deprecations
        )
    }

    public mutating func register<P: LocalExtensionPoint>(
        _ point: P.Type,
        accepting range: Range<SemanticVersion>,
        summary: String? = nil,
        metadataShape: [MetadataFieldDescriptor] = [],
        deprecations: [ContractDeprecation] = []
    ) {
        register(
            point,
            accepting: VersionRange(range),
            summary: summary,
            metadataShape: metadataShape,
            deprecations: deprecations
        )
    }

    /// Emits the machine-readable vocabulary description.
    ///
    /// A host writes this into its own app bundle at build or first launch;
    /// `pluginkit describe` then reads it out of an installed app. That is the
    /// whole answer to "how does an author discover the sockets without the
    /// host's source?".
    public func document(
        appIdentifier: String,
        appVersion: SemanticVersion,
        vocabularies: [VocabularyDescriptor] = [],
        capabilities: [CapabilityDescriptor] = [],
        topics: [TopicDescriptor] = []
    ) -> CatalogDocument {
        // Any vocabulary a point mentions but the host did not describe still
        // appears, inferred from the highest contract version in it — better an
        // approximate entry than a silently missing one.
        var described = vocabularies
        for entry in allEntries where !described.contains(where: { $0.id == entry.vocabulary }) {
            let peers = allEntries.filter { $0.vocabulary == entry.vocabulary }
            let highest = peers.map(\.contractVersion).max() ?? entry.contractVersion
            described.append(VocabularyDescriptor(id: entry.vocabulary, version: highest))
        }

        return CatalogDocument(
            appIdentifier: appIdentifier,
            appVersion: appVersion,
            vocabularies: described.sorted { $0.id.rawValue < $1.id.rawValue },
            extensionPoints: allEntries.map { entry in
                ExtensionPointDescriptor(
                    id: entry.id,
                    vocabulary: entry.vocabulary,
                    contractVersion: entry.contractVersion,
                    accepts: entry.accepts,
                    arity: entry.arity,
                    locality: entry.locality,
                    metadataShape: entry.metadataShape,
                    summary: entry.summary,
                    deprecations: entry.deprecations
                )
            },
            capabilities: capabilities.sorted { $0.id.rawValue < $1.id.rawValue },
            topics: topics.sorted { $0.id.rawValue < $1.id.rawValue }
        )
    }
}
