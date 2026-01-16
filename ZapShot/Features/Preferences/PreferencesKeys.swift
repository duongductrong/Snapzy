//
//  PreferencesKeys.swift
//  ZapShot
//
//  Shared UserDefaults keys for preferences
//

import Foundation

/// Centralized keys for UserDefaults storage
enum PreferencesKeys {
  // General
  static let playSounds = "playSounds"
  static let showMenuBarIcon = "showMenuBarIcon"
  static let exportLocation = "exportLocation"

  // Shortcuts
  static let shortcutsEnabled = "shortcutsEnabled"
  static let fullscreenShortcut = "fullscreenShortcut"
  static let areaShortcut = "areaShortcut"

  // Floating Screenshot (Quick Access)
  static let floatingEnabled = "floatingScreenshot.enabled"
  static let floatingPosition = "floatingScreenshot.position"
  static let floatingAutoDismissEnabled = "floatingScreenshot.autoDismissEnabled"
  static let floatingAutoDismissDelay = "floatingScreenshot.autoDismissDelay"
  static let floatingOverlayScale = "floatingScreenshot.overlayScale"
  static let floatingDragDropEnabled = "floatingScreenshot.dragDropEnabled"
  static let floatingShowCloudUpload = "floatingScreenshot.showCloudUpload"
}
