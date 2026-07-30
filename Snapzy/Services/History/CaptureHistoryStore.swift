//
//  CaptureHistoryStore.swift
//  Snapzy
//
//  SQLite persistence for capture history records via GRDB
//

import Combine
import Foundation
import GRDB
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "CaptureHistoryStore")

extension Notification.Name {
  static let captureHistoryFileDidChange = Notification.Name("captureHistoryFileDidChange")
}

/// Manages persistent storage of capture history records using SQLite via GRDB
@MainActor
final class CaptureHistoryStore: ObservableObject {
  static let shared = CaptureHistoryStore()

  @Published private(set) var records: [CaptureHistoryRecord] = []

  var userDefaults: UserDefaults = .standard
  var isDatabaseAvailable: Bool {
    guard resolveDatabasePool(for: "check database availability") != nil else { return false }
    startObservation()
    return true
  }

  private var dbPool: DatabasePool?
  private var cancellable: AnyDatabaseCancellable?

  private init() {
    do {
      dbPool = try DatabaseManager.shared().dbPool
    } catch {
      dbPool = nil
      logger.error("Capture history disabled; database unavailable: \(error.localizedDescription)")
      DiagnosticLogger.shared.logError(.history, error, "Capture history database unavailable")
    }
    startObservation()
  }

  // MARK: - Reactive Observation

  /// Observe all records ordered by capturedAt desc.
  /// Updates `records` automatically whenever the database changes.
  private func startObservation() {
    guard cancellable == nil else { return }
    guard let dbPool = resolveDatabasePool(for: "start observation") else { return }

    let observation = ValueObservation.tracking { db in
      try CaptureHistoryRecord
        .order(Column("capturedAt").desc)
        .fetchAll(db)
    }
    if DatabaseManager.isRunningUnderXCTest {
      cancellable = observation.start(
        in: dbPool,
        scheduling: .immediate,
        onError: { error in
          logger.error("Database observation error: \(error.localizedDescription)")
          DiagnosticLogger.shared.logError(.history, error, "Capture history database observation failed")
        },
        onChange: { [weak self] newRecords in
          self?.records = newRecords
        }
      )
    } else {
      cancellable = observation.start(
        in: dbPool,
        scheduling: .async(onQueue: DispatchQueue.main),
        onError: { error in
          logger.error("Database observation error: \(error.localizedDescription)")
          DiagnosticLogger.shared.logError(.history, error, "Capture history database observation failed")
        },
        onChange: { [weak self] newRecords in
          self?.records = newRecords
        }
      )
    }
    DiagnosticLogger.shared.log(.debug, .history, "Capture history observation started")
  }

  // MARK: - Public API

  /// Add a new capture record.
  /// Respects the `historyEnabled` preference; no-op if disabled.
  func add(_ record: CaptureHistoryRecord) {
    guard let dbPool = requireDatabase(for: "add capture history record") else { return }

    guard userDefaults.snapzyHistoryEnabled else {
      logger.debug("History disabled, skipping record for \(record.fileName)")
      DiagnosticLogger.shared.log(
        .debug,
        .history,
        "Capture history add skipped; history disabled",
        context: ["fileName": record.fileName, "type": record.captureType.rawValue]
      )
      return
    }

    do {
      try dbPool.write { db in
        try record.insert(db)
      }
      logger.info("Capture history record added: \(record.fileName)")
      DiagnosticLogger.shared.log(
        .info,
        .history,
        "Capture history record added",
        context: [
          "fileName": record.fileName,
          "type": record.captureType.rawValue,
          "fileSize": "\(record.fileSize)",
        ]
      )
    } catch {
      logger.error("Failed to add capture history record: \(error.localizedDescription)")
      DiagnosticLogger.shared.logError(
        .history,
        error,
        "Capture history record add failed",
        context: ["fileName": record.fileName, "type": record.captureType.rawValue]
      )
    }
  }

  /// Remove a record by ID and delete its thumbnail if present
  func remove(id: UUID) {
    remove(ids: [id])
  }

