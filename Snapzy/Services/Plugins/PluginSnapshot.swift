import Foundation
import PluginKitHost
import SnapzyPluginAPI

/// The UI-facing projection of a `PluginRecord` — everything the plugin list,
/// detail view, and command menus render, with reasons alongside state.
struct PluginSnapshot: Identifiable, Equatable {
  let id: String
  let version: String
  let displayName: String
  let summary: String?
  let phase: String
  let tier: PluginTier
  let trust: String
  /// A readable problem sentence: why a plugin is unsatisfied, failed, or
  /// needs a newer Snapzy. Empty when everything is fine.
  let problem: String
  /// Non-fatal conditions worth surfacing.
  let warnings: [String]
  let declaredCapabilities: [CapabilityRequest]
  let contributions: [PluginCommandItem]
  let failureCount: Int
  /// Whether the user explicitly disabled this plugin.
  let userEnabled: Bool?
  /// The on-disk location, for development plugins.
  let locationPath: String?

  var isAvailable: Bool {
    ["resolved", "loading", "active", "inactive"].contains(phase)
  }

  var status: PluginStatusKind {
    if phase == "quarantined" { return .quarantined }
    if let userEnabled, !userEnabled { return .disabled }
    if phase == "rejected" { return .invalid }
    if !problem.isEmpty { return .needsSetup }
    if tier == .sideloaded { return .development }
    if phase == "failed" { return .invalid }
    return .configured
  }
}

/// The status pill taxonomy — one mapping, one file.
enum PluginStatusKind {
  case configured
  case needsSetup
  case disabled
  case invalid
  case requiresNewerSnapzy
  case development
  case quarantined

  /// Plain-language status, written for someone who has never heard the word
  /// "quarantine" — the technical phase name stays on `PluginSnapshot.phase`.
  var label: String {
    switch self {
    case .configured: return L10n.PreferencesPlugins.statusReady
    case .needsSetup: return L10n.PreferencesPlugins.statusNeedsSetup
    case .disabled: return L10n.PreferencesPlugins.statusOff
    case .invalid: return L10n.PreferencesPlugins.statusNotWorking
    case .requiresNewerSnapzy: return L10n.PreferencesPlugins.statusNeedsUpdate
    case .development: return L10n.PreferencesPlugins.statusDeveloper
    case .quarantined: return L10n.PreferencesPlugins.statusBlocked
    }
  }

  /// Shape as well as colour, so the status survives colour blindness and
  /// greyscale screenshots.
  var systemImage: String {
    switch self {
    case .configured: return "checkmark.circle.fill"
    case .needsSetup: return "exclamationmark.circle.fill"
    case .disabled: return "pause.circle.fill"
    case .invalid: return "xmark.circle.fill"
    case .requiresNewerSnapzy: return "arrow.up.circle.fill"
    case .development: return "hammer.circle.fill"
    case .quarantined: return "hand.raised.circle.fill"
    }
  }

  /// Whether this status is worth pulling the user's eye to. Everything else
  /// renders quietly, so a healthy list reads as calm.
  var needsAttention: Bool {
    switch self {
    case .needsSetup, .invalid, .requiresNewerSnapzy, .quarantined: return true
    case .configured, .disabled, .development: return false
    }
  }
}

/// A command contribution, decoded and filterable without loading any code.
struct PluginCommandItem: Identifiable, Equatable, Sendable {
  let id: String
  let pluginID: String
  let pluginName: String
  let name: String
  let title: String
  let systemImage: String
  let accepts: [SnapzyDocumentKind]
  let emits: [DocumentEditKind]
  let isLongRunning: Bool
  /// Why this command is not runnable right now, if anything.
  let disabledReason: String?
  /// The handle to resolve when the user invokes it. Not equatable — carries
  /// the resolver closure.
  let handle: any ExtensionHandleBox

  static func == (lhs: PluginCommandItem, rhs: PluginCommandItem) -> Bool {
    lhs.id == rhs.id && lhs.pluginID == rhs.pluginID
      && lhs.disabledReason == rhs.disabledReason && lhs.title == rhs.title
  }
}

/// Type-erased wrapper so `PluginCommandItem` can carry a generic
/// `ExtensionHandle<SnapzyCommandPoint>` without the catalog going generic.
protocol ExtensionHandleBox: Sendable {
  func resolve() async throws -> any SnapzyCommand
  var metadataEmitted: [DocumentEditKind] { get }
}

struct SnapzyCommandHandleBox: ExtensionHandleBox {
  let handle: ExtensionHandle<SnapzyCommandPoint>
  let emitted: [DocumentEditKind]

  var metadataEmitted: [DocumentEditKind] { emitted }

  func resolve() async throws -> any SnapzyCommand {
    try await handle.resolve()
  }
}
