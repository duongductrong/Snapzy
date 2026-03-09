//
//  AppCoordinator.swift
//  Snapzy
//
//  App lifecycle orchestration for startup, notifications, and shutdown.
//

import AppKit
import Combine
import Foundation

@MainActor
final class AppCoordinator {
  private let environment: AppEnvironment
  private var cancellables = Set<AnyCancellable>()
  private var observers: [NSObjectProtocol] = []

  init(environment: AppEnvironment) {
    self.environment = environment
  }

  func applicationDidFinishLaunching() {
    let didCrash = CrashSentinel.shared.checkAndReset()
    DiagnosticLogger.shared.startSession()
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
    observeInvalidLicenseAlert()
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

    let invalidatedObserver = NotificationCenter.default.addObserver(
      forName: .licenseInvalidated,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        SplashWindowController.shared.showLicenseActivation()
      }
    }

    observers.append(onboardingObserver)
    observers.append(invalidatedObserver)
  }

  private func observeInvalidLicenseAlert() {
    LicenseManager.shared.$showInvalidLicenseAlert
      .removeDuplicates()
      .filter { $0 }
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.showInvalidLicenseConfirmation()
      }
      .store(in: &cancellables)
  }

  private func showInvalidLicenseConfirmation() {
    let licenseManager = LicenseManager.shared

    let alert = NSAlert()
    alert.messageText = "License Invalid"
    alert.informativeText =
      "\(licenseManager.invalidLicenseMessage)\n\nYou can clear the license and activate a new one, or quit the app."
    alert.alertStyle = .critical
    alert.addButton(withTitle: "Reactivate License")
    alert.addButton(withTitle: "Quit App")

    switch alert.runModal() {
    case .alertFirstButtonReturn:
      licenseManager.confirmClearInvalidLicense()
    case .alertSecondButtonReturn:
      licenseManager.confirmQuitApp()
    default:
      break
    }
  }
}