  /// Remove multiple records by ID and delete their stored thumbnails if present
  func remove(ids: [UUID]) {
    let uniqueIds = Array(Set(ids))
    guard !uniqueIds.isEmpty else { return }
    guard let dbPool = requireDatabase(for: "remove capture history records") else { return }

    do {
      var thumbnailPaths: [String] = []
      var removedCount = 0

      try dbPool.write { db in
        for id in uniqueIds {
          if let thumbnailPath = try CaptureHistoryRecord.fetchOne(db, id: id)?.thumbnailPath {
            thumbnailPaths.append(thumbnailPath)
          }

          if try CaptureHistoryRecord.deleteOne(db, id: id) {
            removedCount += 1
          }
        }
      }

      // Clean up stored thumbnail files
      for thumbnailPath in thumbnailPaths {
        do {
          try FileManager.default.removeItem(atPath: thumbnailPath)
        } catch {
          DiagnosticLogger.shared.logError(
            .history,
            error,
            "Capture history thumbnail cleanup failed",
            context: ["fileName": (thumbnailPath as NSString).lastPathComponent]
          )
        }
      }

      if removedCount > 0 {
        refreshRecords()
        logger.info("Capture history records removed: \(removedCount)")
        DiagnosticLogger.shared.log(
          .info,
          .history,
          "Capture history records removed",
          context: ["recordCount": "\(removedCount)"]
        )
      }
    } catch {
      logger.error("Failed to remove capture history records: \(error.localizedDescription)")
      DiagnosticLogger.shared.logError(
        .history,
        error,
        "Capture history records remove failed",
        context: ["requestedCount": "\(uniqueIds.count)"]
      )
    }
  }

  /// Remove a record by file path (used when file is manually deleted)
  func removeByFilePath(_ filePath: String) {
    guard let dbPool = requireDatabase(for: "remove capture history record by file path") else { return }

    do {
      let thumbnailPaths = try dbPool.read { db in
        try CaptureHistoryRecord
          .filter(Column("filePath") == filePath)
          .fetchAll(db)
          .compactMap(\.thumbnailPath)
      }

      let count = try dbPool.write { db in
        try CaptureHistoryRecord
          .filter(Column("filePath") == filePath)
          .deleteAll(db)
      }

      for thumbnailPath in thumbnailPaths {
        do {
          try FileManager.default.removeItem(atPath: thumbnailPath)
        } catch {
          DiagnosticLogger.shared.logError(
            .history,
            error,
            "Capture history thumbnail cleanup failed",
            context: ["fileName": (thumbnailPath as NSString).lastPathComponent]
          )
        }
      }

      if count > 0 {
        logger.info("Removed history record for file: \(filePath)")
        DiagnosticLogger.shared.log(
          .info,
          .history,
          "Capture history record removed by file path",
          context: ["fileName": (filePath as NSString).lastPathComponent, "recordCount": "\(count)"]
        )
      }
    } catch {
      logger.error("Failed to remove record by path: \(error.localizedDescription)")
      DiagnosticLogger.shared.logError(
        .history,
        error,
        "Capture history remove by file path failed",
        context: ["fileName": (filePath as NSString).lastPathComponent]
      )
    }
  }

  /// Remove all records and clean up thumbnails
  @discardableResult
  func removeAll() -> Bool {
    guard let dbPool = requireDatabase(for: "remove all capture history records") else { return false }

    do {
      // Collect all thumbnail paths before deletion
      let thumbnailPaths: [String] = try dbPool.read { db in
        try CaptureHistoryRecord
          .fetchAll(db)
          .compactMap(\.thumbnailPath)
      }

      try dbPool.write { db in
        _ = try CaptureHistoryRecord.deleteAll(db)
      }

      // Clean up thumbnail files
      for path in thumbnailPaths {
        do {
          try FileManager.default.removeItem(atPath: path)
        } catch {
          DiagnosticLogger.shared.logError(
            .history,
            error,
            "Capture history thumbnail cleanup failed",
            context: ["fileName": (path as NSString).lastPathComponent]
          )
        }
      }

      logger.info("All capture history records removed")
      DiagnosticLogger.shared.log(
        .info,
        .history,
        "All capture history records removed",
        context: ["thumbnailCount": "\(thumbnailPaths.count)"]
      )
      return true
    } catch {
      logger.error("Failed to remove all records: \(error.localizedDescription)")
      DiagnosticLogger.shared.logError(.history, error, "Capture history remove all failed")
      return false
    }
  }

