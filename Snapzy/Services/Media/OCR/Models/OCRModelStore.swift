//
//  OCRModelStore.swift
//  Snapzy
//
//  Tracks install state of downloadable OCR models and persists installs.
//

import Combine
import Foundation

/// Observable store for downloadable OCR model install state. Persists
/// installed catalog ids into `ocr.installedModels` (String array) — the
/// availability contract `OCRModelResolver` reads.
@MainActor
final class OCRModelStore: ObservableObject {
  static let shared = OCRModelStore()

  @Published private(set) var states: [String: OCRModelInstallState] = [:]

  private let defaults: UserDefaults
  private let fileManager: FileManager
  private let installRootURL: URL?
  private let downloadService: OCRModelDownloading
  private let catalog: OCRModelCatalog
  private var activeDownloads: [String: (task: Task<Void, Never>, token: UUID)] = [:]

  init(
    defaults: UserDefaults = .standard,
    fileManager: FileManager = .default,
    installRootURL: URL? = nil,
    downloadService: OCRModelDownloading = OCRModelDownloadService(),
    catalog: OCRModelCatalog? = nil
  ) {
    self.defaults = defaults
    self.fileManager = fileManager
    self.installRootURL = installRootURL ?? Self.defaultInstallRootURL(fileManager: fileManager)
    self.downloadService = downloadService
    self.catalog = catalog ?? .shared
    for id in installedIDs { states[id] = .installed }
  }

  // MARK: - Paths

  static func defaultInstallRootURL(fileManager: FileManager = .default) -> URL? {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
      .appendingPathComponent("Snapzy", isDirectory: true)
      .appendingPathComponent("OCRModels", isDirectory: true)
  }

  func installDirectory(for modelID: String) -> URL? {
    installRootURL?.appendingPathComponent(modelID, isDirectory: true)
  }

  func state(for modelID: String) -> OCRModelInstallState {
    states[modelID] ?? .notInstalled
  }

  // MARK: - Download

  /// Starts downloading a catalog model; no-op while downloading/installed.
  /// The guard runs synchronously, so duplicate invocations share the task.
  @discardableResult
  func download(modelID: String) -> Task<Void, Never> {
    if let task = activeDownloads[modelID]?.task { return task }
    guard !state(for: modelID).isInFlight, state(for: modelID) != .installed else { return Task {} }
    let token = UUID()
    let task = Task { await self.performDownload(modelID: modelID, token: token) }
    activeDownloads[modelID] = (task, token)
    return task
  }

  func cancelDownload(modelID: String) {
    activeDownloads[modelID]?.task.cancel()
  }

  private func performDownload(modelID: String, token: UUID) async {
    // Identity check: a stale task finishing late must not clear a newer one.
    defer {
      if activeDownloads[modelID]?.token == token { activeDownloads[modelID] = nil }
    }
    guard let definition = catalog.definition(for: modelID) else {
      states[modelID] = .failed(reason: "Unknown OCR model.")
      return
    }
    guard let installDirectory = installDirectory(for: modelID) else {
      states[modelID] = .failed(reason: "OCR model install directory unavailable.")
      return
    }
    states[modelID] = .downloading(progress: 0)
    do {
      try await downloadService.download(definition, to: installDirectory) { [weak self] fraction in
        Task { @MainActor in
          guard let self, fraction > 0 else { return }
          guard case .downloading(let current) = self.state(for: modelID), fraction > current else { return }
          self.states[modelID] = fraction >= 1 ? .verifying : .downloading(progress: fraction)
        }
      }
      // A cancel/remove landing in the verify/move window wins over the move.
      guard !Task.isCancelled, state(for: modelID) != .notInstalled else {
        try? fileManager.removeItem(at: installDirectory)
        states[modelID] = .notInstalled
        return
      }
      markInstalled(modelID: modelID)
    } catch OCRModelDownloadError.cancelled {
      states[modelID] = .notInstalled
    } catch {
      states[modelID] = .failed(reason: error.localizedDescription)
    }
  }

  // MARK: - Removal

