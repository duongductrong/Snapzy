import Foundation
import PluginKitCore

/// A place plugins are found.
///
/// A protocol rather than a fixed set of directories, and that is the main reason
/// PluginKit can be adopted incrementally: a host with an existing plugin system
/// writes one `PluginSource` and one ``PluginRuntime`` and its old plugins appear
/// in the new registry alongside the new ones, with no flag day.
public protocol PluginSource: Sendable {
    var sourceID: SourceID { get }

    /// How much this location is trusted a priori. A directory the user can drop
    /// files into is not the app's own `PlugIns` folder, and the trust policy
    /// needs to know which is which before it looks at a signature.
    var trustHint: TrustHint { get }

    func discover() async throws -> [DiscoveredPlugin]

    /// Live changes. Defaults to a stream that finishes immediately, so a static
    /// source is three lines and adding change support later breaks nobody.
    func changes() -> AsyncStream<PluginSourceChange>
}

extension PluginSource {
    public func changes() -> AsyncStream<PluginSourceChange> {
        AsyncStream { $0.finish() }
    }
}

/// What a source found, before any validation.
public struct DiscoveredPlugin: Sendable {
    public let manifest: PluginManifest
    public let location: PluginLocation
    public let source: SourceID
    public let trustHint: TrustHint

    public init(
        manifest: PluginManifest,
        location: PluginLocation,
        source: SourceID,
        trustHint: TrustHint
    ) {
        self.manifest = manifest
        self.location = location
        self.source = source
        self.trustHint = trustHint
    }

    public var id: PluginID { manifest.id }
}

/// Where a plugin's code actually is.
public enum PluginLocation: Hashable, Sendable {
    /// A loadable bundle on disk.
    case bundle(URL)
    /// Compiled into the host, supplied by a factory the host registered.
    ///
    /// Not a testing affordance — this is how first-party plugins ship. They get
    /// the same lifecycle, capability brokering, and manifest authority as
    /// third-party ones, which is what stops "first-party" from becoming a
    /// synonym for "unaudited".
    case registered
}

/// How much a *location* implies about trust, before signatures are examined.
public enum TrustHint: String, Hashable, Sendable, Codable {
    /// Inside the host's own bundle, or compiled into it.
    case firstParty
    /// Dropped in by the user.
    case userInstalled
    /// Deployed by an administrator.
    case managed
    /// A development location. Never a production trust input.
    case development
}

/// A live change from a source.
public enum PluginSourceChange: Sendable {
    case added(DiscoveredPlugin)
    case removed(PluginID)
    /// Same identity, new build on disk. Handled as an upgrade, not as a
    /// stranger, so configuration survives.
    case modified(DiscoveredPlugin)
}

// MARK: - Built-in sources

/// Plugins compiled into the host.
///
/// The host supplies a factory per plugin alongside its manifest, so nothing is
/// read from disk and nothing is dynamically loaded — but everything else about
/// the lifecycle is identical.
public struct RegisteredPluginSource: PluginSource {
    public let sourceID: SourceID
    public let trustHint: TrustHint
    private let manifests: [PluginManifest]

    public init(
        sourceID: SourceID = .registered,
        trustHint: TrustHint = .firstParty,
        manifests: [PluginManifest]
    ) {
        self.sourceID = sourceID
        self.trustHint = trustHint
        self.manifests = manifests
    }

    public func discover() async throws -> [DiscoveredPlugin] {
        manifests.map {
            DiscoveredPlugin(
                manifest: $0,
                location: .registered,
                source: sourceID,
                trustHint: trustHint
            )
        }
    }
}

/// Plugin bundles in a directory.
///
/// Used for all three of the user, machine-wide, and app-bundle locations — they
/// differ only in path and trust hint, and giving them three types would be three
/// places for the scanning logic to drift.
public struct DirectoryPluginSource: PluginSource {
    public let sourceID: SourceID
    public let trustHint: TrustHint
    public let directory: URL
    /// Whether a missing directory is an error.
    ///
    /// It is not: a user plugins folder that has never been created is the normal
    /// state of a fresh install, and treating it as a failure would make every
    /// first launch log an error.
    public let toleratesMissingDirectory: Bool

    public init(
        sourceID: SourceID,
        trustHint: TrustHint,
        directory: URL,
        toleratesMissingDirectory: Bool = true
    ) {
        self.sourceID = sourceID
        self.trustHint = trustHint
        self.directory = directory
        self.toleratesMissingDirectory = toleratesMissingDirectory
    }

    /// `~/Library/Application Support/<appName>/Plugins`.
    public static func user(appName: String) -> DirectoryPluginSource {
        DirectoryPluginSource(
            sourceID: .user,
            trustHint: .userInstalled,
            directory: PluginBundleLayout.userPluginsDirectory(appName: appName)
        )
    }

    /// `/Library/Application Support/<appName>/Plugins`.
    public static func machine(appName: String) -> DirectoryPluginSource {
        DirectoryPluginSource(
            sourceID: .machine,
            trustHint: .managed,
            directory: PluginBundleLayout.machinePluginsDirectory(appName: appName)
        )
    }

    /// The host app's own `Contents/PlugIns`.
    public static func builtIn(bundle: Bundle = .main) -> DirectoryPluginSource? {
        guard let url = bundle.builtInPlugInsURL else { return nil }
        return DirectoryPluginSource(sourceID: .builtIn, trustHint: .firstParty, directory: url)
    }

    /// A location named by `$PLUGINKIT_DEV_PATH`, for the authoring loop.
    ///
    /// Returns `nil` when unset, so leaving the call in a shipping build costs
    /// nothing and a developer does not have to maintain a private branch to get
    /// a fast iteration cycle.
    public static func development(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> DirectoryPluginSource? {
        guard let path = environment["PLUGINKIT_DEV_PATH"], !path.isEmpty else { return nil }
        return DirectoryPluginSource(
            sourceID: .development,
            trustHint: .development,
            directory: URL(fileURLWithPath: path, isDirectory: true)
        )
    }

    public func discover() async throws -> [DiscoveredPlugin] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else {
            if toleratesMissingDirectory { return [] }
            throw PluginManifestError.fileNotFound(directory)
        }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                // Symlinks are followed, which is what makes a symlinked
                // development plugin work without copying on every build.
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw PluginManifestError.unreadable(reason: error.localizedDescription)
        }

        var discovered: [DiscoveredPlugin] = []
        for url in contents.sorted(by: { $0.path < $1.path })
        where PluginBundleLayout.looksLikePluginBundle(url) {
            guard let manifestURL = PluginBundleLayout.manifestURL(inBundleAt: url) else { continue }
            // One unreadable bundle must not hide the rest. The manager reports
            // it; the other nineteen plugins still load.
            guard let manifest = try? PluginManifest.load(from: manifestURL) else { continue }
            discovered.append(
                DiscoveredPlugin(
                    manifest: manifest,
                    location: .bundle(url),
                    source: sourceID,
                    trustHint: trustHint
                )
            )
        }
        return discovered
    }
}
