//
//  AppearanceMode.swift
//  Snapzy
//
//  User appearance preference: system, light, or dark
//

import Foundation

/// User preference for app appearance
enum AppearanceMode: String, CaseIterable, Identifiable {
  case system = "System"
  case light = "Light"
  case dark = "Dark"

  var id: String { rawValue }

  /// Display name for UI
  var displayName: String {
    switch self {
    case .system:
      return L10n.Appearance.system
    case .light:
      return L10n.Appearance.light
    case .dark:
      return L10n.Appearance.dark
    }
  }
}
