//
//  QuickAccessActionConfigurationStore.swift
//  Snapzy
//
//  UserDefaults-backed quick action order and visibility.
//

import Combine
import Foundation

@MainActor
final class QuickAccessActionConfigurationStore: ObservableObject {
  static let shared = QuickAccessActionConfigurationStore()

  @Published private(set) var actionOrder: [QuickAccessActionKind]
  @Published private(set) var enabledActions: Set<QuickAccessActionKind>
  @Published private(set) var slotAssignments: [QuickAccessActionSlot: QuickAccessActionKind]

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    actionOrder = Self.normalizedOrder(from: defaults.stringArray(forKey: PreferencesKeys.quickAccessActionOrder))
    enabledActions = Self.normalizedEnabledActions(
      from: defaults.stringArray(forKey: PreferencesKeys.quickAccessEnabledActions),
      known: defaults.stringArray(forKey: PreferencesKeys.quickAccessKnownActions)
    )
    slotAssignments = Self.normalizedSlotAssignments(
      from: defaults.dictionary(forKey: PreferencesKeys.quickAccessActionSlotAssignments) as? [String: String]
    )
  }

  func orderedActions(includeDisabled: Bool) -> [QuickAccessActionKind] {
    guard !includeDisabled else { return actionOrder }
    return actionOrder.filter { enabledActions.contains($0) }
  }

  func isEnabled(_ action: QuickAccessActionKind) -> Bool {
    enabledActions.contains(action)
  }

  func action(in slot: QuickAccessActionSlot) -> QuickAccessActionKind? {
    slotAssignments[slot]
  }

  func assignedSlot(for action: QuickAccessActionKind) -> QuickAccessActionSlot? {
    QuickAccessActionSlot.allCases.first { slotAssignments[$0] == action }
  }

  func setEnabled(_ action: QuickAccessActionKind, enabled: Bool) {
    var updatedActions = enabledActions
    if enabled {
      updatedActions.insert(action)
    } else {
      updatedActions.remove(action)
    }
    enabledActions = updatedActions
    save()
  }

  func assignAction(_ action: QuickAccessActionKind, to slot: QuickAccessActionSlot) {
    var updatedAssignments = slotAssignments
    for assignedSlot in QuickAccessActionSlot.allCases where updatedAssignments[assignedSlot] == action {
      updatedAssignments[assignedSlot] = nil
    }
    updatedAssignments[slot] = action
    slotAssignments = updatedAssignments
    save()
  }

  func clearSlot(_ slot: QuickAccessActionSlot) {
    var updatedAssignments = slotAssignments
    updatedAssignments[slot] = nil
    slotAssignments = updatedAssignments
    save()
  }

  func moveAction(from source: IndexSet, to destination: Int) {
    guard !source.isEmpty else { return }

    let movingActions = source.sorted().map { actionOrder[$0] }
    var updatedOrder = actionOrder
    for index in source.sorted(by: >) {
      updatedOrder.remove(at: index)
    }

    let removedBeforeDestination = source.filter { $0 < destination }.count
    let insertionIndex = max(0, min(destination - removedBeforeDestination, updatedOrder.count))
    updatedOrder.insert(contentsOf: movingActions, at: insertionIndex)

    actionOrder = Self.normalizedOrder(from: updatedOrder.map(\.rawValue))
    save()
  }

  func resetToDefaults() {
    actionOrder = QuickAccessActionKind.defaultOrder
    enabledActions = QuickAccessActionKind.defaultEnabledActions
    slotAssignments = QuickAccessActionSlot.defaultAssignments
    save()
  }

  func applyConfiguration(
    order: [QuickAccessActionKind]?,
    enabledActions: Set<QuickAccessActionKind>?,
    slotAssignments: [QuickAccessActionSlot: QuickAccessActionKind]?
  ) {
    if let order {
      actionOrder = Self.normalizedOrder(from: order.map(\.rawValue))
    }
    if let enabledActions {
      self.enabledActions = enabledActions
    }
    if let slotAssignments {
      self.slotAssignments = Self.normalizedSlotAssignments(
        from: rawSlotAssignments(from: slotAssignments)
      )
    }
    save()
  }

  private func save() {
    defaults.set(actionOrder.map(\.rawValue), forKey: PreferencesKeys.quickAccessActionOrder)
    defaults.set(
      actionOrder.filter { enabledActions.contains($0) }.map(\.rawValue),
      forKey: PreferencesKeys.quickAccessEnabledActions
    )
    defaults.set(rawSlotAssignments(from: slotAssignments), forKey: PreferencesKeys.quickAccessActionSlotAssignments)
    defaults.set(QuickAccessActionKind.allCases.map(\.rawValue), forKey: PreferencesKeys.quickAccessKnownActions)
  }

  private static func normalizedOrder(from rawIDs: [String]?) -> [QuickAccessActionKind] {
    var seen = Set<QuickAccessActionKind>()
    var ordered: [QuickAccessActionKind] = []

    for rawID in rawIDs ?? [] {
      guard let action = QuickAccessActionKind(rawValue: rawID), !seen.contains(action) else { continue }
      ordered.append(action)
      seen.insert(action)
    }

    for action in QuickAccessActionKind.defaultOrder where !seen.contains(action) {
      ordered.append(action)
    }

    return ordered
  }

  /// `known` is the action list the enabled list was saved against. Actions added
  /// since then were never offered to the user, so they start enabled when they
  /// are enabled by default; an explicit disable of a known action is kept.
  static func normalizedEnabledActions(
    from rawIDs: [String]?,
    known rawKnownIDs: [String]?
  ) -> Set<QuickAccessActionKind> {
    guard let rawIDs else {
      return QuickAccessActionKind.defaultEnabledActions
    }

    let saved = Set(rawIDs.compactMap(QuickAccessActionKind.init(rawValue:)))
    let known = rawKnownIDs.map { Set($0.compactMap(QuickAccessActionKind.init(rawValue:))) }
      ?? QuickAccessActionKind.legacyKnownActions
    let introduced = QuickAccessActionKind.defaultEnabledActions.subtracting(known)
    return saved.union(introduced)
  }

  private static func normalizedSlotAssignments(
    from rawAssignments: [String: String]?
  ) -> [QuickAccessActionSlot: QuickAccessActionKind] {
    guard let rawAssignments else {
      return QuickAccessActionSlot.defaultAssignments
    }

    var seenActions = Set<QuickAccessActionKind>()
    var assignments: [QuickAccessActionSlot: QuickAccessActionKind] = [:]

    for slot in QuickAccessActionSlot.allCases {
      let action: QuickAccessActionKind?
      if let rawAction = rawAssignments[slot.rawValue] {
        action = rawAction.isEmpty ? nil : QuickAccessActionKind(rawValue: rawAction)
      } else {
        action = QuickAccessActionSlot.defaultAssignments[slot]
      }

      guard let action,
            !seenActions.contains(action) else {
        continue
      }

      assignments[slot] = action
      seenActions.insert(action)
    }

    return assignments
  }

  private func rawSlotAssignments(
    from assignments: [QuickAccessActionSlot: QuickAccessActionKind]
  ) -> [String: String] {
    var rawAssignments: [String: String] = [:]
    for slot in QuickAccessActionSlot.allCases {
      rawAssignments[slot.rawValue] = assignments[slot]?.rawValue ?? ""
    }
    return rawAssignments
  }
}
