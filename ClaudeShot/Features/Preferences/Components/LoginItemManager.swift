//
//  LoginItemManager.swift
//  ClaudeShot
//
//  Wrapper for SMAppService to manage launch at login
//

import ServiceManagement

/// Manages the app's login item status using SMAppService
struct LoginItemManager {

  /// Enable or disable launch at login
  static func setEnabled(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      print("LoginItemManager: Failed to update login item - \(error.localizedDescription)")
    }
  }

  /// Check if launch at login is currently enabled
  static var isEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }
}
