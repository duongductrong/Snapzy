import Foundation
@_exported import PluginKitCore

/// The `NSPrincipalClass` base for a plugin shipped as a loadable bundle.
///
/// macOS bundle loading resolves an entry point through `Bundle.principalClass`,
/// which must be an Objective-C class. This is that class, so an author writes an
/// override instead of hand-managing exported symbols:
///
/// ```swift
/// // Info.plist: NSPrincipalClass = WordCountEntry
/// @objc(WordCountEntry)
/// final class WordCountEntry: PluginPrincipal {
///     override class func makePlugin() -> any Plugin { WordCountPlugin() }
///
///     override class func contractVersions() -> [String: String] {
///         ["com.acme.editor.api": "1.0.0"]
///     }
/// }
/// ```
///
/// ``contractVersions()`` is a plain `[String: String]` rather than a typed pair
/// because it is an *override point for an author*, and an override should be the
/// least ceremonious thing in the file. The framework parses it into
/// ``PluginEntryPoint/declaredContracts``, which is what the host actually reads.
open class PluginPrincipal: NSObject, PluginEntryPoint {
    public required override init() { super.init() }

    /// Override to return your plugin.
    open class func makePlugin() -> any Plugin {
        preconditionFailure(
            "\(self) must override makePlugin() to return its Plugin instance."
        )
    }

    /// Override to declare linked contract versions, as
    /// `["vocabulary.id": "1.2.3"]`.
    open class func contractVersions() -> [String: String] { [:] }

    public static var declaredContracts: [ContractDependency] {
        contractVersions().compactMap { vocabulary, version in
            guard let parsed = SemanticVersion(string: version) else { return nil }
            return ContractDependency(vocabulary: VocabularyID(vocabulary), builtAgainst: parsed)
        }
    }
}

/// `Info.plist` keys a plugin bundle uses.
public enum PluginBundleKeys {
    /// Names the ``PluginPrincipal`` subclass to instantiate.
    public static let principalClass = "NSPrincipalClass"
    /// Optional override of where the manifest lives inside the bundle.
    public static let manifestPath = "PluginKitManifestPath"
}
