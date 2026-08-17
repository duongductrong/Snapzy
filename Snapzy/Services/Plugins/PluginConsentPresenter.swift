import AppKit
import Foundation
import SnapzyPluginAPI

/// Consent for plugin capabilities.
///
/// Implements PluginKit's `ConsentStore`. The cadence is tier-driven:
///
/// - **official** — one consolidated prompt at install; decisions recorded
///   persistently by `recordInstallConsent`.
/// - **verified / community** — per-capability prompt on first use; the
///   generated copy names the data, never the API.
/// - **sideloaded** — per-capability prompt every session; nothing persists.
///
/// Consent copy is **derived from capability IDs and scopes**, never from
/// author-written manifest strings — a test forbids the latter from reaching
/// the sheet.
@PluginEngine
final class PluginConsentPresenter: ConsentStore {
  static let shared = PluginConsentPresenter()

  private let defaults = UserDefaults.standard
  private let storageKey = "Snapzy.pluginConsent"
  private var sessionCache: [String: ConsentDecision] = [:]
  private var persistentCache: [String: ConsentDecision] = [:]

  /// Whether a sheet is already up; overlapping prompts collapse.
  private var promptInFlight = false

  private init() {
    if let stored = defaults.dictionary(forKey: storageKey) as? [String: String] {
      persistentCache = stored.compactMapValues(ConsentDecision.init(rawValue:))
    }
  }

  // MARK: - ConsentStore

  func decision(for plugin: PluginID, capability: CapabilityID) async -> ConsentDecision? {
    if PluginTierStore.shared.tier(for: plugin.rawValue) == .sideloaded {
      return sessionCache[Self.key(plugin, capability)]
    }
    if let session = sessionCache[Self.key(plugin, capability)] {
      return session
    }
    return persistentCache[Self.key(plugin, capability)]
  }

  func requestConsent(_ prompt: ConsentPrompt) async -> ConsentDecision {
    if let existing = await decision(for: prompt.plugin.id, capability: prompt.capability) {
      return existing
    }

    let tier = PluginTierStore.shared.tier(for: prompt.plugin.id.rawValue)
    let decision = await Self.presentOnMain(prompt: prompt, tier: tier)
    await record(decision, for: prompt.plugin.id, capability: prompt.capability)
    return decision
  }

  func record(_ decision: ConsentDecision, for plugin: PluginID, capability: CapabilityID) async {
    let key = Self.key(plugin, capability)
    sessionCache[key] = decision
    guard PluginTierStore.shared.tier(for: plugin.rawValue) != .sideloaded else { return }
    if decision.isPersistent {
      persistentCache[key] = decision
      flush()
    }
  }

  func revoke(for plugin: PluginID, capability: CapabilityID?) async {
    if let capability {
      let key = Self.key(plugin, capability)
      sessionCache[key] = nil
      persistentCache[key] = nil
    } else {
      let prefix = "\(plugin.rawValue)|"
      for key in sessionCache.keys where key.hasPrefix(prefix) { sessionCache[key] = nil }
      for key in persistentCache.keys where key.hasPrefix(prefix) { persistentCache[key] = nil }
    }
    flush()
  }

  /// The consolidated install-time prompt for official/verified plugins:
  /// one sheet listing every declared capability with its generated copy.
  /// Records `allowAlways` for the whole set when the user approves.
  func recordInstallConsent(
    plugin: PluginIdentity,
    capabilities: [CapabilityRequest]
  ) async -> Bool {
    let copy = capabilities.compactMap { request -> String? in
      guard let capability = PluginCapabilityRegistry.capabilityInfo(for: request.id) else { return nil }
      guard capability.sensitivity != .benign else { return nil }
      return Self.consentLine(for: request.id, scope: request.scope, sensitivity: capability.sensitivity)
    }

    guard !copy.isEmpty else {
      // Nothing sensitive declared: nothing to ask.
      return true
    }

    let approved = await Self.presentInstallSheetOnMain(
      pluginName: plugin.displayName,
      pluginID: plugin.id,
      lines: copy
    )
    guard approved else { return false }

    for request in capabilities {
      if let info = PluginCapabilityRegistry.capabilityInfo(for: request.id), info.sensitivity == .benign {
        continue
      }
      await record(.allowAlways, for: plugin.id, capability: request.id)
    }
    return true
  }

