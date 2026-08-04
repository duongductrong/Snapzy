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
    DiagnosticLogger.shared.log(
      .info,
      .lifecycle,
      "App launch sequence started",
      context: ["previousCrash": didCrash ? "true" : "false"]
    )
    LegacyLicenseCleanupService.shared.runIfNeeded()

    let defaults = UserDefaults.standard
    if defaults.object(forKey: PreferencesKeys.diagnosticsRetentionDays) == nil {
      defaults.set(LogCleanupScheduler.defaultRetentionDays, forKey: PreferencesKeys.diagnosticsRetentionDays)
    }

    if defaults.object(forKey: PreferencesKeys.urlSchemeEnabled) == nil {
      defaults.set(true, forKey: PreferencesKeys.urlSchemeEnabled)
    }

    // History defaults
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

    let configurationAutoImportResult = applyUserConfigurationIfNeeded()
    startConfigurationSync(after: configurationAutoImportResult)

    LogCleanupScheduler.shared.start()
    RecordingMetadataCleanupScheduler.shared.start()
    CaptureHistoryRetentionService.shared.start()
    DiagnosticLogger.shared.log(.debug, .lifecycle, "Background schedulers started")

    AppStatusBarController.shared.setup(
      viewModel: environment.screenCaptureViewModel,
      updater: UpdaterManager.shared.updater,
      didCrash: didCrash && DiagnosticLogger.shared.isEnabled
    )
    DiagnosticLogger.shared.log(
      .debug,
      .ui,
      "Status bar controller configured",
      context: ["crashPrompt": (didCrash && DiagnosticLogger.shared.isEnabled) ? "true" : "false"]
    )

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      DiagnosticLogger.shared.log(.debug, .ui, "Splash presentation scheduled")
      self.presentStartupExperience(configurationAutoImportResult: configurationAutoImportResult)
    }

    observeNotifications()
  }

  func applicationWillTerminate() {
    flushConfigurationSyncBeforeTermination()
    DiagnosticLogger.shared.log(.info, .lifecycle, "App terminated normally")
    CrashSentinel.shared.markTerminated()
    LogCleanupScheduler.shared.stop()
    RecordingMetadataCleanupScheduler.shared.stop()
    SnapzyConfigurationSyncCoordinator.shared.stop()

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
        DiagnosticLogger.shared.log(.info, .ui, "Onboarding requested from notification")
        SplashWindowController.shared.show(forceOnboarding: true)
      }
    }

    observers.append(onboardingObserver)
    DiagnosticLogger.shared.log(
      .debug,
      .lifecycle,
      "App notifications observed",
      context: ["observerCount": "\(observers.count)"]
    )
  }

  private func applyUserConfigurationIfNeeded() -> SnapzyConfigurationAutoImportResult {
    let result = SnapzyConfigurationAutoImporter.applyIfNeededOnLaunch()
    let context = [
      "file": result.fileURL.path,
      "changes": "\(result.appliedChangeCount)",
      "warnings": "\(result.warningCount)",
      "errors": "\(result.errorCount)"
    ]

    switch result.status {
    case .applied:
      DiagnosticLogger.shared.log(
        .info,
        .preferences,
        "TOML configuration auto-applied",
        context: context
      )
    case .failed:
      var failedContext = context
      if let errorMessage = result.errorMessage {
        failedContext["error"] = errorMessage
      }
      DiagnosticLogger.shared.log(
        .warning,
        .preferences,
        "TOML configuration auto-apply failed",
        context: failedContext
      )
    case .skippedMissingFile:
      DiagnosticLogger.shared.log(
        .debug,
        .preferences,
        "TOML configuration auto-apply skipped; file missing",
        context: ["file": result.fileURL.path]
      )
    case .skippedPermissionRequired:
      DiagnosticLogger.shared.log(
        .debug,
        .preferences,
        "TOML configuration auto-apply skipped; folder access required",
        context: ["file": result.fileURL.path]
      )
    case .skippedUnchanged:
      DiagnosticLogger.shared.log(
        .debug,
        .preferences,
        "TOML configuration auto-apply skipped; file unchanged",
        context: ["file": result.fileURL.path]
      )
    }

    return result
  }

  private func startConfigurationSync(after autoImportResult: SnapzyConfigurationAutoImportResult) {
    let coordinator = SnapzyConfigurationSyncCoordinator.shared
    coordinator.start()

    guard autoImportResult.status != .applied else { return }
    coordinator.scheduleSync(reason: .appLaunch)
  }

  private func flushConfigurationSyncBeforeTermination() {
    do {
      try SnapzyConfigurationSyncCoordinator.shared.flushPendingSync(reason: .appTerminate)
    } catch {
      DiagnosticLogger.shared.logError(
        .preferences,
        error,
        "TOML configuration sync before termination failed"
      )
    }
  }

  private func presentStartupExperience(
    configurationAutoImportResult: SnapzyConfigurationAutoImportResult
  ) {
    if shouldPresentConfigurationAccessOnboarding(for: configurationAutoImportResult) {
      UserDefaults.standard.set(true, forKey: PreferencesKeys.configurationAccessOnboardingPrompted)
      DiagnosticLogger.shared.log(.info, .ui, "Configuration access onboarding scheduled")
      SplashWindowController.shared.showConfigurationAccess()
      return
    }

    SplashWindowController.shared.show()
    
    // Automatically show the new feature intro once
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      // Cleanup legacy key
      UserDefaults.standard.removeObject(forKey: "hasSeenSmartElementIntro")
      
      if let campaign = FeatureIntroManager.shared.getPendingCampaign() {
        FeatureIntroManager.shared.showCampaign(campaign)
      }
    }
  }

  private func shouldPresentConfigurationAccessOnboarding(
    for result: SnapzyConfigurationAutoImportResult
  ) -> Bool {
    guard result.status == .skippedPermissionRequired else {
      return false
    }

    guard OnboardingFlowView.hasCompletedOnboarding else {
      return false
    }

    return !UserDefaults.standard.bool(forKey: PreferencesKeys.configurationAccessOnboardingPrompted)
  }
}
