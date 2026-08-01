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

      LazyView(MenuBarSettingsView())
        .tabItem { Label(L10n.Preferences.menuBarTab, systemImage: "menubar.rectangle") }
        .tag(PreferencesTab.menuBar)

      LazyView(CaptureSettingsView())
        .tabItem { Label(L10n.Preferences.captureTab, systemImage: "camera.fill") }
        .tag(PreferencesTab.capture)

      LazyView(AnnotateSettingsView())
        .tabItem { Label(L10n.Preferences.annotateTab, systemImage: "pencil.and.scribble") }
        .tag(PreferencesTab.annotate)

      LazyView(QuickAccessSettingsView())
        .tabItem { Label(L10n.Preferences.quickAccessTab, systemImage: "square.stack.fill") }
        .tag(PreferencesTab.quickAccess)

      LazyView(HistorySettingsView())
        .tabItem { Label(L10n.Preferences.historyTab, systemImage: "clock.arrow.circlepath") }
        .tag(PreferencesTab.history)

      LazyView(ShortcutsSettingsView())
        .tabItem { Label(L10n.Preferences.shortcutsTab, systemImage: "keyboard.fill") }
        .tag(PreferencesTab.shortcuts)

      LazyView(PermissionsSettingsView())
        .tabItem { Label(L10n.Preferences.permissionsTab, systemImage: "lock.shield.fill") }
        .tag(PreferencesTab.permissions)

      LazyView(CloudSettingsView())
        .tabItem { Label(L10n.Preferences.cloudTab, systemImage: "icloud.fill") }
        .tag(PreferencesTab.cloud)

      LazyView(AdvancedSettingsView())
        .tabItem { Label(L10n.Preferences.advancedTab, systemImage: "slider.horizontal.3") }
        .tag(PreferencesTab.advanced)

      LazyView(AboutSettingsView())
        .tabItem { Label(L10n.Preferences.aboutTab, systemImage: "info.circle.fill") }
        .tag(PreferencesTab.about)
    }
    .frame(width: 760, height: 550)
  }
}

#Preview {
  PreferencesView()
}
