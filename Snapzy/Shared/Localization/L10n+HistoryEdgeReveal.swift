import Foundation

extension L10n.PreferencesHistory {
  static let edgeRevealTitle = L10n.string(
    "preferences-history.edge-reveal-title",
    defaultValue: "Reveal at Top Edge",
    comment: "History settings toggle for revealing the traditional panel by hovering the top screen edge"
  )

  static let edgeRevealDescription = L10n.string(
    "preferences-history.edge-reveal-description",
    defaultValue: "Move the pointer to the topmost screen edge to slide the panel down. Move away to auto-hide.",
    comment: "History settings description for the top edge hover reveal"
  )
}
