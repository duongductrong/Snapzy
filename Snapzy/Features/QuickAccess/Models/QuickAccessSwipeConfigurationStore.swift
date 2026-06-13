//
//  QuickAccessSwipeConfigurationStore.swift
//  Snapzy
//
//  Persisted mapping of swipe directions to behaviors for Quick Access cards.
//

import Combine
import Foundation

/// Stores user-configured swipe behaviors for the Quick Access panel.
@MainActor
final class QuickAccessSwipeConfigurationStore: ObservableObject {
  static let shared = QuickAccessSwipeConfigurationStore()

  @Published private(set) var leftBehavior: QuickAccessSwipeBehavior
  @Published private(set) var rightBehavior: QuickAccessSwipeBehavior

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    // Default toward the nearest screen edge to dismiss and the opposite
    // direction to do nothing. The default is based on the current panel side
    // so first-time users get the expected "swipe toward edge" behavior.
    let isLeftSide = QuickAccessManager.shared.position.isLeftSide
    let defaultLeftBehavior: QuickAccessSwipeBehavior = isLeftSide ? .dismiss : .none
    let defaultRightBehavior: QuickAccessSwipeBehavior = isLeftSide ? .none : .dismiss

    self.leftBehavior = Self.behavior(
      from: defaults.string(forKey: PreferencesKeys.quickAccessSwipeLeftBehavior),
      default: defaultLeftBehavior
    )
    self.rightBehavior = Self.behavior(
      from: defaults.string(forKey: PreferencesKeys.quickAccessSwipeRightBehavior),
      default: defaultRightBehavior
    )
  }

  func behavior(for direction: QuickAccessSwipeDirection) -> QuickAccessSwipeBehavior {
    switch direction {
    case .left: return leftBehavior
    case .right: return rightBehavior
    }
  }

  func setBehavior(_ behavior: QuickAccessSwipeBehavior, for direction: QuickAccessSwipeDirection) {
    switch direction {
    case .left:
      guard leftBehavior != behavior else { return }
      leftBehavior = behavior
    case .right:
      guard rightBehavior != behavior else { return }
      rightBehavior = behavior
    }
    save()
  }

  func resetToDefaults() {
    let isLeftSide = QuickAccessManager.shared.position.isLeftSide
    leftBehavior = isLeftSide ? .dismiss : .none
    rightBehavior = isLeftSide ? .none : .dismiss
    save()
  }

  private func save() {
    defaults.set(leftBehavior.rawValue, forKey: PreferencesKeys.quickAccessSwipeLeftBehavior)
    defaults.set(rightBehavior.rawValue, forKey: PreferencesKeys.quickAccessSwipeRightBehavior)
  }

  private static func behavior(
    from rawValue: String?,
    default defaultBehavior: QuickAccessSwipeBehavior
  ) -> QuickAccessSwipeBehavior {
    guard let rawValue = rawValue,
          let behavior = QuickAccessSwipeBehavior(rawValue: rawValue) else {
      return defaultBehavior
    }
    return behavior
  }
}
