import AppKit
import Foundation
import SnapzyPluginAPI

/// Install / update / remove for indexed plugins.
///
/// Install: download → verify → stage → atomic replace → re-discover →
/// consolidated consent. Update: keep-until-verified swap; settings, secrets,
/// and storage survive; **re-consent on any capability widening**. Remove:
/// bundle + settings + container + Keychain + recorded consent.
@PluginEngine
final class PluginInstaller {
  static let shared = PluginInstaller()

  enum InstallError: Error, CustomStringConvertible {
    case cancelled
    case verification(String)
    case compatibility([String])
    case network(String)
    case consentDenied
    case internalError(String)

    var description: String {
      switch self {
      case .cancelled: return "The install was cancelled."
      case .verification(let reason): return reason
      case .compatibility(let issues): return issues.joined(separator: " ")
      case .network(let reason): return reason
      case .consentDenied: return "You declined the plugin's permissions."
      case .internalError(let reason): return reason
      }
    }
  }

  /// Installs an index entry. Consent comes *after* verification and staging,
  /// and before anything becomes runnable.
  func install(entry: PluginIndexEntry) async throws {
    let issues = PluginPackageVerifier.compatibilityIssues(
      entry: entry, appVersion: Self.appVersion
    )
    guard issues.isEmpty else {
      throw InstallError.compatibility(issues)
    }

    // Download.
    guard let bundleURL = URL(string: entry.bundleURL) else {
      throw InstallError.network("The bundle URL is invalid.")
    }
    let zipData: Data
    do {
      var request = URLRequest(url: bundleURL)
      request.timeoutInterval = 120
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw InstallError.network("The bundle download failed.")
      }
      zipData = data
    } catch let error as InstallError {
      throw error
    } catch {
      throw InstallError.network(error.localizedDescription)
    }

    // Verify + extract into staging.
    let stagingRoot = PluginDirectory.pluginDataDirectory
      .appendingPathComponent("Staging", isDirectory: true)
    let extracted: URL
    do {
      extracted = try PluginPackageVerifier().verifyAndExtract(
        zipData: zipData, entry: entry, into: stagingRoot
      )
    } catch {
      throw InstallError.verification("\(error)")
    }
    defer { try? FileManager.default.removeItem(at: extracted.deletingLastPathComponent()) }

    // Capability-widening check against the previous install.
    let previous = Self.previousCapabilityIDs(for: entry.id)
    let requested = Set(entry.capabilities.map(\.id))
    let widened = requested.subtracting(previous)
    if !widened.isEmpty {
      // An update that adds capabilities must re-consent before it can run.
      let approved = await Self.consentForWidened(
        pluginName: entry.displayName,
        widened: widened.sorted()
      )
      guard approved else { throw InstallError.consentDenied }
    }

    // Atomic replace into the plugins directory.
    guard let finalFolder = PluginDirectory.installedPluginDirectory(id: entry.id) else {
      throw InstallError.verification("The plugin id is not a valid identifier.")
    }
    let parent = finalFolder.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let temporary = parent.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.copyItem(at: extracted, to: temporary)
    if FileManager.default.fileExists(atPath: finalFolder.path) {
      _ = try FileManager.default.replaceItemAt(
        finalFolder, withItemAt: temporary, backupItemName: nil, options: []
      )
    } else {
      try FileManager.default.moveItem(at: temporary, to: finalFolder)
    }

    // Consolidated consent (official/verified) — recorded before discovery so
    // the first invocation never double-prompts.
    let manifest = try PluginManifest.load(from: PluginBundleLayout.manifestURL(inBundleAt: finalFolder)!)
    let tier: PluginTier = switch entry.tier {
    case "official": .official
    case "verified": .verified
    default: .community
    }
    let approved = await PluginConsentPresenter.shared.recordInstallConsent(
      plugin: manifest.identity,
      capabilities: manifest.capabilities
    )
    guard approved else {
      try? FileManager.default.removeItem(at: finalFolder)
      throw InstallError.consentDenied
    }
    PluginTierStore.shared.setTier(tier, for: entry.id)

    await PluginHostController.shared.restart()
  }

  /// Capability ids recorded for the currently-installed build, used to
  /// detect widening updates.
  static func previousCapabilityIDs(for pluginID: String) -> Set<String> {
    guard let directory = PluginDirectory.installedPluginDirectory(id: pluginID),
      let manifestURL = PluginBundleLayout.manifestURL(inBundleAt: directory),
      let manifest = try? PluginManifest.load(from: manifestURL)
    else {
      return []
    }
    return Set(manifest.capabilities.map(\.id.rawValue))
  }

  private static func consentForWidened(pluginName: String, widened: [String]) async -> Bool {
    await MainActor.run {
      let alert = NSAlert()
      alert.messageText = "“\(pluginName)” wants new permissions"
      alert.informativeText = "This update asks for capabilities you have not granted before:\n\n• \(widened.joined(separator: "\n• "))\n\nReview them before updating."
      alert.alertStyle = .warning
      alert.addButton(withTitle: "Allow and Update")
      alert.addButton(withTitle: "Cancel")
      return alert.runModal() == .alertFirstButtonReturn
    }
  }

  private static var appVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
  }
}

/// `revoked: true` on the next index fetch disables installed copies — the
/// only kill switch, and the plan ships it in v1.
@MainActor
enum PluginRevocationEnforcer {
  static func enforce(_ index: PluginRegistryIndex, controller: PluginHostController = .shared) async {
    let revoked = index.plugins.filter(\.revoked)
    for entry in revoked {
      let snapshot = controller.snapshots.first { $0.id == entry.id }
      guard let snapshot, snapshot.isAvailable else { continue }
      await controller.setEnabled(entry.id, false)
      let reason = entry.revokedReason ?? "No reason was published."
      DiagnosticLogger.shared.log(.warning, .plugin, "Plugin “\(entry.id)” was revoked: \(reason)")
      await MainActor.run {
        AppToastManager.shared.show(
          message: "“\(entry.displayName)” was disabled: it has been revoked by its publisher.",
          style: .warning,
          duration: 8
        )
      }
    }
  }
}

/// Version badges for the Browse list: "Update available" computed from the
/// index without downloading anything in the background.
enum PluginUpdateChecker {
  static func updatesAvailable(
    index: PluginRegistryIndex?,
    installed: [PluginSnapshot]
  ) -> [PluginIndexEntry] {
    guard let index else { return [] }
    let installedVersions = Dictionary(
      installed.map { ($0.id, $0.version) },
      uniquingKeysWith: { first, _ in first }
    )
    return index.plugins.filter { entry in
      guard !entry.revoked, let version = installedVersions[entry.id] else { return false }
      return Self.compare(entry.version, version) > 0
    }
  }

  /// Whether `candidate` is a newer version than `installed`.
  static func isUpdate(_ candidate: String, newerThan installed: String) -> Bool {
    compare(candidate, installed) > 0
  }

  private static func compare(_ lhs: String, _ rhs: String) -> Int {
    let left = lhs.split(separator: ".").compactMap { Int($0) }
    let right = rhs.split(separator: ".").compactMap { Int($0) }
    for index in 0..<max(left.count, right.count) {
      let l = index < left.count ? left[index] : 0
      let r = index < right.count ? right[index] : 0
      if l != r { return l < r ? -1 : 1 }
    }
    return 0
  }
}
