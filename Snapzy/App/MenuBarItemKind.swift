//
//  MenuBarItemKind.swift
//  Snapzy
//
//  Stable identifiers for customizable status bar menu entries.
//

import Foundation

/// Logical sections of the status bar menu. Group order is fixed; users reorder
/// items only within a group, and separators render between non-empty groups.
enum MenuBarItemGroup: String, CaseIterable {
  case capture
  case recording
  case tools
}

/// Identifiers for menu entries the user can hide and/or reorder.
/// Raw values are persisted in UserDefaults and TOML config — never rename.
/// Pinned entries (recording status block, permission prompt, What's New,
/// Preferences, Quit) are intentionally not represented here.
enum MenuBarItemKind: String, CaseIterable {
  // Capture
  case captureArea
  case captureAreaAnnotate
  case captureApplication
  case captureFullscreen
  case captureActiveWindow
  case scrollingCapture
  case captureOCR
  case captureSmartElement
  case captureObjectCutout

  // Recording
  case recordScreen
  case recordApplication

  // Tools
  case openAnnotate
  case combineImages
  case editVideo
  case cloudUploads
  case openHistory
  case shortcutList

  // App (fixed position, hideable only)
  case checkForUpdates

  var group: MenuBarItemGroup? {
    switch self {
    case .captureArea, .captureAreaAnnotate, .captureApplication, .captureFullscreen,
         .captureActiveWindow, .scrollingCapture, .captureOCR, .captureSmartElement,
         .captureObjectCutout:
      return .capture
    case .recordScreen, .recordApplication:
      return .recording
    case .openAnnotate, .combineImages, .editVideo, .cloudUploads, .openHistory, .shortcutList:
      return .tools
    case .checkForUpdates:
      return nil
    }
  }

  /// Items the user can both hide and reorder within their group.
  var isCustomizable: Bool { group != nil }

  /// Items the user can hide but not move from their default position.
  var isHideableOnly: Bool { self == .checkForUpdates }

  /// Title shown in the settings list. Reuses the same L10n keys as the menu.
  var settingsTitle: String {
    switch self {
    case .captureArea: return L10n.Actions.captureArea
    case .captureAreaAnnotate: return L10n.Actions.captureAreaAnnotate
    case .captureApplication: return L10n.PreferencesShortcuts.applicationCaptureTitle
    case .captureFullscreen: return L10n.Actions.captureFullscreen
    case .captureActiveWindow: return L10n.Actions.captureActiveWindow
    case .scrollingCapture: return L10n.Actions.scrollingCapture
    case .captureOCR: return L10n.Actions.captureTextOCR
    case .captureSmartElement: return L10n.Actions.captureSmartElement
    case .captureObjectCutout: return GlobalShortcutKind.objectCutout.displayName
    case .recordScreen: return L10n.Menu.recordScreen
    case .recordApplication: return L10n.PreferencesShortcuts.applicationRecordingTitle
    case .openAnnotate: return L10n.Actions.openAnnotate
    case .combineImages: return L10n.Combine.open
    case .editVideo: return L10n.Menu.editVideo
    case .cloudUploads: return L10n.Actions.cloudUploads
    case .openHistory: return L10n.Actions.openHistory
    case .shortcutList: return L10n.Menu.keyboardShortcuts
    case .checkForUpdates: return L10n.Menu.checkForUpdates
    }
  }

  /// SF Symbol matching the icon used by the menu entry.
  var systemImage: String {
    switch self {
    case .captureArea: return "crop"
    case .captureAreaAnnotate: return "pencil.and.scribble"
    case .captureApplication: return "macwindow"
    case .captureFullscreen: return "rectangle.dashed"
    case .captureActiveWindow: return "macwindow.on.rectangle"
    case .scrollingCapture: return "arrow.up.and.down"
    case .captureOCR: return "text.viewfinder"
    case .captureSmartElement: return "dot.viewfinder"
    case .captureObjectCutout: return "person.crop.rectangle"
    case .recordScreen: return "record.circle"
    case .recordApplication: return "square.on.square"
    case .openAnnotate: return "pencil.and.outline"
    case .combineImages: return "rectangle.3.group"
    case .editVideo: return "film"
    case .cloudUploads: return "icloud.and.arrow.up"
    case .openHistory: return "clock.arrow.circlepath"
    case .shortcutList: return "list.bullet.rectangle"
    case .checkForUpdates: return "arrow.triangle.2.circlepath"
    }
  }

  /// Default in-group order for customizable items of a group.
  static func defaultOrder(for group: MenuBarItemGroup) -> [MenuBarItemKind] {
    allCases.filter { $0.group == group }
  }
}
