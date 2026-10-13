//
//  SandboxOffDataMigrationService.swift
//  Snapzy
//
//  One-time migration for users upgrading from App Sandbox builds.
//

import Foundation
import os.log

private let sandboxOffMigrationLogger = Logger(
  subsystem: "Snapzy",
  category: "SandboxOffMigration"
)

struct SandboxOffDataMigrationResult: Equatable {
  let didRun: Bool
  let copiedApplicationSupportItems: Int
  let skippedApplicationSupportItems: Int
  let errorSkippedApplicationSupportItems: Int
  let importedPreferenceKeys: Int
  let skippedPreferenceKeys: Int
  let copiedLogItems: Int

  static let skipped = SandboxOffDataMigrationResult(
    didRun: false,
    copiedApplicationSupportItems: 0,
    skippedApplicationSupportItems: 0,
    errorSkippedApplicationSupportItems: 0,
    importedPreferenceKeys: 0,
    skippedPreferenceKeys: 0,
    copiedLogItems: 0
  )
}

@MainActor
final class SandboxOffDataMigrationService {
  struct Configuration {
    var bundleIdentifier: String?
    var homeDirectory: URL
    var applicationSupportDirectory: URL
    var libraryDirectory: URL
    var userDefaults: UserDefaults
    var fileManager: FileManager
    var isRunningSandboxed: Bool

    static func live() -> Configuration? {
      guard
        let applicationSupportDirectory = FileManager.default.urls(
          for: .applicationSupportDirectory,
          in: .userDomainMask
        ).first,
        let libraryDirectory = FileManager.default.urls(
          for: .libraryDirectory,
          in: .userDomainMask
        ).first
      else {
        return nil
      }

      return Configuration(
        bundleIdentifier: Bundle.main.bundleIdentifier,
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
        applicationSupportDirectory: applicationSupportDirectory,
        libraryDirectory: libraryDirectory,
        userDefaults: .standard,
        fileManager: .default,
        isRunningSandboxed: ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
      )
    }
  }

  enum MigrationError: LocalizedError {
    case configurationUnavailable
    case missingBundleIdentifier

    var errorDescription: String? {
      switch self {
      case .configurationUnavailable:
        return "Could not resolve user Library paths for sandbox data migration."
      case .missingBundleIdentifier:
        return "Could not resolve Snapzy bundle identifier for sandbox data migration."
      }
    }
  }

  static let shared = SandboxOffDataMigrationService()

  private let configurationProvider: @MainActor @Sendable () -> Configuration?
  private let completedKey = PreferencesKeys.sandboxOffMigrationCompleted
  private let appSupportFolderName = "Snapzy"
  private let markerFileName = ".sandbox-off-migration-completed"

  init(configurationProvider: (@MainActor @Sendable () -> Configuration?)? = nil) {
    self.configurationProvider = configurationProvider ?? { Configuration.live() }
  }

  @discardableResult
  func runIfNeeded() throws -> SandboxOffDataMigrationResult {
    guard let configuration = configurationProvider() else {
      throw MigrationError.configurationUnavailable
    }

    guard !configuration.isRunningSandboxed else {
      return .skipped
    }

    guard !hasCompletedMigration(configuration) else {
      return .skipped
    }

    guard let bundleIdentifier = configuration.bundleIdentifier, !bundleIdentifier.isEmpty else {
      throw MigrationError.missingBundleIdentifier
    }

    let sourceDataDirectory = sandboxDataDirectory(
      homeDirectory: configuration.homeDirectory,
      bundleIdentifier: bundleIdentifier
    )
    guard configuration.fileManager.fileExists(atPath: sourceDataDirectory.path) else {
      markCompleted(configuration, sourceDataDirectory: sourceDataDirectory)
      return SandboxOffDataMigrationResult(
        didRun: true,
        copiedApplicationSupportItems: 0,
        skippedApplicationSupportItems: 0,
        errorSkippedApplicationSupportItems: 0,
        importedPreferenceKeys: 0,
        skippedPreferenceKeys: 0,
        copiedLogItems: 0
      )
    }

    var applicationSupportSummary = DirectoryMergeSummary()
    try mergeDirectoryIfPresent(
      from: sourceDataDirectory
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent(appSupportFolderName, isDirectory: true),
      to: destinationAppSupportDirectory(configuration),
      configuration: configuration,
      summary: &applicationSupportSummary
    )

    let preferencesSummary = migratePreferences(
      sourceDataDirectory: sourceDataDirectory,
      bundleIdentifier: bundleIdentifier,
      configuration: configuration
    )

    var logSummary = DirectoryMergeSummary()
    do {
      try mergeDirectoryIfPresent(
        from: sourceDataDirectory
          .appendingPathComponent("Library", isDirectory: true)
          .appendingPathComponent("Logs", isDirectory: true)
          .appendingPathComponent(appSupportFolderName, isDirectory: true),
        to: configuration.libraryDirectory
          .appendingPathComponent("Logs", isDirectory: true)
          .appendingPathComponent(appSupportFolderName, isDirectory: true),
        configuration: configuration,
        summary: &logSummary
      )
    } catch {
      sandboxOffMigrationLogger.warning(
        "Log migration skipped: \(error.localizedDescription, privacy: .public)"
      )
    }

    markCompleted(configuration, sourceDataDirectory: sourceDataDirectory)

    cleanupLegacySandboxData(
      sourceDataDirectory: sourceDataDirectory,
      bundleIdentifier: bundleIdentifier,
      configuration: configuration
    )

    let result = SandboxOffDataMigrationResult(
      didRun: true,
      copiedApplicationSupportItems: applicationSupportSummary.copiedItems,
      skippedApplicationSupportItems: applicationSupportSummary.skippedItems,
      errorSkippedApplicationSupportItems: applicationSupportSummary.errorSkippedItems,
      importedPreferenceKeys: preferencesSummary.importedKeys,
      skippedPreferenceKeys: preferencesSummary.skippedKeys,
      copiedLogItems: logSummary.copiedItems
    )
    sandboxOffMigrationLogger.info(
      "Sandbox data migration completed: appSupportCopied=\(result.copiedApplicationSupportItems), appSupportSkipped=\(result.skippedApplicationSupportItems), appSupportErrorSkipped=\(result.errorSkippedApplicationSupportItems), prefsImported=\(result.importedPreferenceKeys), logsCopied=\(result.copiedLogItems)"
    )
    return result
  }

