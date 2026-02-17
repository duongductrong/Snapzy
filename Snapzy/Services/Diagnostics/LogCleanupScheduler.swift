//
//  LogCleanupScheduler.swift
//  Snapzy
//
//  Prunes log entries older than 2 hours and deletes old daily files
//

import Foundation

final class LogCleanupScheduler {
  static let shared = LogCleanupScheduler()

  private let ttlSeconds: TimeInterval = 2 * 60 * 60 // 2 hours
  private let cleanupInterval: TimeInterval = 30 * 60 // 30 minutes
  private var timer: Timer?

  private init() {}

  // MARK: - Scheduling

  func start() {
    // Run immediately on launch
    performCleanup()

    // Schedule periodic cleanup
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.timer?.invalidate()
      self.timer = Timer.scheduledTimer(
        withTimeInterval: self.cleanupInterval,
        repeats: true
      ) { [weak self] _ in
        self?.performCleanup()
      }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  // MARK: - Cleanup Logic

  private func performCleanup() {
    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let self else { return }
      self.pruneOldEntries()
      self.deleteOldFiles()
    }
  }

  /// Remove entries older than 2 hours from today's log file.
  private func pruneOldEntries() {
    let logger = DiagnosticLogger.shared
    let logFile = logger.currentLogFileURL
    let fm = FileManager.default

    guard fm.fileExists(atPath: logFile.path),
      let content = try? String(contentsOf: logFile, encoding: .utf8)
    else { return }

    let now = Date()
    let cutoff = now.addingTimeInterval(-ttlSeconds)
    let lines = content.components(separatedBy: "\n")

    var keptLines: [String] = []
    for line in lines {
      // Keep session headers (start with "===") and empty lines
      if line.hasPrefix("===") || line.hasPrefix("macOS ") || line.hasPrefix("===") || line.isEmpty {
        keptLines.append(line)
        continue
      }

      // Parse timestamp and check TTL
      if let entryTime = DiagnosticLogEntry.parseTimestamp(from: line, referenceDate: now) {
        if entryTime >= cutoff {
          keptLines.append(line)
        }
      } else {
        // Keep unparseable lines (context lines, etc.)
        keptLines.append(line)
      }
    }

    let pruned = keptLines.joined(separator: "\n")

    // Only rewrite if we actually removed something
    if pruned.count < content.count {
      // Close handles before rewriting
      logger.closeHandles()
      try? pruned.write(to: logFile, atomically: true, encoding: .utf8)
    }
  }

  /// Delete log files from previous days.
  private func deleteOldFiles() {
    let logger = DiagnosticLogger.shared
    let logDir = logger.logDirectoryURL
    let fm = FileManager.default
    let todayFileName = logger.currentLogFileURL.lastPathComponent

    guard let files = try? fm.contentsOfDirectory(atPath: logDir.path) else { return }

    for file in files {
      if file.hasPrefix("snapzy_") && file.hasSuffix(".txt") && file != todayFileName {
        let filePath = logDir.appendingPathComponent(file)
        try? fm.removeItem(at: filePath)
      }
    }
  }
}