  /// Update the thumbnail path for a record
  func updateThumbnailPath(id: UUID, path: String?) {
    guard let dbPool = requireDatabase(for: "update capture history thumbnail path") else { return }

    do {
      try dbPool.write { db in
        if var record = try CaptureHistoryRecord.fetchOne(db, id: id) {
          record.thumbnailPath = path
          try record.update(db)
        }
      }
    } catch {
      logger.error("Failed to update thumbnail path: \(error.localizedDescription)")
      DiagnosticLogger.shared.logError(
        .history,
        error,
        "Capture history thumbnail path update failed",
        context: ["recordId": id.uuidString]
      )
    }
  }

  /// Update the file path for a record (e.g. after save-to-export moves the file)
  func updateFilePath(id: UUID, newPath: String) {
    guard let dbPool = requireDatabase(for: "update capture history file path") else { return }

    do {
      try dbPool.write { db in
        if var record = try CaptureHistoryRecord.fetchOne(db, id: id) {
          record.filePath = newPath
          record.fileName = (newPath as NSString).lastPathComponent
          try record.update(db)
        }
      }
      logger.info("Updated file path for record \(id): \(newPath)")
      DiagnosticLogger.shared.log(
        .info,
        .history,
        "Capture history file path updated",
        context: ["recordId": id.uuidString, "fileName": (newPath as NSString).lastPathComponent]
      )
    } catch {
      logger.error("Failed to update file path: \(error.localizedDescription)")
      DiagnosticLogger.shared.logError(
        .history,
        error,
        "Capture history file path update failed",
        context: ["recordId": id.uuidString, "fileName": (newPath as NSString).lastPathComponent]
      )
    }
  }

  /// Update matching record paths after a temp file is moved to a new location.
  @discardableResult
  func updateFilePath(from oldPath: String, to newPath: String) -> Int {
    guard let dbPool = requireDatabase(for: "update capture history file paths") else { return 0 }

    do {
      var updatedCount = 0
      try dbPool.write { db in
        let matchingRecords = try CaptureHistoryRecord
          .filter(Column("filePath") == oldPath)
          .fetchAll(db)

        for var record in matchingRecords {
          record.filePath = newPath
          record.fileName = (newPath as NSString).lastPathComponent
          try record.update(db)
          updatedCount += 1
        }
      }

      if updatedCount > 0 {
        logger.info("Updated \(updatedCount) history record path(s) from \(oldPath) to \(newPath)")
        DiagnosticLogger.shared.log(
          .info,
          .history,
          "Capture history file paths updated after move",
          context: [
            "recordCount": "\(updatedCount)",
            "oldFileName": (oldPath as NSString).lastPathComponent,
            "newFileName": (newPath as NSString).lastPathComponent,
          ]
        )
      }
      return updatedCount
    } catch {
      logger.error("Failed to update file path by old path: \(error.localizedDescription)")
      DiagnosticLogger.shared.logError(
        .history,
        error,
        "Capture history file path update after move failed",
        context: [
          "oldFileName": (oldPath as NSString).lastPathComponent,
          "newFileName": (newPath as NSString).lastPathComponent,
        ]
      )
      return 0
    }
  }

