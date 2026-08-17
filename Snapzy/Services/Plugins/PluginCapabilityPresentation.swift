import Foundation
import SnapzyPluginAPI

/// How a capability is shown to someone deciding whether to trust a plugin.
///
/// One mapping, one file: the friendly name, the symbol, and the generated
/// consent sentence all come from the capability id, so the Plugins tab and
/// the consent alerts can never disagree about what a permission means.
enum PluginCapabilityPresentation {
  struct Item: Identifiable {
    let id: String
    let name: String
    let systemImage: String
    let detail: String
    /// Sensitive and dangerous capabilities lead the list — a user scanning
    /// the sheet should hit "Internet" before "Image editing".
    let isSensitive: Bool
  }

  /// Friendly, translated name for a capability. Never shows the raw id.
  static func name(for capabilityID: String) -> String {
    switch capabilityID {
    case "snapzy.network": return L10n.PreferencesPlugins.capabilityNetwork
    case "snapzy.asset.read": return L10n.PreferencesPlugins.capabilityAssetRead
    case "snapzy.document.write": return L10n.PreferencesPlugins.capabilityDocumentWrite
    case "snapzy.clipboard.write": return L10n.PreferencesPlugins.capabilityClipboardWrite
    case "snapzy.secrets": return L10n.PreferencesPlugins.capabilitySecrets
    case "snapzy.ocr": return L10n.PreferencesPlugins.capabilityOCR
    case "snapzy.image": return L10n.PreferencesPlugins.capabilityImage
    case "snapzy.media": return L10n.PreferencesPlugins.capabilityMedia
    case "snapzy.ui": return L10n.PreferencesPlugins.capabilityUI
    case "snapzy.storage": return L10n.PreferencesPlugins.capabilityStorage
    case "snapzy.notify": return L10n.PreferencesPlugins.capabilityNotify
    default: return L10n.PreferencesPlugins.capabilityOther
    }
  }

  static func systemImage(for capabilityID: String) -> String {
    switch capabilityID {
    case "snapzy.network": return "globe"
    case "snapzy.asset.read": return "photo"
    case "snapzy.document.write": return "square.and.pencil"
    case "snapzy.clipboard.write": return "doc.on.clipboard"
    case "snapzy.secrets": return "key.fill"
    case "snapzy.ocr": return "text.viewfinder"
    case "snapzy.image": return "photo.on.rectangle"
    case "snapzy.media": return "film"
    case "snapzy.ui": return "questionmark.bubble"
    case "snapzy.storage": return "internaldrive"
    case "snapzy.notify": return "bell"
    default: return "checkmark.shield"
    }
  }

  /// Presentation items for a plugin's declared capabilities, sensitive first,
  /// each carrying the generated consent sentence as its detail line.
  static func items(for requests: [CapabilityRequest]) -> [Item] {
    requests
      .map { request -> Item in
        let sensitivity = PluginCapabilityRegistry.capabilityInfo(for: request.id)?.sensitivity ?? .sensitive
        return Item(
          id: request.id.rawValue,
          name: name(for: request.id.rawValue),
          systemImage: systemImage(for: request.id.rawValue),
          detail: PluginConsentPresenter.consentLine(
            for: request.id, scope: request.scope, sensitivity: sensitivity
          ),
          isSensitive: sensitivity != .benign
        )
      }
      .sorted { left, right in
        if left.isSensitive != right.isSensitive { return left.isSensitive }
        return left.name.localizedStandardCompare(right.name) == .orderedAscending
      }
  }

  /// The same treatment for a registry entry, which carries capability ids and
  /// scopes but no live `CapabilityRequest` values.
  static func items(for capabilities: [IndexCapability]) -> [Item] {
    capabilities
      .map { capability -> Item in
        let id = CapabilityID(rawValue: capability.id)
        let sensitivity = PluginCapabilityRegistry.capabilityInfo(for: id)?.sensitivity ?? .sensitive
        return Item(
          id: capability.id,
          name: name(for: capability.id),
          systemImage: systemImage(for: capability.id),
          detail: PluginConsentPresenter.consentLine(
            for: id, scope: scopeValue(from: capability.scope), sensitivity: sensitivity
          ),
          isSensitive: sensitivity != .benign
        )
      }
      .sorted { left, right in
        if left.isSensitive != right.isSensitive { return left.isSensitive }
        return left.name.localizedStandardCompare(right.name) == .orderedAscending
      }
  }

  /// Bridges the index's `[String: [String]]` scope shape to the `JSONValue`
  /// the consent copy is generated from.
  private static func scopeValue(from scope: [String: [String]]?) -> JSONValue {
    guard let scope else { return .object([:]) }
    return .object(scope.mapValues { .array($0.map { .string($0) }) })
  }
}
