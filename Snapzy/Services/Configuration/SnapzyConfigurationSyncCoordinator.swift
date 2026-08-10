//
//  SnapzyConfigurationSyncCoordinator.swift
//  Snapzy
//
//  Debounced background sync from live app settings into config.toml.
//

import Combine
import Foundation

@MainActor
final class SnapzyConfigurationSyncCoordinator: ObservableObject {
  enum Status: Equatable {
    case idle
    case scheduled
    case syncing
    case upToDate(Date)
    case synced(Date)
    case needsPermission
    case conflict(URL)
    case failed(String)
  }

  enum Reason: String {
    case appLaunch
    case appTerminate
    case defaultsChanged
    case explicitChange
    case manual
    case openConfig
  }

  static let shared = SnapzyConfigurationSyncCoordinator()

  @Published private(set) var status: Status = .idle

  private let notificationCenter: NotificationCenter
  private let debounceInterval: TimeInterval
  private let syncManagedConfigIfSafe: @MainActor () throws -> SnapzyConfigurationSyncResult
  private let syncManagedConfigIfSafeInBackground: @MainActor () async throws -> SnapzyConfigurationSyncResult
  private let syncCurrentSettings: @MainActor (URL?, String?) throws -> URL
  private let currentSettingsSignature: @MainActor () -> String
  private var defaultsObserver: NSObjectProtocol?
  private var debounceTask: Task<Void, Never>?
  private var isStarted = false
  private var activeSyncCount = 0
  private var needsFollowUpSync = false
  private var lastAttemptedSettingsSignature: String?
  private var nextSyncSequence = 0
  private var latestStatusSequence = 0

  init(
    service: SnapzyConfigurationService,
    notificationCenter: NotificationCenter = .default,
    debounceInterval: TimeInterval = 1.2
  ) {
    self.notificationCenter = notificationCenter
    self.debounceInterval = debounceInterval
    self.syncManagedConfigIfSafe = {
      try service.syncManagedConfigIfSafe()
    }
    self.syncManagedConfigIfSafeInBackground = {
      try await service.syncManagedConfigIfSafeInBackground()
    }
    self.syncCurrentSettings = { url, expectedFileSignature in
      try service.syncManagedConfigToCurrentSettingsIfUnchanged(
        at: url,
        expectedFileSignature: expectedFileSignature
      )
    }
    self.currentSettingsSignature = {
      SnapzyConfigurationAutoImporter.contentSignature(for: service.exportTOML())
    }
  }

  convenience init(
    notificationCenter: NotificationCenter = .default,
    debounceInterval: TimeInterval = 1.2
  ) {
    self.init(
      service: SnapzyConfigurationService.shared,
      notificationCenter: notificationCenter,
      debounceInterval: debounceInterval
    )
  }

  init(
    notificationCenter: NotificationCenter = .default,
    debounceInterval: TimeInterval,
    syncManagedConfigIfSafe: @escaping @MainActor () throws -> SnapzyConfigurationSyncResult,
    syncManagedConfigIfSafeInBackground: (@MainActor () async throws -> SnapzyConfigurationSyncResult)? = nil,
    syncCurrentSettingsAfterConfirmation: @escaping @MainActor (URL?, String?) throws -> URL,
    currentSettingsSignature: @escaping @MainActor () -> String = { "" }
  ) {
    self.notificationCenter = notificationCenter
    self.debounceInterval = debounceInterval
    self.syncManagedConfigIfSafe = syncManagedConfigIfSafe
    if let syncManagedConfigIfSafeInBackground {
      self.syncManagedConfigIfSafeInBackground = syncManagedConfigIfSafeInBackground
    } else {
      self.syncManagedConfigIfSafeInBackground = {
        try syncManagedConfigIfSafe()
      }
    }
    self.syncCurrentSettings = syncCurrentSettingsAfterConfirmation
    self.currentSettingsSignature = currentSettingsSignature
  }

