//
//  PreferencesView.swift
//  Snapzy
//
//  Root preferences window with tabbed interface
//

import SwiftUI

struct PreferencesView: View {
  @ObservedObject private var themeManager = ThemeManager.shared
  @ObservedObject private var navigationState = PreferencesNavigationState.shared

  var body: some View {
    TabView(selection: $navigationState.selectedTab) {
      LazyView(GeneralSettingsView())
        .tabItem { Label(L10n.Preferences.generalTab, systemImage: "gearshape.fill") }
        .tag(PreferencesTab.general)

      LazyView(CaptureSettingsView())
        .tabItem { Label(L10n.Preferences.captureTab, systemImage: "camera.fill") }
        .tag(PreferencesTab.capture)

      LazyView(QuickAccessSettingsView())
        .tabItem { Label(L10n.Preferences.quickAccessTab, systemImage: "square.stack.fill") }
        .tag(PreferencesTab.quickAccess)

      LazyView(ShortcutsSettingsView())
        .tabItem { Label(L10n.Preferences.shortcutsTab, systemImage: "keyboard.fill") }
        .tag(PreferencesTab.shortcuts)

      LazyView(PermissionsSettingsView())
        .tabItem { Label(L10n.Preferences.permissionsTab, systemImage: "lock.shield.fill") }
        .tag(PreferencesTab.permissions)

      LazyView(CloudSettingsView())
        .tabItem { Label(L10n.Preferences.cloudTab, systemImage: "icloud.fill") }
        .tag(PreferencesTab.cloud)

      LazyView(AboutSettingsView())
        .tabItem { Label(L10n.Preferences.aboutTab, systemImage: "info.circle.fill") }
        .tag(PreferencesTab.about)
    }
    .frame(width: 700, height: 550)
  }
}

#Preview {
  PreferencesView()
}
