//
//  CaptureHistoryRetentionService.swift
//  Snapzy
//
//  Enforces retention policy for capture history (age and count limits)
//

import Foundation
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "CaptureHistoryRetentionService")

/// Enforces retention policies for capture history records
@MainActor
final class CaptureHistoryRetentionService {

  static let shared = CaptureHistoryRetentionService()

  private var timer: Timer?

  private init() {}

  // MARK: - Public API

  /// Start periodic retention sweeps (daily)
  func start() {
    // Run immediately on start
    Task { await sweep() }

    // Schedule daily sweep
    timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { _ in
      Task { @MainActor in
        await self.sweep()
      }
    }
  }

  /// Stop periodic sweeps
  func stop() {
    timer?.invalidate()
    timer = nil
  }

  /// Perform a single retention sweep based on current preferences
  func sweep() async {
    let defaults = UserDefaults.standard

    // Only sweep if history is enabled
    guard defaults.bool(forKey: PreferencesKeys.historyEnabled) else { return }

    let retentionDays = defaults.integer(forKey: PreferencesKeys.historyRetentionDays)
    let maxCount = defaults.integer(forKey: PreferencesKeys.historyMaxCount)

    logger.info("Starting retention sweep (days: \(retentionDays), maxCount: \(maxCount))")

    // Collect temp file paths before deleting records so we can clean them up afterward
    let tempPathsToDelete = collectTempFilePathsForRecordsToDelete(
      retentionDays: retentionDays,
      maxCount: maxCount
    )

    // Age-based cleanup
    if retentionDays > 0 {
      CaptureHistoryStore.shared.removeOlderThan(days: retentionDays)
    }

    // Count-based cleanup
    if maxCount > 0 {
      CaptureHistoryStore.shared.trimToMaxCount(maxCount)
    }

    // Delete associated temp files that are no longer referenced by any history record
    deleteUnreferencedTempFiles(paths: tempPathsToDelete)

    // Clean up orphaned thumbnails
    await cleanupOrphanedThumbnails()

    logger.info("Retention sweep completed")
  }

  /// Collect temp file paths for records that will be deleted by retention.
  /// Returns paths that are in the temp directory and will be removed.
  private func collectTempFilePathsForRecordsToDelete(
    retentionDays: Int,
    maxCount: Int
  ) -> [String] {
    let store = CaptureHistoryStore.shared
    let tempManager = TempCaptureManager.shared

    var pathsToDelete: [String] = []

    do {
      let allRecords = store.records

      // Find records older than retentionDays
      if retentionDays > 0 {
        let cutoff = Date().addingTimeInterval(-TimeInterval(retentionDays * 24 * 60 * 60))
        for record in allRecords where record.capturedAt < cutoff {
          if tempManager.isTempFile(record.fileURL) {
            pathsToDelete.append(record.filePath)
          }
        }
      }

      // Find records that would be trimmed by maxCount
      if maxCount > 0, allRecords.count > maxCount {
        let excess = allRecords.count - maxCount
        let oldestRecords = allRecords.suffix(excess)
        for record in oldestRecords {
          if tempManager.isTempFile(record.fileURL) && !pathsToDelete.contains(record.filePath) {
            pathsToDelete.append(record.filePath)
          }
        }
      }
    }

    return pathsToDelete
  }

  /// Delete temp files only if they are no longer referenced by any history record
  private func deleteUnreferencedTempFiles(paths: [String]) {
    let store = CaptureHistoryStore.shared
    let fm = FileManager.default

    for path in paths {
      // Only delete if no other history record references this file
      guard !store.hasRecord(forFilePath: path) else { continue }
      guard fm.fileExists(atPath: path) else { continue }

      do {
        try fm.removeItem(atPath: path)
        logger.debug("Deleted temp file after retention: \(path)")
      } catch {
        logger.error("Failed to delete temp file \(path): \(error.localizedDescription)")
      }
    }
  }

  /// Delete all history records and thumbnails, leaving capture files untouched
  func clearAllHistory() {
    CaptureHistoryStore.shared.removeAll()
    HistoryThumbnailGenerator.shared.clearAllThumbnails()
    logger.info("All history cleared by user request")
  }

  // MARK: - Private

  /// Remove thumbnails that no longer have a corresponding history record
  private func cleanupOrphanedThumbnails() async {
    let generator = HistoryThumbnailGenerator.shared
    let store = CaptureHistoryStore.shared

    let fm = FileManager.default
    let thumbsDir = generator.thumbnailsDirectory
    guard let contents = try? fm.contentsOfDirectory(at: thumbsDir, includingPropertiesForKeys: nil) else { return }

    let activeRecordIds = Set(store.records.map(\.id.uuidString))

    var removedCount = 0
    for url in contents {
      let filename = url.deletingPathExtension().lastPathComponent
      if !activeRecordIds.contains(filename) {
        try? fm.removeItem(at: url)
        removedCount += 1
      }
    }

    if removedCount > 0 {
      logger.info("Cleaned up \(removedCount) orphaned thumbnail(s)")
    }
  }
}
