//
//  MenuBarIconStyle.swift
//  Snapzy
//
//  Selectable menu bar icon styles.
//

import Foundation

/// Menu bar icon choices: the bundled default artwork, built-in SF Symbol
/// alternates, or a user-imported custom PNG.
/// Raw values are persisted in UserDefaults and TOML config — never rename.
enum MenuBarIconStyle: String, CaseIterable, Identifiable {
  case `default`
  case cameraViewfinder
  case cameraFill
  case scissors
  case photoOnRectangle
  case custom

  var id: String { rawValue }

  /// SF Symbol backing built-in alternates. `nil` for the bundled default
  /// artwork and the user-imported custom icon.
  var symbolName: String? {
    switch self {
    case .cameraViewfinder: return "camera.viewfinder"
    case .cameraFill: return "camera.fill"
    case .scissors: return "scissors"
    case .photoOnRectangle: return "photo.on.rectangle"
    case .default, .custom: return nil
    }
  }
}
