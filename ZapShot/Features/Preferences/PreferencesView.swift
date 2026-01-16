//
//  PreferencesView.swift
//  ZapShot
//
//  Root preferences window with tabbed interface
//

import SwiftUI

struct PreferencesView: View {
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

      PlaceholderSettingsView.recording
        .tabItem { Label("Recording", systemImage: "video") }

//      PlaceholderSettingsView.cloud
//        .tabItem { Label("Cloud", systemImage: "cloud") }

      PlaceholderSettingsView.advanced
        .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
    }
    .frame(width: 700, height: 550)
  }
}

#Preview {
  PreferencesView()
}