  /// Mark matching history rows stale after their backing file was overwritten.
  @discardableResult
  func markFileChanged(at url: URL) -> [UUID] {
    guard let dbPool = requireDatabase(for: "mark capture history file changed") else { return [] }

    let filePath = url.path
    let fileName = url.lastPathComponent
    let fileSize = currentFileSize(at: url)
    var updatedIds: [UUID] = []

    do {
      try dbPool.write { db in
        let matchingRecords = try CaptureHistoryRecord
          .filter(Column("filePath") == filePath)
          .fetchAll(db)

        for var record in matchingRecords {
          updatedIds.append(record.id)
          record.fileName = fileName
          record.fileSize = fileSize
          record.thumbnailPath = nil
          try record.update(db)
        }
      }

      guard !updatedIds.isEmpty else { return [] }

      for id in updatedIds {
        HistoryThumbnailGenerator.shared.deleteThumbnail(for: id)
      }

      NotificationCenter.default.post(
        name: .captureHistoryFileDidChange,
        object: self,
        userInfo: [
          "filePath": filePath,
          "recordIDs": updatedIds,
        ]
      )

      logger.info("Marked \(updatedIds.count) history thumbnail(s) stale for file: \(fileName)")
      DiagnosticLogger.shared.log(
        .info,
        .history,
        "Capture history records marked stale after file change",
        context: ["fileName": fileName, "recordCount": "\(updatedIds.count)"]
      )
      return updatedIds
    } catch {
      logger.error("Failed to mark history file changed: \(error.localizedDescription)")
      DiagnosticLogger.shared.logError(
        .history,
        error,
        "Capture history mark file changed failed",
        context: ["fileName": fileName]
      )
      return []
    }
  }

  /// Check whether an active history record exists for a given file path
  func hasRecord(forFilePath filePath: String) -> Bool {
    guard let dbPool = requireDatabase(for: "check capture history record existence") else { return false }

    do {
      let count = try dbPool.read { db in
        try CaptureHistoryRecord
          .filter(Column("filePath") == filePath)
          .fetchCount(db)
      }
      return count > 0
    } catch {
      logger.error("Failed to check record existence: \(error.localizedDescription)")
      DiagnosticLogger.shared.logError(
        .history,
        error,
        "Capture history record existence check failed",
        context: ["fileName": (filePath as NSString).lastPathComponent]
      )
      return false
    }
  }

  /// Remove records older than the given number of days.
  /// Pass 0 to skip age-based cleanup.
  func removeOlderThan(days: Int) {
    guard days > 0 else { return }
    guard let dbPool = requireDatabase(for: "remove old capture history records") else { return }

    let cutoff = Date().addingTimeInterval(-TimeInterval(days * 24 * 60 * 60))

    do {
      let count = try dbPool.write { db in
        try CaptureHistoryRecord
          .filter(Column("capturedAt") < cutoff)
          .deleteAll(db)
      }
      if count > 0 {
        logger.info("Removed \(count) record(s) older than \(days) days")
        DiagnosticLogger.shared.log(
          .info,
          .history,
          "Capture history age retention removed records",
          context: ["days": "\(days)", "recordCount": "\(count)"]
        )
      }
    } catch {
      logger.error("Failed to remove old records: \(error.localizedDescription)")
      DiagnosticLogger.shared.logError(
        .history,
        error,
        "Capture history age retention failed",
        context: ["days": "\(days)"]
      )
    }
  }

  /// If total record count exceeds `maxCount`, remove oldest records.
  /// Pass 0 to skip count-based cleanup.
  func trimToMaxCount(_ maxCount: Int) {
    guard maxCount > 0 else { return }
    guard let dbPool = requireDatabase(for: "trim capture history records") else { return }

    do {
      let total = try dbPool.read { db in
        try CaptureHistoryRecord.fetchCount(db)
      }

      guard total > maxCount else { return }
      let excess = total - maxCount

      let idsToDelete: [UUID] = try dbPool.read { db in
        try CaptureHistoryRecord
          .order(Column("capturedAt").asc)
          .limit(excess)
          .fetchAll(db)
          .map(\.id)
      }

      try dbPool.write { db in
        for id in idsToDelete {
          _ = try CaptureHistoryRecord.deleteOne(db, id: id)
        }
      }

      logger.info("Trimmed \(idsToDelete.count) oldest record(s) to stay within max count \(maxCount)")
      DiagnosticLogger.shared.log(
        .info,
        .history,
        "Capture history count retention trimmed records",
        context: ["maxCount": "\(maxCount)", "recordCount": "\(idsToDelete.count)"]
      )
    } catch {
      logger.error("Failed to trim records: \(error.localizedDescription)")
      DiagnosticLogger.shared.logError(
        .history,
        error,
        "Capture history count retention failed",
        context: ["maxCount": "\(maxCount)"]
      )
    }
  }

