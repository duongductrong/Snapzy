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
  var userDefaults: UserDefaults = .standard
  var annotationSessionStore: AnnotationSessionStore = .shared

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
    DiagnosticLogger.shared.log(.info, .history, "Capture history retention service started")
  }

  /// Stop periodic sweeps
  func stop() {
    timer?.invalidate()
    timer = nil
    DiagnosticLogger.shared.log(.debug, .history, "Capture history retention service stopped")
  }

  /// Perform a single retention sweep based on current preferences
  func sweep() async {
    // Only sweep if history is enabled
    guard userDefaults.snapzyHistoryEnabled else {
      DiagnosticLogger.shared.log(.debug, .history, "Capture history retention sweep skipped; history disabled")
      return
    }
    guard CaptureHistoryStore.shared.isDatabaseAvailable else {
      DiagnosticLogger.shared.log(
        .warning,
        .history,
        "Capture history retention sweep skipped; database unavailable"
      )
      return
    }

    let retentionDays = userDefaults.integer(forKey: PreferencesKeys.historyRetentionDays)
    let maxCount = userDefaults.integer(forKey: PreferencesKeys.historyMaxCount)

    logger.info("Starting retention sweep (days: \(retentionDays), maxCount: \(maxCount))")
    DiagnosticLogger.shared.log(
      .info,
      .history,
      "Capture history retention sweep started",
      context: ["days": "\(retentionDays)", "maxCount": "\(maxCount)"]
    )

    // Collect temp file paths before deleting records so we can clean them up afterward
    let tempPathsToDelete = collectTempFilePathsForRecordsToDelete(
      retentionDays: retentionDays,
      maxCount: maxCount
    )
    DiagnosticLogger.shared.log(
      .debug,
      .history,
      "Capture history retention collected temp files",
      context: ["fileCount": "\(tempPathsToDelete.count)"]
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
    cleanupOrphanedAnnotationSessions()

    logger.info("Retention sweep completed")
    DiagnosticLogger.shared.log(
      .info,
      .history,
      "Capture history retention sweep completed",
      context: ["tempFileCandidates": "\(tempPathsToDelete.count)"]
    )
  }

  /// Collect temp file paths for records that will be deleted by retention.
  /// Returns paths that are in the temp directory and will be removed.
  private func collectTempFilePathsForRecordsToDelete(
    retentionDays: Int,
    maxCount: Int
  ) -> [String] {
    let store = CaptureHistoryStore.shared
    guard store.isDatabaseAvailable else { return [] }

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
          if tempManager.isTempFile(record.fileURL), !pathsToDelete.contains(record.filePath) {
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
    guard store.isDatabaseAvailable else { return }

    let fm = FileManager.default

    for path in paths {
      // Only delete if no other history record references this file
      guard !store.hasRecord(forFilePath: path) else { continue }
      guard fm.fileExists(atPath: path) else { continue }

      do {
        try fm.removeItem(atPath: path)
        logger.debug("Deleted temp file after retention: \(path)")
        DiagnosticLogger.shared.log(
          .debug,
          .history,
          "Capture history retention deleted temp file",
          context: ["fileName": (path as NSString).lastPathComponent]
        )
      } catch {
        logger.error("Failed to delete temp file \(path): \(error.localizedDescription)")
        DiagnosticLogger.shared.logError(
          .history,
          error,
          "Capture history retention temp file delete failed",
          context: ["fileName": (path as NSString).lastPathComponent]
        )
      }
    }
  }

  /// Delete all history records and thumbnails, leaving capture files untouched
  func clearAllHistory() {
    guard CaptureHistoryStore.shared.removeAll() else {
      logger.error("Clear all history skipped sidecar cleanup because database rows were not removed")
      DiagnosticLogger.shared.log(
        .warning,
        .history,
        "Clear all history skipped sidecar cleanup; database rows were not removed"
      )
      return
    }

    HistoryThumbnailGenerator.shared.clearAllThumbnails()
    annotationSessionStore.deleteAllSessions()
    logger.info("All history cleared by user request")
    DiagnosticLogger.shared.log(.info, .history, "All capture history cleared by user request")
  }

  // MARK: - Private

  /// Remove thumbnails that no longer have a corresponding history record
  private func cleanupOrphanedThumbnails() async {
    let generator = HistoryThumbnailGenerator.shared
    let store = CaptureHistoryStore.shared
    guard store.isDatabaseAvailable else {
      DiagnosticLogger.shared.log(
        .warning,
        .history,
        "Capture history orphan thumbnail cleanup skipped; database unavailable"
      )
      return
    }

    let fm = FileManager.default
    let thumbsDir = generator.thumbnailsDirectory
    let contents: [URL]
    do {
      contents = try fm.contentsOfDirectory(at: thumbsDir, includingPropertiesForKeys: nil)
    } catch {
      DiagnosticLogger.shared.logError(.history, error, "Capture history orphan thumbnail cleanup listing failed")
      return
    }

    let activeRecordIds = Set(store.records.map(\.id.uuidString))

    var removedCount = 0
    for url in contents {
      let filename = url.deletingPathExtension().lastPathComponent
      if !activeRecordIds.contains(filename) {
        do {
          try fm.removeItem(at: url)
          removedCount += 1
        } catch {
          DiagnosticLogger.shared.logError(
            .history,
            error,
            "Capture history orphan thumbnail delete failed",
            context: ["fileName": url.lastPathComponent]
          )
        }
      }
    }

    if removedCount > 0 {
      logger.info("Cleaned up \(removedCount) orphaned thumbnail(s)")
      DiagnosticLogger.shared.log(
        .info,
        .history,
        "Capture history orphan thumbnails cleaned",
        context: ["thumbnailCount": "\(removedCount)"]
      )
    }
  }

  private func cleanupOrphanedAnnotationSessions() {
    guard CaptureHistoryStore.shared.isDatabaseAvailable else {
      DiagnosticLogger.shared.log(
        .warning,
        .history,
        "Capture history annotation session cleanup skipped; database unavailable"
      )
      return
    }

    let activeScreenshotPaths = Set(
      CaptureHistoryStore.shared.records
        .filter { $0.captureType == .screenshot }
        .map(\.filePath)
    )
    annotationSessionStore.cleanup(keepingScreenshotFilePaths: activeScreenshotPaths)
  }
}
