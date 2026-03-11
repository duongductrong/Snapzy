//
//  SnapzyApp.swift
//  Snapzy
//
//  Main app entry point - Menu Bar App
//

import SwiftUI

// MARK: - Notification Names

extension Notification.Name {
  static let showOnboarding = Notification.Name("showOnboarding")
}

@main
struct SnapzyApp: App {
  private let bootstrap: Void = {
    DefaultsDomainMigrationService.shared.runIfNeeded()
    AppIdentityManager.shared.refresh()
  }()
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @ObservedObject private var themeManager = ThemeManager.shared

  init() {
    _ = bootstrap
  }

  var body: some Scene {
    // Settings Window
    Settings {
      PreferencesView()
        .preferredColorScheme(themeManager.systemAppearance)
    }
  }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
  private var coordinator: AppCoordinator?

  func applicationDidFinishLaunching(_ notification: Notification) {
    DefaultsDomainMigrationService.shared.runIfNeeded()
    AppIdentityManager.shared.refresh()

    let coordinator = AppCoordinator(environment: AppEnvironment.live())
    self.coordinator = coordinator
    coordinator.applicationDidFinishLaunching()
  }

  func applicationWillTerminate(_ notification: Notification) {
    coordinator?.applicationWillTerminate()
  }
}