  func start() {
    guard !isStarted else { return }
    isStarted = true
    defaultsObserver = notificationCenter.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { [weak self] in
        await self?.scheduleSyncFromDefaultsChange()
      }
    }
  }

  func stop() {
    debounceTask?.cancel()
    debounceTask = nil
    if let defaultsObserver {
      notificationCenter.removeObserver(defaultsObserver)
    }
    defaultsObserver = nil
    isStarted = false
    activeSyncCount = 0
    needsFollowUpSync = false
    nextSyncSequence += 1
    latestStatusSequence = nextSyncSequence
    status = .idle
  }

  func scheduleSync(reason: Reason) {
    guard isStarted else { return }

    if isSyncing {
      needsFollowUpSync = true
      return
    }

    debounceTask?.cancel()
    status = .scheduled
    let delay = UInt64(debounceInterval * 1_000_000_000)
    debounceTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: delay)
      guard let self, !Task.isCancelled else { return }
      self.debounceTask = nil
      // A capture session is presenting: postpone rather than stall the selection
      // drag on a full main-thread TOML export + signature (~6-18ms per capture).
      // The re-armed debounce fires once the flow settles, so the sync is delayed,
      // never lost (and `flushPendingSync` still covers app terminate).
      if AreaSelectionController.shared.isPresenting {
        self.scheduleSync(reason: reason)
        return
      }
      // The unchanged-signature skip runs here — once after edits settle, never
      // per notification. The signature is a full TOML export + SHA256, so
      // computing it per UserDefaults change (e.g. every slider tick) stalls
      // the main thread (see issue #335).
      if reason == .defaultsChanged,
         let lastAttemptedSettingsSignature = self.lastAttemptedSettingsSignature,
         self.currentSettingsSignature() == lastAttemptedSettingsSignature {
        if self.status == .scheduled {
          self.status = .idle
        }
        return
      }
      do {
        try await self.syncNowInBackground(reason: reason)
      } catch {
        DiagnosticLogger.shared.logError(
          .preferences,
          error,
          "TOML configuration background sync failed"
        )
      }
    }
  }

  @discardableResult
  func flushPendingSync(reason: Reason) throws -> SnapzyConfigurationSyncResult? {
    guard debounceTask != nil || isSyncing || needsFollowUpSync else { return nil }
    return try syncNow(reason: reason)
  }

  func cancelPendingSync() {
    debounceTask?.cancel()
    debounceTask = nil
    if status == .scheduled, !isSyncing {
      status = .idle
    }
  }

  @discardableResult
  func syncNow(reason: Reason = .manual) throws -> SnapzyConfigurationSyncResult {
    cancelPendingSync()
    let sequence = beginSync()
    var syncResult: SnapzyConfigurationSyncResult?
    defer {
      finishSyncing(after: syncResult, sequence: sequence)
    }

    do {
      let result = try syncManagedConfigIfSafe()
      syncResult = result
      updateStatus(for: result, sequence: sequence)
      log(result, reason: reason)
      return result
    } catch {
      updateFailureStatus(error, sequence: sequence)
      throw error
    }
  }

  @discardableResult
  func syncNowInBackground(reason: Reason = .manual) async throws -> SnapzyConfigurationSyncResult {
    cancelPendingSync()
    let sequence = beginSync()

    do {
      let result = try await syncManagedConfigIfSafeInBackground()
      updateStatus(for: result, sequence: sequence)
      log(result, reason: reason)
      finishSyncing(after: result, sequence: sequence)
      return result
    } catch {
      updateFailureStatus(error, sequence: sequence)
      finishSyncing(after: nil, sequence: sequence)
      throw error
    }
  }

  @discardableResult
  func syncCurrentSettingsAfterConfirmation(
    at url: URL? = nil,
    expectedFileSignature: String? = nil
  ) throws -> URL {
    cancelPendingSync()
    let sequence = beginSync()
    var syncResult: SnapzyConfigurationSyncResult?
    defer {
      finishSyncing(after: syncResult, sequence: sequence)
    }

    do {
      let fileURL = try syncCurrentSettings(url, expectedFileSignature)
      let settingsSignature = currentSettingsSignature()
      let result = SnapzyConfigurationSyncResult(
        status: .synced,
        fileURL: fileURL,
        exportedSettingsSignature: settingsSignature
      )
      syncResult = result
      lastAttemptedSettingsSignature = settingsSignature
      updateStatus(for: result, sequence: sequence)
      DiagnosticLogger.shared.log(
        .info,
        .preferences,
        "TOML configuration sync confirmed",
        context: ["file": fileURL.path]
      )
      return fileURL
    } catch {
      updateFailureStatus(error, sequence: sequence)
      throw error
    }
  }

  private var isSyncing: Bool {
    activeSyncCount > 0
  }

  private func beginSync() -> Int {
    activeSyncCount += 1
    nextSyncSequence += 1
    status = .syncing
    return nextSyncSequence
  }

  private func updateStatus(for result: SnapzyConfigurationSyncResult, sequence: Int) {
    guard sequence >= latestStatusSequence else { return }
    latestStatusSequence = sequence
    lastAttemptedSettingsSignature = result.exportedSettingsSignature
    let now = Date()
    switch result.status {
    case .alreadyCurrent:
      status = .upToDate(now)
    case .synced:
      status = .synced(now)
    case .needsConfirmation:
      status = .conflict(result.fileURL)
    case .permissionRequired:
      status = .needsPermission
    }
  }

  private func scheduleSyncFromDefaultsChange() {
    scheduleSync(reason: .defaultsChanged)
  }

  private func updateFailureStatus(_ error: Error, sequence: Int) {
    guard sequence >= latestStatusSequence else { return }
    latestStatusSequence = sequence
    status = .failed(error.localizedDescription)
  }

  private func finishSyncing(after result: SnapzyConfigurationSyncResult?, sequence: Int) {
    activeSyncCount = max(0, activeSyncCount - 1)
    guard activeSyncCount == 0, needsFollowUpSync else { return }

    let syncedSignature = result?.exportedSettingsSignature
    let needsSync = syncedSignature == nil || currentSettingsSignature() != syncedSignature
    needsFollowUpSync = false
    if needsSync {
      scheduleSync(reason: .defaultsChanged)
    }
  }

  private func log(_ result: SnapzyConfigurationSyncResult, reason: Reason) {
    DiagnosticLogger.shared.log(
      .debug,
      .preferences,
      "TOML configuration sync checked",
      context: [
        "reason": reason.rawValue,
        "status": "\(result.status)",
        "file": result.fileURL.path,
      ]
    )
  }
}
