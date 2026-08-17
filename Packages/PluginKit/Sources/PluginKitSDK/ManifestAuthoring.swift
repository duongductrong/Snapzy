import Foundation

/// Builds a manifest in Swift, for authors who would rather not hand-write JSON.
///
/// The manifest stays the *runtime* source of truth — a host must be able to read
/// it without executing anything, so it cannot be derived from code at load time.
/// But an author can legitimately treat code as the *authoring* source of truth
/// and emit `plugin.json` from a small target that uses this builder, which is
/// what removes the drift by construction rather than by discipline.
///
/// ```swift
/// let manifest = PluginManifestBuilder(
///     id: "com.example.wordcount", version: "1.0.0", displayName: "Word Count"
/// )
/// .builtAgainst(vocabulary: "com.acme.editor.api", version: "1.0.0")
/// .requesting("fs.read", reason: "Counts words in the open file.")
/// .contributing(to: "com.acme.editor.command", named: "count",
///               contractVersion: "1.0.0", priority: 10,
///               metadata: ["title": "Count Words"])
/// .build()
///
/// try manifest.encoded().write(to: outputURL)
/// ```
public struct PluginManifestBuilder {
    private var manifest: PluginManifest

    public init(
        id: PluginID,
        version: SemanticVersion,
        displayName: String,
        summary: String? = nil
    ) {
        self.manifest = PluginManifest(
            id: id,
            version: version,
            displayName: displayName,
            summary: summary,
            // Pin to the PluginKit generation the author is compiling against.
            // Defaulting to `.any` would let a plugin built on 0.1 be loaded by a
            // 2.0 host that has changed the contract underneath it.
            sdkVersion: .compatible(with: PluginKitVersion.current)
        )
    }

    public func author(_ author: PluginAuthor) -> Self {
        var copy = self
        copy.manifest.author = author
        return copy
    }

    public func builtAgainst(
        vocabulary: VocabularyID,
        version: SemanticVersion,
        compatibleWith: VersionRange? = nil
    ) -> Self {
        var copy = self
        copy.manifest.contracts.append(
            ContractDependency(
                vocabulary: vocabulary,
                builtAgainst: version,
                compatibleWith: compatibleWith
            )
        )
        return copy
    }

    public func runtime(_ requirement: RuntimeRequirement) -> Self {
        var copy = self
        copy.manifest.runtime = requirement
        return copy
    }

    public func activation(_ policy: ActivationPolicy) -> Self {
        var copy = self
        copy.manifest.activation = policy
        return copy
    }

    public func requesting(
        _ capability: CapabilityID,
        scope: JSONValue = .object([:]),
        required: Bool = false,
        reason: String
    ) -> Self {
        var copy = self
        copy.manifest.capabilities.append(
            CapabilityRequest(id: capability, scope: scope, required: required, reason: reason)
        )
        return copy
    }

    public func depending(
        on plugin: PluginID,
        versions: VersionRange = .any,
        required: Bool = true
    ) -> Self {
        var copy = self
        copy.manifest.dependencies.append(
            PluginDependency(id: plugin, versions: versions, required: required)
        )
        return copy
    }

    public func providing(
        _ service: ServiceID,
        version: SemanticVersion,
        summary: String? = nil
    ) -> Self {
        var copy = self
        copy.manifest.provides.append(
            ServiceDeclaration(id: service, version: version, summary: summary)
        )
        return copy
    }

    public func contributing(
        to point: ExtensionPointID,
        named name: String,
        contractVersion: SemanticVersion,
        priority: Int = 0,
        metadata: JSONValue = .object([:])
    ) -> Self {
        var copy = self
        copy.manifest.contributions.append(
            Contribution(
                extensionPoint: point,
                name: name,
                contractVersion: contractVersion,
                priority: priority,
                metadata: metadata
            )
        )
        return copy
    }

    /// Type-safe variant: the metadata is the host's own `Metadata` type, so a
    /// host renaming a field breaks the author's build instead of producing a
    /// manifest the host silently rejects at runtime.
    public func contributing<P: ExtensionPoint>(
        to point: P.Type,
        named name: String,
        priority: Int = 0,
        metadata: P.Metadata
    ) throws -> Self {
        var copy = self
        copy.manifest.contributions.append(
            try Contribution(
                extensionPoint: P.extensionPointID,
                name: name,
                contractVersion: P.contractVersion,
                priority: priority,
                encoding: metadata
            )
        )
        if !copy.manifest.contracts.contains(where: { $0.vocabulary == P.vocabulary }) {
            copy.manifest.contracts.append(
                ContractDependency(vocabulary: P.vocabulary, builtAgainst: P.contractVersion)
            )
        }
        return copy
    }

    public func configuration(_ schema: ConfigurationSchema) -> Self {
        var copy = self
        copy.manifest.configuration = schema
        return copy
    }

    public func build() -> PluginManifest { manifest }

    /// Builds and checks the invariants a host will check at discovery, so a bad
    /// manifest fails at the author's desk instead of on a user's machine.
    public func validated() throws -> PluginManifest {
        try manifest.validateStructure()
        return manifest
    }
}

// MARK: - Drift

/// A difference between what a manifest declares and what a plugin's code
/// actually does.
///
/// Manifest generation from code needs macro machinery; *detecting drift* needs
/// none. Activating a plugin in a harness, recording what it registers and
/// requests, and diffing against `plugin.json` gives the same guarantee today —
/// which is why the invariant does not have to wait for the tooling.
///
/// See `PluginHarness.driftReport()`.
public enum ManifestDrift: Hashable, Sendable, CustomStringConvertible {
    /// Declared in the manifest, never registered during activation. Dead weight
    /// at best; at worst a menu item that throws when clicked.
    case declaredButNotRegistered(point: ExtensionPointID, name: String)

    /// Registered during activation without being declared. The host **rejects**
    /// this at runtime rather than warning — a plugin must not be able to
    /// contribute past its own disclosure.
    case registeredButNotDeclared(point: ExtensionPointID, name: String)

    /// A capability the code asks for and the manifest does not declare. Also
    /// rejected at runtime, for the same reason.
    case capabilityUsedButNotDeclared(CapabilityID)

    /// Declared and never used. Harmless, but it inflates the permission list a
    /// user is asked to approve, which makes every other line in it less
    /// meaningful.
    case capabilityDeclaredButUnused(CapabilityID)

    /// A service the code publishes without declaring it.
    case serviceProvidedButNotDeclared(ServiceID)

    public var description: String {
        switch self {
        case .declaredButNotRegistered(let point, let name):
            return "declared but never registered: \(point)#\(name)"
        case .registeredButNotDeclared(let point, let name):
            return "registered but not declared: \(point)#\(name)"
        case .capabilityUsedButNotDeclared(let id):
            return "capability used, not declared: \(id)"
        case .capabilityDeclaredButUnused(let id):
            return "capability declared, never used: \(id)"
        case .serviceProvidedButNotDeclared(let id):
            return "service provided, not declared: \(id)"
        }
    }

    /// Whether this drift will actually break the plugin at runtime, as opposed
    /// to merely being untidy. Lets a build step fail on the first kind and warn
    /// on the second.
    public var isFatal: Bool {
        switch self {
        case .registeredButNotDeclared, .capabilityUsedButNotDeclared,
             .serviceProvidedButNotDeclared:
            return true
        case .declaredButNotRegistered, .capabilityDeclaredButUnused:
            return false
        }
    }
}
