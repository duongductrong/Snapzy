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
    let didCrash = CrashSentinel.shared.checkAndReset()
    DiagnosticLogger.shared.startSession()
    LegacyLicenseCleanupService.shared.runIfNeeded()
    LogCleanupScheduler.shared.start()
    RecordingMetadataCleanupScheduler.shared.start()

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
