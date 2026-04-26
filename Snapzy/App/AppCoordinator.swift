//
//  AppCoordinator.swift
//  Snapzy
//
//  App lifecycle orchestration for startup, notifications, and shutdown.
//

import AppKit
import Foundation

@MainActor
final class AppCoordinator {
  private let environment: AppEnvironment
  private var observers: [NSObjectProtocol] = []

  init(environment: AppEnvironment) {
    self.environment = environment
  }

  func applicationDidFinishLaunching() {
    AppIdentityManager.shared.refresh()
    let didCrash = CrashSentinel.shared.checkAndReset()
    DiagnosticLogger.shared.startSession()
    LegacyLicenseCleanupService.shared.runIfNeeded()
    LogCleanupScheduler.shared.start()
    RecordingMetadataCleanupScheduler.shared.start()

    // History defaults
    let defaults = UserDefaults.standard
    if defaults.object(forKey: PreferencesKeys.historyEnabled) == nil {
      defaults.set(true, forKey: PreferencesKeys.historyEnabled)
    }
    if defaults.object(forKey: PreferencesKeys.historyRetentionDays) == nil {
      defaults.set(30, forKey: PreferencesKeys.historyRetentionDays)
    }
    if defaults.object(forKey: PreferencesKeys.historyMaxCount) == nil {
      defaults.set(500, forKey: PreferencesKeys.historyMaxCount)
    }
    if defaults.object(forKey: PreferencesKeys.historyOpenOnLaunch) == nil {
      defaults.set(false, forKey: PreferencesKeys.historyOpenOnLaunch)
    }

    // Floating history panel defaults
    if defaults.object(forKey: "history.floating.enabled") == nil {
      defaults.set(true, forKey: "history.floating.enabled")
    }
    if defaults.object(forKey: "history.floating.position") == nil {
      defaults.set("topCenter", forKey: "history.floating.position")
    }
    if defaults.object(forKey: "history.floating.maxDisplayedItems") == nil {
      defaults.set(10, forKey: "history.floating.maxDisplayedItems")
    }

    CaptureHistoryRetentionService.shared.start()

    AppStatusBarController.shared.setup(
      viewModel: environment.screenCaptureViewModel,
      updater: UpdaterManager.shared.updater,
      didCrash: didCrash && DiagnosticLogger.shared.isEnabled
    )

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      SplashWindowController.shared.show()
    }

    observeNotifications()
  }

  func applicationWillTerminate() {
    DiagnosticLogger.shared.log(.info, .lifecycle, "App terminated normally")
    CrashSentinel.shared.markTerminated()
    LogCleanupScheduler.shared.stop()
    RecordingMetadataCleanupScheduler.shared.stop()

    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers.removeAll()
  }

  func handleDeepLink(_ url: URL) {
    SnapzyDeepLinkHandler(screenCaptureViewModel: environment.screenCaptureViewModel)
      .handle(url)
  }

  private func observeNotifications() {
    let onboardingObserver = NotificationCenter.default.addObserver(
      forName: .showOnboarding,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        SplashWindowController.shared.show(forceOnboarding: true)
      }
    }

    observers.append(onboardingObserver)
  }
}