  /// Deletes the model's install directory and unregisters the model.
  func removeModel(modelID: String) {
    cancelDownload(modelID: modelID)
    if let directory = installDirectory(for: modelID),
       fileManager.fileExists(atPath: directory.path) {
      do {
        try fileManager.removeItem(at: directory)
      } catch {
        DiagnosticLogger.shared.logError(.ocr, error, "OCR model removal failed")
      }
    }
    markMissing(modelID: modelID)
    resetSelectionIfNeeded(modelIDs: [modelID])
  }

  /// Removes installs invalidated by a user-catalog delete or metadata change.
  func invalidateCatalogModels(modelIDs: [String]) {
    for id in modelIDs {
      removeModel(modelID: id)
    }
  }

  /// Prunes a model from persisted installs without touching its files.
  func markMissing(modelID: String) {
    PPOCRSessionManager.shared.unload(modelID: modelID)
    persistInstalledIDs(installedIDs.filter { $0 != modelID })
    states[modelID] = .notInstalled
  }

  // MARK: - Validation

  /// Re-reads `ocr.installedModels` after an external rewrite (config import).
  func reloadFromDefaults() {
    validateInstalledModelsOnLaunch()
    for (id, state) in states where !state.isInFlight { states[id] = nil }
    for id in installedIDs { states[id] = .installed }
  }

  /// Prunes persisted installs whose files are missing on disk; resets the
  /// persisted selection to built-in when it referenced a pruned model.
  func validateInstalledModelsOnLaunch() {
    guard catalog.isAuthoritative else {
      DiagnosticLogger.shared.log(
        .warning,
        .ocr,
        "Skipped OCR install pruning because the model catalog is unavailable"
      )
      return
    }
    var validIDs: [String] = []
    var prunedIDs: [String] = []
    var seen = Set<String>()
    for id in installedIDs where !seen.contains(id) {
      seen.insert(id)
      if isInstallComplete(modelID: id) {
        validIDs.append(id)
      } else {
        prunedIDs.append(id)
      }
    }
    guard !prunedIDs.isEmpty else { return }

    persistInstalledIDs(validIDs)
    for id in prunedIDs {
      states[id] = .notInstalled
    }
    let rawSelection = defaults.string(forKey: PreferencesKeys.ocrSelectedModel) ?? ""
    if case .downloadable(let selectedID) = OCRModelSelection(persistedValue: rawSelection),
       prunedIDs.contains(selectedID) {
      defaults.set(OCRModelSelection.builtIn.persistedValue, forKey: PreferencesKeys.ocrSelectedModel)
    }
    DiagnosticLogger.shared.log(
      .warning,
      .ocr,
      "Pruned incomplete OCR model installs",
      context: ["models": prunedIDs.joined(separator: ",")]
    )
  }

  // MARK: - Persistence

  private var installedIDs: [String] {
    defaults.stringArray(forKey: PreferencesKeys.ocrInstalledModels) ?? []
  }

  private func persistInstalledIDs(_ ids: [String]) {
    defaults.set(ids, forKey: PreferencesKeys.ocrInstalledModels)
  }

  private func markInstalled(modelID: String) {
    if !installedIDs.contains(modelID) {
      persistInstalledIDs(installedIDs + [modelID])
    }
    states[modelID] = .installed
    DiagnosticLogger.shared.log(.info, .ocr, "OCR model installed", context: ["model": modelID])
  }

  private func isInstallComplete(modelID: String) -> Bool {
    guard let definition = catalog.definition(for: modelID),
          let directory = installDirectory(for: modelID) else { return false }
    return definition.files.allSatisfy {
      fileManager.fileExists(atPath: directory.appendingPathComponent($0.name).path)
    }
  }

  private func resetSelectionIfNeeded(modelIDs: [String]) {
    let rawSelection = defaults.string(forKey: PreferencesKeys.ocrSelectedModel) ?? ""
    guard case .downloadable(let selectedID) = OCRModelSelection(persistedValue: rawSelection),
          modelIDs.contains(selectedID)
    else { return }
    defaults.set(OCRModelSelection.builtIn.persistedValue, forKey: PreferencesKeys.ocrSelectedModel)
  }
}
