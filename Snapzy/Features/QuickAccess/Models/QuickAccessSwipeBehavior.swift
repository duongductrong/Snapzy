//
//  QuickAccessSwipeBehavior.swift
//  Snapzy
//
//  Configurable behaviors for Quick Access card swipe directions.
//

import Foundation

/// Behaviors that can be assigned to a horizontal swipe direction.
enum QuickAccessSwipeBehavior: String, CaseIterable, Codable, Identifiable {
  case none
  case dismiss
  case dragToApp

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .none:
      return L10n.PreferencesQuickAccess.swipeBehaviorNone
    case .dismiss:
      return L10n.PreferencesQuickAccess.swipeBehaviorDismiss
    case .dragToApp:
      return L10n.PreferencesQuickAccess.swipeBehaviorDragToApp
    }
  }
}

/// Absolute horizontal swipe directions that can be configured in settings.
enum QuickAccessSwipeDirection: String, CaseIterable, Codable, Identifiable {
  case left
  case right

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .left:
      return L10n.PreferencesQuickAccess.swipeDirectionLeft
    case .right:
      return L10n.PreferencesQuickAccess.swipeDirectionRight
    }
  }
}
