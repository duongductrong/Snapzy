//
//  LogCleanupScheduler.swift
//  Snapzy
//
//  Deletes diagnostic daily log files after the configured retention period.
//

import Foundation

final class LogCleanupScheduler {
  static let shared = LogCleanupScheduler()
  static let defaultRetentionDays = 3
  static let retentionDaysRange = 1...30

  private let cleanupInterval: TimeInterval = 30 * 60 // 30 minutes
  private var timer: Timer?

  private init() {}

  var retentionDays: Int {
    let defaults = UserDefaults.standard
    let storedValue = defaults.object(forKey: PreferencesKeys.diagnosticsRetentionDays) as? Int
      ?? Self.defaultRetentionDays
    return min(max(storedValue, Self.retentionDaysRange.lowerBound), Self.retentionDaysRange.upperBound)
  }

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

  func performCleanupNow() {
    performCleanup()
  }

  // MARK: - Cleanup Logic

  private func performCleanup() {
    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let self else { return }
      self.deleteOldFiles()
    }
  }

  /// Delete daily log files older than the configured retention window.
  private func deleteOldFiles() {
    let logger = DiagnosticLogger.shared
    let logDir = logger.logDirectoryURL
    let fm = FileManager.default

    guard let files = try? fm.contentsOfDirectory(atPath: logDir.path) else { return }

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let earliestKeptDay = calendar.date(
      byAdding: .day,
      value: -(retentionDays - 1),
      to: today
    ) ?? today

    for file in files {
      guard let fileDay = Self.date(fromLogFileName: file), fileDay < earliestKeptDay else { continue }
      let filePath = logDir.appendingPathComponent(file)
      try? fm.removeItem(at: filePath)
    }
  }

  private static func date(fromLogFileName fileName: String) -> Date? {
    guard fileName.hasPrefix("snapzy_"), fileName.hasSuffix(".txt") else { return nil }

    let start = fileName.index(fileName.startIndex, offsetBy: "snapzy_".count)
    let end = fileName.index(fileName.endIndex, offsetBy: -".txt".count)
    guard start < end else { return nil }

    let dateString = String(fileName[start..<end])
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = Calendar.current.timeZone
    formatter.isLenient = false
    return formatter.date(from: dateString).map { Calendar.current.startOfDay(for: $0) }
  }
}
