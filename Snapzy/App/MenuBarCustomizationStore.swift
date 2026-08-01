//
//  MenuBarCustomizationStore.swift
//  Snapzy
//
//  UserDefaults-backed menu bar item order, visibility, and icon style.
//

import Combine
import Foundation

@MainActor
final class MenuBarCustomizationStore: ObservableObject {
  static let shared = MenuBarCustomizationStore()

  /// Flat order of all customizable items. Only relative order within each
  /// group is meaningful; rendering filters per group.
  @Published private(set) var itemOrder: [MenuBarItemKind]
  @Published private(set) var hiddenItems: Set<MenuBarItemKind>
  @Published private(set) var iconStyle: MenuBarIconStyle

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    itemOrder = Self.normalizedOrder(from: defaults.stringArray(forKey: PreferencesKeys.menuBarItemOrder))
    hiddenItems = Self.normalizedHiddenItems(from: defaults.stringArray(forKey: PreferencesKeys.menuBarHiddenItems))
    iconStyle = Self.normalizedIconStyle(from: defaults.string(forKey: PreferencesKeys.menuBarIconStyle))
  }

  // MARK: - Queries

  /// Visible items for a group in the user's configured order.
  func orderedVisibleItems(for group: MenuBarItemGroup) -> [MenuBarItemKind] {
    orderedItems(for: group).filter { !hiddenItems.contains($0) }
  }

  /// All items for a group (visible and hidden) in the user's configured order.
  func orderedItems(for group: MenuBarItemGroup) -> [MenuBarItemKind] {
    itemOrder.filter { $0.group == group }
  }

  func isHidden(_ item: MenuBarItemKind) -> Bool {
    hiddenItems.contains(item)
  }

  // MARK: - Mutations

  func setHidden(_ item: MenuBarItemKind, hidden: Bool) {
    guard item.isCustomizable || item.isHideableOnly else { return }
    var updated = hiddenItems
    if hidden {
      updated.insert(item)
    } else {
      updated.remove(item)
    }
    hiddenItems = updated
    save()
  }

  /// Reorder within a group. Indices address the group's full item list
  /// (visible + hidden), matching the settings UI rows.
  func moveItem(from source: IndexSet, to destination: Int, in group: MenuBarItemGroup) {
    guard !source.isEmpty else { return }

    var groupItems = orderedItems(for: group)
    let moving = source.sorted().map { groupItems[$0] }
    for index in source.sorted(by: >) {
      groupItems.remove(at: index)
    }

    let removedBeforeDestination = source.filter { $0 < destination }.count
    let insertionIndex = max(0, min(destination - removedBeforeDestination, groupItems.count))
    groupItems.insert(contentsOf: moving, at: insertionIndex)

    // Rebuild the flat order, replacing this group's subsequence in place and
    // leaving other groups untouched.
    var updated: [MenuBarItemKind] = []
    var groupIterator = groupItems.makeIterator()
    for item in itemOrder {
      if item.group == group, let next = groupIterator.next() {
        updated.append(next)
      } else {
        updated.append(item)
      }
    }
    itemOrder = Self.normalizedOrder(from: updated.map(\.rawValue))
    save()
  }

  func setIconStyle(_ style: MenuBarIconStyle) {
    iconStyle = style
    save()
  }

  func resetToDefaults() {
    itemOrder = MenuBarItemKind.allCases.filter(\.isCustomizable)
    hiddenItems = []
    iconStyle = .default
    save()
  }

  /// Applies imported TOML configuration values (nil leaves the value untouched).
  func applyConfiguration(
    order: [MenuBarItemKind]?,
    hiddenItems: Set<MenuBarItemKind>?,
    iconStyle: MenuBarIconStyle?
  ) {
    if let order {
      itemOrder = Self.normalizedOrder(from: order.map(\.rawValue))
    }
    if let hiddenItems {
      self.hiddenItems = hiddenItems.filter { $0.isCustomizable || $0.isHideableOnly }
    }
    if let iconStyle {
      self.iconStyle = iconStyle
    }
    save()
  }

  // MARK: - Persistence

  private func save() {
    defaults.set(itemOrder.map(\.rawValue), forKey: PreferencesKeys.menuBarItemOrder)
    defaults.set(hiddenItems.map(\.rawValue).sorted(), forKey: PreferencesKeys.menuBarHiddenItems)
    defaults.set(iconStyle.rawValue, forKey: PreferencesKeys.menuBarIconStyle)
  }

  // MARK: - Normalization

  private static func normalizedOrder(from rawIDs: [String]?) -> [MenuBarItemKind] {
    let customizable = MenuBarItemKind.allCases.filter(\.isCustomizable)
    var seen = Set<MenuBarItemKind>()
    var ordered: [MenuBarItemKind] = []

    for rawID in rawIDs ?? [] {
      guard let item = MenuBarItemKind(rawValue: rawID),
            item.isCustomizable,
            !seen.contains(item) else { continue }
      ordered.append(item)
      seen.insert(item)
    }

    // Items missing from storage (fresh install or added in a later release)
    // append in default order; per-group filtering keeps them positioned
    // correctly within their own group.
    for item in customizable where !seen.contains(item) {
      ordered.append(item)
    }

    return ordered
  }

  private static func normalizedHiddenItems(from rawIDs: [String]?) -> Set<MenuBarItemKind> {
    guard let rawIDs else { return [] }
    return Set(rawIDs.compactMap(MenuBarItemKind.init(rawValue:)))
      .filter { $0.isCustomizable || $0.isHideableOnly }
  }

  private static func normalizedIconStyle(from rawValue: String?) -> MenuBarIconStyle {
    guard let rawValue, let style = MenuBarIconStyle(rawValue: rawValue) else {
      return .default
    }
    return style
  }
}
