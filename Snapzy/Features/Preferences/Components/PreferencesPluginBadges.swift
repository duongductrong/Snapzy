import SwiftUI

/// Plugin status as a pill. Colour carries the same meaning as
/// `PluginStatusKind.needsAttention`: calm statuses stay quiet, the ones that
/// need a decision get the loud tint.
struct PluginStatusBadge: View {
  let status: PluginStatusKind

  var body: some View {
    StatusBadge(
      label: status.label,
      systemImage: status.systemImage,
      tint: tint
    )
  }

  private var tint: Color {
    switch status {
    case .configured: return .green
    case .needsSetup: return .orange
    case .disabled: return .secondary
    case .invalid: return .red
    case .requiresNewerSnapzy: return .orange
    case .development: return .purple
    case .quarantined: return .red
    }
  }
}

/// Which tier a plugin came from. Informational only — the status badge is
/// the one that asks for attention.
struct PluginTierBadge: View {
  let tier: PluginTier

  var body: some View {
    StatusBadge(label: tier.label, tint: tint)
  }

  private var tint: Color {
    switch tier {
    case .official: return .accentColor
    case .verified: return .blue
    case .community: return .secondary
    case .sideloaded: return .purple
    }
  }
}
