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

/// Manages persistent storage of capture history records using SQLite via GRDB
@MainActor
final class CaptureHistoryStore: ObservableObject {

  static let shared = CaptureHistoryStore()

  @Published private(set) var records: [CaptureHistoryRecord] = []

  private let dbPool: DatabasePool
  private var cancellable: AnyDatabaseCancellable?

  private init() {
    dbPool = DatabaseManager.shared.dbPool
    startObservation()
  }

  // MARK: - Reactive Observation

  /// Observe all records ordered by capturedAt desc.
  /// Updates `records` automatically whenever the database changes.
  private func startObservation() {
    let observation = ValueObservation.tracking { db in
      try CaptureHistoryRecord
        .order(Column("capturedAt").desc)
        .fetchAll(db)
    }
    cancellable = observation.start(
      in: dbPool,
      scheduling: .async(onQueue: DispatchQueue.main),
      onError: { error in
        logger.error("Database observation error: \(error.localizedDescription)")
      },
      onChange: { [weak self] newRecords in
        self?.records = newRecords
      }
    )
  }

  // MARK: - Public API

  /// Add a new capture record.
  /// Respects the `historyEnabled` preference; no-op if disabled.
  func add(_ record: CaptureHistoryRecord) {
    guard UserDefaults.standard.bool(forKey: PreferencesKeys.historyEnabled) else {
      logger.debug("History disabled, skipping record for \(record.fileName)")
      return
    }

    do {
      try dbPool.write { db in
        try record.insert(db)
      }
      logger.info("Capture history record added: \(record.fileName)")
    } catch {
      logger.error("Failed to add capture history record: \(error.localizedDescription)")
    }
  }

  /// Remove a record by ID and delete its thumbnail if present
  func remove(id: UUID) {
    do {
      let thumbnailPath = try dbPool.read { db in
        try CaptureHistoryRecord.fetchOne(db, id: id)?.thumbnailPath
      }

      try dbPool.write { db in
        _ = try CaptureHistoryRecord.deleteOne(db, id: id)
      }

      // Clean up thumbnail file
      if let thumbnailPath = thumbnailPath {
        try? FileManager.default.removeItem(atPath: thumbnailPath)
      }

      logger.info("Capture history record removed: \(id)")
    } catch {
      logger.error("Failed to remove capture history record: \(error.localizedDescription)")
    }
  }

  /// Remove a record by file path (used when file is manually deleted)
  func removeByFilePath(_ filePath: String) {
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
        try? FileManager.default.removeItem(atPath: thumbnailPath)
      }

      if count > 0 {
        logger.info("Removed history record for file: \(filePath)")
      }
    } catch {
      logger.error("Failed to remove record by path: \(error.localizedDescription)")
    }
  }

  /// Remove all records and clean up thumbnails
  func removeAll() {
    do {
      // Collect all thumbnail paths before deletion
      let thumbnailPaths: [String] = try dbPool.read { db in
        try CaptureHistoryRecord
          .select(Column("thumbnailPath"))
          .asRequest(of: String.self)
          .fetchAll(db)
          .compactMap { $0 }
      }

      try dbPool.write { db in
        _ = try CaptureHistoryRecord.deleteAll(db)
      }

      // Clean up thumbnail files
      for path in thumbnailPaths {
        try? FileManager.default.removeItem(atPath: path)
      }

      logger.info("All capture history records removed")
    } catch {
      logger.error("Failed to remove all records: \(error.localizedDescription)")
    }
  }

  /// Update the thumbnail path for a record
  func updateThumbnailPath(id: UUID, path: String?) {
    do {
      try dbPool.write { db in
        if var record = try CaptureHistoryRecord.fetchOne(db, id: id) {
          record.thumbnailPath = path
          try record.update(db)
        }
      }
    } catch {
      logger.error("Failed to update thumbnail path: \(error.localizedDescription)")
    }
  }

  /// Update the file path for a record (e.g. after save-to-export moves the file)
  func updateFilePath(id: UUID, newPath: String) {
    do {
      try dbPool.write { db in
        if var record = try CaptureHistoryRecord.fetchOne(db, id: id) {
          record.filePath = newPath
          record.fileName = (newPath as NSString).lastPathComponent
          try record.update(db)
        }
      }
      logger.info("Updated file path for record \(id): \(newPath)")
    } catch {
      logger.error("Failed to update file path: \(error.localizedDescription)")
    }
  }

  /// Update matching record paths after a temp file is moved to a new location.
  @discardableResult
  func updateFilePath(from oldPath: String, to newPath: String) -> Int {
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
      }
      return updatedCount
    } catch {
      logger.error("Failed to update file path by old path: \(error.localizedDescription)")
      return 0
    }
  }

  /// Check whether an active history record exists for a given file path
  func hasRecord(forFilePath filePath: String) -> Bool {
    do {
      let count = try dbPool.read { db in
        try CaptureHistoryRecord
          .filter(Column("filePath") == filePath)
          .fetchCount(db)
      }
      return count > 0
    } catch {
      logger.error("Failed to check record existence: \(error.localizedDescription)")
      return false
    }
  }

  /// Remove records older than the given number of days.
  /// Pass 0 to skip age-based cleanup.
  func removeOlderThan(days: Int) {
    guard days > 0 else { return }
    let cutoff = Date().addingTimeInterval(-TimeInterval(days * 24 * 60 * 60))

    do {
      let count = try dbPool.write { db in
        try CaptureHistoryRecord
          .filter(Column("capturedAt") < cutoff)
          .deleteAll(db)
      }
      if count > 0 {
        logger.info("Removed \(count) record(s) older than \(days) days")
      }
    } catch {
      logger.error("Failed to remove old records: \(error.localizedDescription)")
    }
  }

  /// If total record count exceeds `maxCount`, remove oldest records.
  /// Pass 0 to skip count-based cleanup.
  func trimToMaxCount(_ maxCount: Int) {
    guard maxCount > 0 else { return }

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
    } catch {
      logger.error("Failed to trim records: \(error.localizedDescription)")
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
    }
  }

  /// Most recent N records
  func recentRecords(limit: Int = 5) -> [CaptureHistoryRecord] {
    Array(records.prefix(limit))
  }
}
