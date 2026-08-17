import Foundation
import SnapzyPluginAPI

/// Plugin filesystem locations, and the path-traversal guard every path a
/// plugin can influence must pass before touching the filesystem.
enum PluginDirectory {
  /// `~/Library/Application Support/Snapzy/Plugins` — where installed
  /// plugins live (PluginKit's own layout convention).
  static var userPluginsDirectory: URL {
    PluginBundleLayout.userPluginsDirectory(appName: appSupportName)
  }

  /// `~/Library/Application Support/Snapzy/PluginData` — per-plugin
  /// containers, settings, and tier records.
  static var pluginDataDirectory: URL {
    PluginBundleLayout.pluginDataDirectory(appName: appSupportName)
  }

  /// Where "Load Plugin from Folder…" stages its copies.
  ///
  /// A sibling of the installed plugins rather than a subdirectory of them:
  /// `DirectoryPluginSource` scans exactly one level and only for `.plugin`
  /// bundles, so anything nested inside `Plugins/` is invisible to discovery.
  /// This directory gets its own source in ``SnapzyHostConfiguration``, which
  /// is also what keeps the `development` trust hint attached to it.
  static var developmentPluginsDirectory: URL {
    pluginDataDirectory.appendingPathComponent("Development", isDirectory: true)
  }

  /// The on-disk cache for the registry index.
  static var registryCacheURL: URL {
    pluginDataDirectory.appendingPathComponent("registry-index.json", isDirectory: false)
  }

  /// Plugin IDs are used as directory names. Anything but a reverse-DNS-ish
  /// identifier is refused before it can touch the filesystem.
  static func isValidPluginID(_ id: String) -> Bool {
    guard !id.isEmpty, id.count <= 128 else { return false }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
    return id.unicodeScalars.allSatisfy { allowed.contains($0) }
      && !id.hasPrefix(".")
      && !id.contains("..")
  }

  /// Resolves a plugin id to a directory under `root`, refusing traversal.
  static func pluginDirectory(id: String, in root: URL) -> URL? {
    guard isValidPluginID(id) else { return nil }
    return root.appendingPathComponent(id, isDirectory: true)
  }

  /// The on-disk location of an installed plugin bundle: `<id>.plugin`
  /// (PluginKit's bundle extension convention for discovery).
  static func installedPluginDirectory(id: String) -> URL? {
    guard isValidPluginID(id) else { return nil }
    return userPluginsDirectory.appendingPathComponent("\(id).plugin", isDirectory: true)
  }

  private static var appSupportName: String { "Snapzy" }
}

/// Which tier a plugin was installed from. Affects consent cadence and UI
/// labelling only — containment is identical for every tier.
enum PluginTier: String, Codable, Sendable {
  case official
  case verified
  case community
  case sideloaded

  /// Who published it, in words that mean something to someone who has not
  /// read the trust-tier documentation.
  var label: String {
    switch self {
    case .official: return L10n.PreferencesPlugins.tierOfficial
    case .verified: return L10n.PreferencesPlugins.tierVerified
    case .community: return L10n.PreferencesPlugins.tierCommunity
    case .sideloaded: return L10n.PreferencesPlugins.tierDevelopment
    }
  }
}

/// Persists trust tiers per plugin ID. Tier is decided by the installer /
/// registry, never by the plugin itself.
@PluginEngine
final class PluginTierStore {
  static let shared = PluginTierStore()

  private let fileURL: URL = PluginDirectory.pluginDataDirectory.appendingPathComponent("tiers.json")
  private var tiers: [String: PluginTier] = [:]
  private var loaded = false

  private func ensureLoaded() {
    guard !loaded else { return }
    defer { loaded = true }
    guard let data = try? Data(contentsOf: fileURL) else { return }
    tiers = (try? JSONDecoder().decode([String: PluginTier].self, from: data)) ?? [:]
  }

  func tier(for pluginID: String) -> PluginTier {
    ensureLoaded()
    return tiers[pluginID] ?? .community
  }

  func setTier(_ tier: PluginTier, for pluginID: String) {
    ensureLoaded()
    tiers[pluginID] = tier
    persist()
  }

  func remove(pluginID: String) {
    ensureLoaded()
    tiers[pluginID] = nil
    persist()
  }

  private func persist() {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      try encoder.encode(tiers).write(to: fileURL, options: .atomic)
    } catch {
      DiagnosticLogger.shared.log(.warning, .plugin, "Could not persist plugin tiers: \(error)")
    }
  }
}
