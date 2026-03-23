//
//  DatabaseManager.swift
//  Snapzy
//
//  Singleton managing the SQLite database connection and schema migrations via GRDB
//

import Foundation
import GRDB
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "DatabaseManager")

/// Manages the SQLite database connection and schema migrations
final class DatabaseManager: @unchecked Sendable {

  static let shared = DatabaseManager()

  let dbPool: DatabasePool

  private init() {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    let dir = appSupport.appendingPathComponent("Snapzy", isDirectory: true)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let dbPath = dir.appendingPathComponent("snapzy.db").path

    do {
      dbPool = try DatabasePool(path: dbPath)
      try Self.migrator.migrate(dbPool)
      logger.info("Database initialized at \(dbPath)")
    } catch {
      fatalError("DatabaseManager: failed to open database — \(error)")
    }
  }

  // MARK: - Migrations

  private static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()

    #if DEBUG
      // Speed up development by nuking the database when migrations change
      migrator.eraseDatabaseOnSchemaChange = true
    #endif

    migrator.registerMigration("v1_createCloudUploadRecords") { db in
      try db.create(table: "cloudUploadRecord") { t in
        t.column("id", .text).primaryKey()
        t.column("fileName", .text).notNull()
        t.column("publicURL", .text).notNull()
        t.column("key", .text).notNull()
        t.column("fileSize", .integer).notNull()
        t.column("uploadedAt", .datetime).notNull()
        t.column("providerType", .text).notNull()
        t.column("expireTime", .text).notNull()
        t.column("contentType", .text)
      }
      try db.create(
        index: "idx_cloudUploadRecord_uploadedAt",
        on: "cloudUploadRecord",
        columns: ["uploadedAt"]
      )
      try db.create(
        index: "idx_cloudUploadRecord_key",
        on: "cloudUploadRecord",
        columns: ["key"]
      )
    }

    return migrator
  }
}
