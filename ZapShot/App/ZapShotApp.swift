//
//  ZapShotApp.swift
//  ZapShot
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
struct ZapShotApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @StateObject private var viewModel = ScreenCaptureViewModel()
  @State private var showOnboarding = !OnboardingFlowView.hasCompletedOnboarding
  @ObservedObject private var themeManager = ThemeManager.shared

  // Sparkle updater controller
  private let updaterController: SPUStandardUpdaterController

  init() {
    updaterController = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  }

  var body: some Scene {
    // Menu Bar
    MenuBarExtra("ZapShot", systemImage: "camera.aperture") {
      MenuBarContentView(viewModel: viewModel, updater: updaterController.updater)
        .preferredColorScheme(themeManager.systemAppearance)
    }

    // Onboarding Window (shown only when needed)
    WindowGroup(id: "onboarding") {
      OnboardingFlowView(onComplete: {
        showOnboarding = false
        // Close onboarding window
        NSApp.windows
          .filter { $0.identifier?.rawValue.contains("onboarding") == true }
          .forEach { $0.close() }
      })
      .frame(width: 500, height: 450)
      .preferredColorScheme(themeManager.systemAppearance)
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
  func applicationDidFinishLaunching(_ notification: Notification) {
    // Show onboarding on first launch
    if !OnboardingFlowView.hasCompletedOnboarding {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        self.showOnboardingWindow()
      }
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
    // If onboarding window not found, open it via OpenWindow environment
//    if let url = URL(string: "zapshot://onboarding") {
//      NSWorkspace.shared.open(url)
//    }
  }
}

// MARK: - Menu Bar Content

struct MenuBarContentView: View {
  @ObservedObject var viewModel: ScreenCaptureViewModel
  let updater: SPUUpdater

  var body: some View {
    Group {
      // Capture Actions
      Button {
        viewModel.captureArea()
      } label: {
        Label("Capture Area", systemImage: "crop")
      }
      .keyboardShortcut("4", modifiers: [.command, .shift])
      .disabled(!viewModel.hasPermission)

      Button {
        viewModel.captureFullscreen()
      } label: {
        Label("Capture Fullscreen", systemImage: "rectangle.dashed")
      }
      .keyboardShortcut("3", modifiers: [.command, .shift])
      .disabled(!viewModel.hasPermission)

      Divider()

      // Recording
      Button {
        viewModel.startRecordingFlow()
      } label: {
        Label("Record Screen", systemImage: "record.circle")
      }
      .keyboardShortcut("5", modifiers: [.command, .shift])
      .disabled(!viewModel.hasPermission)

      Divider()

      // Tools
      Button {
        AnnotateManager.shared.openEmptyAnnotation()
      } label: {
        Label("Open Annotate", systemImage: "pencil.and.outline")
      }
      .keyboardShortcut("a", modifiers: [.command, .shift])

      Divider()

      // Permission Status (if not granted)
      if !viewModel.hasPermission {
        Button {
          viewModel.requestPermission()
        } label: {
          Label("Grant Permission...", systemImage: "lock.shield")
        }

        Divider()
      }

      // Check for Updates
      CheckForUpdatesView(updater: updater)

      // Preferences
      SettingsLink {
        Label("Preferences...", systemImage: "gear")
      }
      .keyboardShortcut(",", modifiers: .command)

      Divider()

      // Quit
      Button {
        NSApp.terminate(nil)
      } label: {
        Label("Quit ZapShot", systemImage: "power")
      }
      .keyboardShortcut("q", modifiers: .command)
    }
  }
}
