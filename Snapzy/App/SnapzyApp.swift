//
//  SnapzyApp.swift
//  Snapzy
//
//  Main app entry point - Menu Bar App
//

import SwiftUI
import Sparkle

// MARK: - Notification Names

extension Notification.Name {
  static let showOnboarding = Notification.Name("showOnboarding")
}

@main
struct SnapzyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @AppStorage(PreferencesKeys.onboardingCompleted) private var onboardingCompleted = false
  @ObservedObject private var themeManager = ThemeManager.shared

  var body: some Scene {
    // Onboarding Window (shown only when needed)
    WindowGroup(id: "onboarding") {
      if onboardingCompleted == false {
        OnboardingFlowView(onComplete: {
          onboardingCompleted = true
          // Close onboarding window
          NSApp.windows
            .filter { $0.identifier?.rawValue.contains("onboarding") == true }
            .forEach { $0.close() }
        })
        .frame(width: 700, height: 600)
        .preferredColorScheme(themeManager.systemAppearance)
      }
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .defaultSize(width: 500, height: 450)

    // Settings Window
    Settings {
      PreferencesView()
        .preferredColorScheme(themeManager.systemAppearance)
    }
  }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
  private let viewModel = ScreenCaptureViewModel()

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Setup status bar with dependencies (uses shared UpdaterManager)
    StatusBarController.shared.setup(
      viewModel: viewModel,
      updater: UpdaterManager.shared.updater
    )

    // Show splash on every launch
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      SplashWindowController.shared.show(onContinue: { [weak self] in
        // After splash dismisses, show onboarding if not completed
        if !OnboardingFlowView.hasCompletedOnboarding {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self?.showOnboardingWindow()
          }
        }
      })
    }

    // Listen for restart onboarding notification
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleShowOnboarding),
      name: .showOnboarding,
      object: nil
    )
  }

  @objc private func handleShowOnboarding() {
    showOnboardingWindow()
  }

  private func showOnboardingWindow() {
    NSApp.activate(ignoringOtherApps: true)
    for window in NSApp.windows {
      if window.identifier?.rawValue.contains("onboarding") == true {
        window.makeKeyAndOrderFront(nil)
        window.center()
        return
      }
    }
  }
}

