import Foundation

/// Where things live inside a plugin bundle, and where bundles live on disk.
///
/// Centralised because three separate parties have to agree: the host's
/// discovery code, the author's build step, and the CLI. A layout constant
/// duplicated across those three is a layout constant that will disagree.
public enum PluginBundleLayout {
    /// The manifest filename.
    public static let manifestName = "plugin.json"

    /// Bundle extensions treated as plugins. `.plugin` is preferred; `.bundle`
    /// is accepted because that is what a plain SwiftPM or Xcode bundle target
    /// produces without extra configuration, and rejecting it would make the
    /// first five minutes of plugin authoring needlessly annoying.
    public static let bundleExtensions: Set<String> = ["plugin", "bundle"]

    /// Where a manifest may be found inside a bundle, in search order.
    ///
    /// `Contents/Resources` is correct for a real macOS bundle. The root is
    /// checked too so that a directory an author assembled by hand — or a test
    /// fixture — works without ceremony.
    public static let manifestSearchPaths = [
        "Contents/Resources/\(manifestName)",
        "Resources/\(manifestName)",
        manifestName,
    ]

    /// Resolves the manifest inside a bundle directory, or `nil` if absent.
    public static func manifestURL(inBundleAt bundleURL: URL) -> URL? {
        for relativePath in manifestSearchPaths {
            let candidate = bundleURL.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Whether a URL looks like a plugin bundle.
    public static func looksLikePluginBundle(_ url: URL) -> Bool {
        bundleExtensions.contains(url.pathExtension.lowercased())
    }

    /// The per-user plugin directory for an app.
    ///
    /// `~/Library/Application Support/<appName>/Plugins`.
    public static func userPluginsDirectory(appName: String) -> URL {
        applicationSupport(appName: appName).appendingPathComponent("Plugins", isDirectory: true)
    }

    /// The machine-wide plugin directory, for IT-deployed plugins.
    ///
    /// `/Library/Application Support/<appName>/Plugins`.
    public static func machinePluginsDirectory(appName: String) -> URL {
        URL(fileURLWithPath: "/Library/Application Support", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)
    }

    /// Where per-plugin containers live.
    ///
    /// `~/Library/Application Support/<appName>/PluginData`.
    public static func pluginDataDirectory(appName: String) -> URL {
        applicationSupport(appName: appName).appendingPathComponent("PluginData", isDirectory: true)
    }

    /// Where a host writes its emitted vocabulary catalog inside its own bundle.
    public static let catalogResourcePath = "Contents/Resources/PluginAPI"

    private static func applicationSupport(appName: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent(appName, isDirectory: true)
    }
}
