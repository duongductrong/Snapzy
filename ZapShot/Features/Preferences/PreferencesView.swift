//
//  PreferencesView.swift
//  ZapShot
//
//  Root preferences window with tabbed interface
//

import SwiftUI

struct PreferencesView: View {
  @ObservedObject private var themeManager = ThemeManager.shared

  var body: some View {
    TabView {
      GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gear") }

//      PlaceholderSettingsView.wallpaper
//        .tabItem { Label("Wallpaper", systemImage: "photo") }

      ShortcutsSettingsView()
        .tabItem { Label("Shortcuts", systemImage: "keyboard") }

      QuickAccessSettingsView()
        .tabItem { Label("Quick Access", systemImage: "square.stack") }

      RecordingSettingsView()
        .tabItem { Label("Recording", systemImage: "video") }

//      PlaceholderSettingsView.cloud
//        .tabItem { Label("Cloud", systemImage: "cloud") }

      PlaceholderSettingsView.advanced
        .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }

      AboutSettingsView()
        .tabItem { Label("About", systemImage: "info.circle") }
    }
    .frame(width: 700, height: 550)
    .onAppear {
      // Bring preferences window to front
      NSApp.activate(ignoringOtherApps: true)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        NSApp.windows
          .filter { $0.title.contains("Settings") || $0.title.contains("Preferences") }
          .forEach { $0.makeKeyAndOrderFront(nil) }
      }
    }
  }
}

#Preview {
  PreferencesView()
}
