//
//  PreferencesView.swift
//  Snapzy
//
//  Root preferences window with tabbed interface
//

import SwiftUI

struct PreferencesView: View {
  @ObservedObject private var themeManager = ThemeManager.shared

  var body: some View {
    TabView {
      GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gearshape.fill") }

      CaptureSettingsView()
        .tabItem { Label("Capture", systemImage: "camera.fill") }

      QuickAccessSettingsView()
        .tabItem { Label("Quick Access", systemImage: "square.stack.fill") }

      ShortcutsSettingsView()
        .tabItem { Label("Shortcuts", systemImage: "keyboard.fill") }

      PermissionsSettingsView()
        .tabItem { Label("Permissions", systemImage: "lock.shield.fill") }

      AboutSettingsView()
        .tabItem { Label("About", systemImage: "info.circle.fill") }
    }
    .frame(width: 700, height: 550)
  }
}

#Preview {
  PreferencesView()
}