  /// Marks migration as completed without copying any data.
  /// Used when user chooses "Start Fresh" after permission failures.
  /// Old container data is preserved (not deleted).
  func skipMigration() throws {
    guard let configuration = configurationProvider() else {
      throw MigrationError.configurationUnavailable
    }
    guard let bundleIdentifier = configuration.bundleIdentifier,
          !bundleIdentifier.isEmpty else {
      throw MigrationError.missingBundleIdentifier
    }

    let sourceDataDirectory = sandboxDataDirectory(
      homeDirectory: configuration.homeDirectory,
      bundleIdentifier: bundleIdentifier
    )

    sandboxOffMigrationLogger.info(
      "Migration skipped by user (Start Fresh). Old data preserved at: \(sourceDataDirectory.path, privacy: .public)"
    )

    markCompleted(configuration, sourceDataDirectory: sourceDataDirectory)
  }

  private struct DirectoryMergeSummary {
    var copiedItems = 0
    var skippedItems = 0
    var errorSkippedItems = 0
  }

  private struct PreferencesMigrationSummary {
    var importedKeys = 0
    var skippedKeys = 0
  }

  private func sandboxDataDirectory(homeDirectory: URL, bundleIdentifier: String) -> URL {
    homeDirectory
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Containers", isDirectory: true)
      .appendingPathComponent(bundleIdentifier, isDirectory: true)
      .appendingPathComponent("Data", isDirectory: true)
  }

  private func destinationAppSupportDirectory(_ configuration: Configuration) -> URL {
    configuration.applicationSupportDirectory
      .appendingPathComponent(appSupportFolderName, isDirectory: true)
  }

  private func markerFileURL(_ configuration: Configuration) -> URL {
    destinationAppSupportDirectory(configuration)
      .appendingPathComponent(markerFileName)
  }

  private func hasCompletedMigration(_ configuration: Configuration) -> Bool {
    configuration.userDefaults.bool(forKey: completedKey)
      || configuration.fileManager.fileExists(atPath: markerFileURL(configuration).path)
  }

  private func markCompleted(
    _ configuration: Configuration,
    sourceDataDirectory: URL
  ) {
    let destinationDirectory = destinationAppSupportDirectory(configuration)
    let markerURL = markerFileURL(configuration)
    let marker = """
      completedAt=\(ISO8601DateFormatter().string(from: Date()))
      source=\(sourceDataDirectory.path)
      """

    do {
      try configuration.fileManager.createDirectory(
        at: destinationDirectory,
        withIntermediateDirectories: true
      )
      try marker.write(to: markerURL, atomically: true, encoding: .utf8)
    } catch {
      sandboxOffMigrationLogger.error(
        "Sandbox migration marker write failed: \(error.localizedDescription, privacy: .public)"
      )
    }

    configuration.userDefaults.set(true, forKey: completedKey)
    configuration.userDefaults.synchronize()
  }

