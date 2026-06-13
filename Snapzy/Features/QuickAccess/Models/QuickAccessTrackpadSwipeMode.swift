//
//  QuickAccessTrackpadSwipeMode.swift
//  Snapzy
//
//  Trackpad swipe direction mode for Quick Access cards.
//

import Foundation

/// Determines how a two-finger horizontal swipe on a Quick Access card is translated.
enum QuickAccessTrackpadSwipeMode: String, CaseIterable, Codable, Identifiable {
  /// The card follows the finger direction, e.g. swipe left moves the card left.
  case natural
  /// The card moves opposite to the finger direction, e.g. swipe left moves the card right.
  case inverted

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .natural:
      return L10n.PreferencesQuickAccess.trackpadSwipeModeNatural
    case .inverted:
      return L10n.PreferencesQuickAccess.trackpadSwipeModeInverted
    }
  }

  /// Multiplier applied to the raw scrolling delta for this mode.
  var translationMultiplier: CGFloat {
    switch self {
    case .natural: return -1
    case .inverted: return 1
    }
  }
}
