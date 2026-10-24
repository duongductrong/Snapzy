//
//  CLIActivityIndicator.swift
//  Snapzy
//
//  Makes CLI captures visible: the menu bar icon is tinted while one runs,
//  and when the icon is hidden a toast names the app instead (at most once
//  per app every 30 seconds).
//

import Foundation

@MainActor
final class CLIActivityIndicator {
  static let shared = CLIActivityIndicator()

  static let toastInterval: TimeInterval = 30

  private var activeCaptures = 0
  private var lastToastByCaller: [String: Date] = [:]

  func begin(caller: CLICallerIdentity?, now: Date = Date()) {
    activeCaptures += 1
    let statusBar = AppStatusBarController.shared
    statusBar.setCLIActivity(true)

    let name = caller?.displayName ?? L10n.CommandLine.unknownApp
    DiagnosticLogger.shared.log(.info, .cli, "CLI capture started", context: ["caller": name])

    guard !statusBar.isStatusItemVisibleToUser, Self.shouldToast(
      lastShown: lastToastByCaller[caller?.key ?? ""],
      now: now
    ) else { return }
    lastToastByCaller[caller?.key ?? ""] = now
    AppToastManager.shared.show(message: L10n.CommandLine.captureToast(name), style: .info)
  }

  func end() {
    activeCaptures = max(0, activeCaptures - 1)
    if activeCaptures == 0 {
      AppStatusBarController.shared.setCLIActivity(false)
    }
  }

  nonisolated static func shouldToast(lastShown: Date?, now: Date) -> Bool {
    guard let lastShown else { return true }
    return now.timeIntervalSince(lastShown) >= toastInterval
  }
}
