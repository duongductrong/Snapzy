//
//  UpdaterManager.swift
//  Snapzy
//
//  Shared Sparkle updater manager - singleton to ensure updater is started once
//

import Sparkle

final class UpdaterManager {
  static let shared = UpdaterManager()

  let controller: SPUStandardUpdaterController

  var updater: SPUUpdater {
    controller.updater
  }

  private init() {
    controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  }

  func checkForUpdates() {
    updater.checkForUpdates()
  }
}