  private func mergeDirectoryIfPresent(
    from sourceDirectory: URL,
    to destinationDirectory: URL,
    configuration: Configuration,
    summary: inout DirectoryMergeSummary
  ) throws {
    let fileManager = configuration.fileManager
    guard fileManager.fileExists(atPath: sourceDirectory.path) else {
      return
    }

    try fileManager.createDirectory(
      at: destinationDirectory,
      withIntermediateDirectories: true
    )

    let sourceItems: [URL]
    do {
      sourceItems = try fileManager.contentsOfDirectory(
        at: sourceDirectory,
        includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
        options: []
      )
    } catch {
      if error.isPermissionDenied {
        sandboxOffMigrationLogger.warning(
          "Cannot list directory (permission denied), skipping: \(sourceDirectory.lastPathComponent, privacy: .public)"
        )
        summary.errorSkippedItems += 1
        return
      }
      throw error
    }

    for sourceItem in sourceItems {
      do {
        let destinationItem = destinationDirectory.appendingPathComponent(sourceItem.lastPathComponent)
        let values = try sourceItem.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let isDirectory = values.isDirectory == true && values.isSymbolicLink != true

        if isDirectory {
          if fileManager.fileExists(atPath: destinationItem.path) {
            var isDestinationDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: destinationItem.path, isDirectory: &isDestinationDirectory),
               isDestinationDirectory.boolValue {
              try mergeDirectoryIfPresent(
                from: sourceItem,
                to: destinationItem,
                configuration: configuration,
                summary: &summary
              )
            } else {
              summary.skippedItems += 1
            }
          } else {
            try mergeDirectoryIfPresent(
              from: sourceItem,
              to: destinationItem,
              configuration: configuration,
              summary: &summary
            )
          }
          continue
        }

        guard !fileManager.fileExists(atPath: destinationItem.path) else {
          summary.skippedItems += 1
          continue
        }

        try copyItemAtomically(
          from: sourceItem,
          to: destinationItem,
          fileManager: fileManager
        )
        summary.copiedItems += 1
      } catch {
        if error.isPermissionDenied {
          sandboxOffMigrationLogger.warning(
            "Skipping item (permission denied): \(sourceItem.lastPathComponent, privacy: .public)"
          )
        } else {
          sandboxOffMigrationLogger.error(
            "Skipping item (unexpected error): \(sourceItem.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)"
          )
        }
        summary.errorSkippedItems += 1
      }
    }
  }

  private func copyItemAtomically(
    from sourceURL: URL,
    to destinationURL: URL,
    fileManager: FileManager
  ) throws {
    try fileManager.createDirectory(
      at: destinationURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let temporaryURL = destinationURL.deletingLastPathComponent()
      .appendingPathComponent(".sandbox-migration-\(UUID().uuidString)-\(destinationURL.lastPathComponent)")
    try? fileManager.removeItem(at: temporaryURL)
    do {
      try fileManager.copyItem(at: sourceURL, to: temporaryURL)
      try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    } catch {
      try? fileManager.removeItem(at: temporaryURL)
      throw error
    }
  }

  private func migratePreferences(
    sourceDataDirectory: URL,
    bundleIdentifier: String,
    configuration: Configuration
  ) -> PreferencesMigrationSummary {
    let sourcePreferencesURL = sourceDataDirectory
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Preferences", isDirectory: true)
      .appendingPathComponent("\(bundleIdentifier).plist")

    guard
      configuration.fileManager.fileExists(atPath: sourcePreferencesURL.path),
      let sourcePreferences = NSDictionary(contentsOf: sourcePreferencesURL) as? [String: Any]
    else {
      return PreferencesMigrationSummary()
    }

    let destinationPreferencesURL = configuration.libraryDirectory
      .appendingPathComponent("Preferences", isDirectory: true)
      .appendingPathComponent("\(bundleIdentifier).plist")
    let shouldImportAllKeys = !configuration.fileManager.fileExists(atPath: destinationPreferencesURL.path)
    let existingPreferences = configuration.userDefaults.dictionaryRepresentation()

    var summary = PreferencesMigrationSummary()
    for (key, value) in sourcePreferences where key != completedKey {
      guard shouldImportAllKeys || existingPreferences[key] == nil else {
        summary.skippedKeys += 1
        continue
      }

      configuration.userDefaults.set(value, forKey: key)
      summary.importedKeys += 1
    }

    if summary.importedKeys > 0 {
      configuration.userDefaults.synchronize()
    }

    return summary
  }

  private func cleanupLegacySandboxData(
    sourceDataDirectory: URL,
    bundleIdentifier: String,
    configuration: Configuration
  ) {
    let fileManager = configuration.fileManager

    let sourceAppSupport = sourceDataDirectory
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Application Support", isDirectory: true)
      .appendingPathComponent(appSupportFolderName, isDirectory: true)

    let sourceLogs = sourceDataDirectory
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Logs", isDirectory: true)
      .appendingPathComponent(appSupportFolderName, isDirectory: true)

    let sourcePrefs = sourceDataDirectory
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Preferences", isDirectory: true)
      .appendingPathComponent("\(bundleIdentifier).plist")

    for url in [sourceAppSupport, sourceLogs, sourcePrefs] {
      guard fileManager.fileExists(atPath: url.path) else { continue }
      do {
        try fileManager.removeItem(at: url)
        sandboxOffMigrationLogger.info("Cleaned up legacy sandbox data at: \(url.lastPathComponent, privacy: .public)")
      } catch {
        sandboxOffMigrationLogger.error("Failed to clean up legacy data at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
      }
    }
  }
}