  func clearSessionDecisions() {
    sessionCache.removeAll()
  }

  // MARK: - Generated copy

  /// Derives the consent sentence from the capability and its scope. The
  /// plugin's own `reason` string is deliberately unused here.
  nonisolated static func consentLine(
    for capability: CapabilityID,
    scope: JSONValue,
    sensitivity: CapabilitySensitivity
  ) -> String {
    switch capability.rawValue {
    case "snapzy.network":
      let hosts = Self.hostList(from: scope)
      return hosts.isEmpty
        ? L10n.PreferencesPlugins.consentNetworkGeneric
        : L10n.PreferencesPlugins.consentNetwork(hosts.joined(separator: ", "))
    case "snapzy.asset.read":
      let kinds = Self.kindList(from: scope).map(Self.documentKindName)
      return kinds.isEmpty
        ? L10n.PreferencesPlugins.consentAssetReadGeneric
        : L10n.PreferencesPlugins.consentAssetRead(kinds.joined(separator: ", "))
    case "snapzy.document.write":
      let ops = Self.opList(from: scope).map(Self.editOperationName)
      return ops.isEmpty
        ? L10n.PreferencesPlugins.consentDocumentWriteGeneric
        : L10n.PreferencesPlugins.consentDocumentWrite(ops.joined(separator: ", "))
    case "snapzy.clipboard.write":
      return L10n.PreferencesPlugins.consentClipboardWrite
    case "snapzy.secrets":
      return L10n.PreferencesPlugins.consentSecrets
    case "snapzy.ocr":
      return L10n.PreferencesPlugins.consentOCR
    case "snapzy.image":
      return L10n.PreferencesPlugins.consentImage
    case "snapzy.media":
      return L10n.PreferencesPlugins.consentMedia
    case "snapzy.ui":
      return L10n.PreferencesPlugins.consentUI
    case "snapzy.storage":
      return L10n.PreferencesPlugins.consentStorage
    case "snapzy.notify":
      return L10n.PreferencesPlugins.consentNotify
    default:
      return L10n.PreferencesPlugins.consentOther(capability.rawValue)
    }
  }

  /// Manifest scopes speak API (`annotateSession`); consent copy speaks
  /// English. Unknown tokens pass through raw so a newer manifest degrades to
  /// something accurate rather than to nothing.
  private nonisolated static func documentKindName(_ raw: String) -> String {
    switch raw {
    case "screenshot": return L10n.PreferencesPlugins.kindScreenshot
    case "video": return L10n.PreferencesPlugins.kindVideo
    case "gif": return L10n.PreferencesPlugins.kindGIF
    case "annotateSession": return L10n.PreferencesPlugins.kindAnnotateSession
    default: return raw
    }
  }

  private nonisolated static func editOperationName(_ raw: String) -> String {
    switch raw {
    case "addItem": return L10n.PreferencesPlugins.editAddItem
    case "updateItem": return L10n.PreferencesPlugins.editUpdateItem
    case "removeItem": return L10n.PreferencesPlugins.editRemoveItem
    case "setCrop": return L10n.PreferencesPlugins.editSetCrop
    default: return raw
    }
  }

  private nonisolated static func hostList(from scope: JSONValue) -> [String] {
    guard case .object(let object) = scope, case .array(let values)? = object["hosts"] else { return [] }
    return values.compactMap { if case .string(let host) = $0 { return host } else { return nil } }
  }

  private nonisolated static func kindList(from scope: JSONValue) -> [String] {
    guard case .object(let object) = scope, case .array(let values)? = object["kinds"] else { return [] }
    return values.compactMap { if case .string(let kind) = $0 { return kind } else { return nil } }
  }

  private nonisolated static func opList(from scope: JSONValue) -> [String] {
    guard case .object(let object) = scope, case .array(let values)? = object["ops"] else { return [] }
    return values.compactMap { if case .string(let op) = $0 { return op } else { return nil } }
  }

  // MARK: - Presentation

