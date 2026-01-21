//
//  AppearanceMode.swift
//  ClaudeShot
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
  var displayName: String { rawValue }
}