  /// Convenience: build and add a record from a capture URL
  func addCapture(
    url: URL,
    captureType: CaptureHistoryType,
    duration: TimeInterval? = nil,
    width: Int? = nil,
    height: Int? = nil
  ) {
    let fileSize: Int64
    do {
      let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
      fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
    } catch {
      fileSize = 0
      DiagnosticLogger.shared.logError(
        .history,
        error,
        "Capture history file attributes unavailable",
        context: ["fileName": url.lastPathComponent, "type": captureType.rawValue]
      )
    }

    let record = CaptureHistoryRecord(
      id: UUID(),
      filePath: url.path,
      fileName: url.lastPathComponent,
      captureType: captureType,
      fileSize: fileSize,
      capturedAt: Date(),
      width: width,
      height: height,
      duration: duration,
      thumbnailPath: nil,
      isDeleted: false
    )

    add(record)
  }

  /// Clear all thumbnail paths without deleting records
  func clearAllThumbnailPaths() {
    guard let dbPool = requireDatabase(for: "clear capture history thumbnail paths") else { return }

    do {
      let allRecords = try dbPool.read { db in
        try CaptureHistoryRecord.fetchAll(db)
      }
      try dbPool.write { db in
        for var record in allRecords {
          record.thumbnailPath = nil
          try record.update(db)
        }
      }
    } catch {
      logger.error("Failed to clear thumbnail paths: \(error.localizedDescription)")
      DiagnosticLogger.shared.logError(.history, error, "Capture history clear thumbnail paths failed")
    }
  }

  /// Most recent N records
  func recentRecords(limit: Int = 5) -> [CaptureHistoryRecord] {
    Array(records.prefix(limit))
  }

  func refreshRecords() {
    guard let dbPool = requireDatabase(for: "refresh capture history records") else { return }

    do {
      records = try dbPool.read { db in
        try CaptureHistoryRecord
          .order(Column("capturedAt").desc)
          .fetchAll(db)
      }
    } catch {
      logger.error("Failed to refresh capture history records: \(error.localizedDescription)")
      DiagnosticLogger.shared.logError(.history, error, "Capture history refresh failed")
    }
  }

  private func currentFileSize(at url: URL) -> Int64 {
    if let fileSize = fileSizeFromAttributes(at: url, logsFailure: false) {
      return fileSize
    }

    return SandboxFileAccessManager.shared.withScopedAccess(to: url) {
      fileSizeFromAttributes(at: url, logsFailure: true) ?? 0
    }
  }

  private func fileSizeFromAttributes(at url: URL, logsFailure: Bool) -> Int64? {
    do {
      let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
      return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    } catch {
      if logsFailure {
        DiagnosticLogger.shared.logError(
          .history,
          error,
          "Capture history current file size failed",
          context: ["fileName": url.lastPathComponent]
        )
      }
      return nil
    }
  }

  private func requireDatabase(for operation: String) -> DatabasePool? {
    guard let dbPool = resolveDatabasePool(for: operation) else { return nil }
    startObservation()
    return dbPool
  }

  private func resolveDatabasePool(for operation: String) -> DatabasePool? {
    if let dbPool {
      return dbPool
    }

    do {
      let manager = try DatabaseManager.shared()
      dbPool = manager.dbPool
      return manager.dbPool
    } catch {
      logger.error("Skipped \(operation); database unavailable: \(error.localizedDescription)")
      DiagnosticLogger.shared.log(
        .warning,
        .history,
        "Capture history operation skipped; database unavailable",
        context: ["operation": operation]
      )
      return nil
    }
  }
}
