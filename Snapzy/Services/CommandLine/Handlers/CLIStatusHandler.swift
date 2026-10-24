//
//  CLIStatusHandler.swift
//  Snapzy
//
//  `system.status`: what a CLI caller needs to know before capturing. Never
//  prompts for permission.
//

import Foundation
import SnapzyCLIProtocol

nonisolated struct CLIStatusHandler: CLIRequestHandling {
  func handle(_: CLIEmpty, context _: CLIRequestContext) async throws -> CLIStatus {
    await Self.currentStatus()
  }

  @MainActor
  private static func currentStatus() async -> CLIStatus {
    let captureManager = ScreenCaptureManager.shared
    await captureManager.checkPermission()

    return CLIStatus(
      appVersion: CLIServer.appVersion,
      cliEnabled: CLIServer.shared.isRunning,
      onboardingCompleted: OnboardingFlowView.hasCompletedOnboarding,
      screenRecordingPermission: permission(
        for: captureManager.permissionStatus,
        requiresRelaunch: captureManager.requiresRelaunchToActivate
      ),
      // Caller authorization lands in plan phase 05.
      authorization: .undetermined
    )
  }

  /// Granted on disk but not yet active in this process (granted while Snapzy
  /// was running) is `unavailable`: capture still fails until a relaunch.
  static func permission(
    for status: ScreenRecordingPermissionStatus,
    requiresRelaunch: Bool
  ) -> CLIStatus.Permission {
    switch status {
    case .granted: requiresRelaunch ? .unavailable : .granted
    case .notGranted: .denied
    case .grantedButUnavailableDueToAppIdentity: .unavailable
    }
  }
}