  private nonisolated static func presentOnMain(prompt: ConsentPrompt, tier: PluginTier) async -> ConsentDecision {
    await MainActor.run {
      let line = consentLine(
        for: prompt.capability, scope: prompt.scope, sensitivity: prompt.sensitivity
      )
      let tierNote: String
      switch tier {
      case .official, .verified:
        tierNote = ""
      case .community:
        tierNote = "\n\nThis plugin is unreviewed community software. Its sandbox is identical to every other plugin's — this prompt is about the data it can ask you to share."
      case .sideloaded:
        tierNote = "\n\nDevelopment plugin. You will be asked again next session."
      }

      let alert = NSAlert()
      alert.messageText = "Allow “\(prompt.plugin.displayName)”?"
      alert.informativeText = "“\(prompt.plugin.displayName)” \(line).\(tierNote)"
      alert.alertStyle = prompt.sensitivity == .dangerous ? .critical : .warning
      let always = alert.addButton(withTitle: "Always Allow")
      let once = alert.addButton(withTitle: "Allow Once")
      let deny = alert.addButton(withTitle: "Deny")
      always.keyEquivalent = ""
      once.keyEquivalent = "\r"
      deny.keyEquivalent = "\u{1b}"

      let response = alert.runModal()
      switch response {
      case .alertFirstButtonReturn: return .allowAlways
      case .alertSecondButtonReturn: return .allowOnce
      default: return .denyOnce
      }
    }
  }

  private nonisolated static func presentInstallSheetOnMain(
    pluginName: String, pluginID: PluginID, lines: [String]
  ) async -> Bool {
    await MainActor.run {
      let alert = NSAlert()
      alert.messageText = "Install “\(pluginName)”?"
      alert.informativeText = "Before installing, \(pluginName) wants these permissions:\n\n• \(lines.joined(separator: "\n• "))\n\nEvery plugin runs in the same sandbox with the same protections — official, verified, or community."
      alert.alertStyle = .warning
      alert.addButton(withTitle: "Install")
      alert.addButton(withTitle: "Cancel")
      return alert.runModal() == .alertFirstButtonReturn
    }
  }

  // MARK: - Persistence

  private func flush() {
    defaults.set(persistentCache.mapValues(\.rawValue), forKey: storageKey)
  }

  private static func key(_ plugin: PluginID, _ capability: CapabilityID) -> String {
    "\(plugin.rawValue)|\(capability.rawValue)"
  }
}

/// Registry of capability metadata (id → sensitivity), shared by the consent
/// presenter and the broker. Built by `SnapzyHostConfiguration`.
enum PluginCapabilityRegistry {
  struct CapabilityInfo: Sendable {
    let id: CapabilityID
    let sensitivity: CapabilitySensitivity
  }

  private static let infos: [CapabilityInfo] = [
    .init(id: SnapzyNetworkAccess.capabilityID, sensitivity: SnapzyNetworkAccess.sensitivity),
    .init(id: SnapzyAssetRead.capabilityID, sensitivity: SnapzyAssetRead.sensitivity),
    .init(id: SnapzyDocumentWrite.capabilityID, sensitivity: SnapzyDocumentWrite.sensitivity),
    .init(id: SnapzyClipboardWrite.capabilityID, sensitivity: SnapzyClipboardWrite.sensitivity),
    .init(id: SnapzySecretsAccess.capabilityID, sensitivity: SnapzySecretsAccess.sensitivity),
    .init(id: SnapzyOCR.capabilityID, sensitivity: SnapzyOCR.sensitivity),
    .init(id: SnapzyImage.capabilityID, sensitivity: SnapzyImage.sensitivity),
    .init(id: SnapzyMedia.capabilityID, sensitivity: SnapzyMedia.sensitivity),
    .init(id: SnapzyNotify.capabilityID, sensitivity: SnapzyNotify.sensitivity),
    .init(id: SnapzyUI.capabilityID, sensitivity: SnapzyUI.sensitivity),
    .init(id: SnapzyStorage.capabilityID, sensitivity: SnapzyStorage.sensitivity),
  ]

  static func capabilityInfo(for id: CapabilityID) -> CapabilityInfo? {
    infos.first { $0.id == id }
  }

  static var all: [CapabilityInfo] { infos }
}
