//
//  MagnifierSizeOption.swift
//  Snapzy
//
//  Size of the area-selection magnifier, stored as its raw value under
//  `PreferencesKeys.screenshotMagnifierSize`.
//

import CoreGraphics
import Foundation

enum MagnifierSizeOption: String, CaseIterable, Identifiable {
  case small
  case medium
  case large

  /// The size the magnifier had before this preference existed, so upgrades look unchanged.
  static let defaultValue: MagnifierSizeOption = .medium

  var id: String { rawValue }

  /// Side length of the square preview. The color picker panel below it shares this width;
  /// 128pt is the narrowest width that still fits the hex row, the coordinates row and the
  /// English copy hint without clipping.
  var previewSize: CGFloat {
    switch self {
    case .small: return 128
    case .medium: return 160
    case .large: return 200
    }
  }

  var displayName: String {
    switch self {
    case .small: return L10n.PreferencesCapture.magnifierSizeSmall
    case .medium: return L10n.PreferencesCapture.magnifierSizeMedium
    case .large: return L10n.PreferencesCapture.magnifierSizeLarge
    }
  }

  /// Unset or unknown stored values (hand-edited defaults) fall back to the default.
  static func resolve(_ rawValue: String?) -> MagnifierSizeOption {
    rawValue.flatMap(MagnifierSizeOption.init(rawValue:)) ?? defaultValue
  }

  static func current(defaults: UserDefaults = .standard) -> MagnifierSizeOption {
    resolve(defaults.string(forKey: PreferencesKeys.screenshotMagnifierSize))
  }
}
