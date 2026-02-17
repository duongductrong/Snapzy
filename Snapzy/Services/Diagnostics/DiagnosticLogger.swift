//
//  DiagnosticLogger.swift
//  Snapzy
//
//  Core logging engine — appends to daily .txt files in ~/Library/Logs/Snapzy/
//

import AppKit
import Foundation

final class DiagnosticLogger {
  static let shared = DiagnosticLogger()

  // MARK: - Configuration

  private let logDirectoryName = "Snapzy"
  private let filePrefix = "snapzy_"
  private let fileExtension = "txt"

  // MARK: - State

  private let writeQueue = DispatchQueue(label: "com.snapzy.diagnosticlogger", qos: .utility)
  private var currentFileHandle: FileHandle?
  private var currentDateString: String?
  private var hasWrittenSessionHeader = false

  private init() {}

  // MARK: - Public API

  var isEnabled: Bool {
    UserDefaults.standard.object(forKey: PreferencesKeys.diagnosticsEnabled) as? Bool ?? true
  }

  /// Start a new session — writes the system context header.
  func startSession() {
    guard isEnabled else { return }
    writeQueue.async { [weak self] in
      self?.writeSessionHeader()
    }
  }

  /// Log a diagnostic entry.
  func log(_ level: DiagnosticLogLevel, _ category: DiagnosticLogCategory, _ message: String) {
    guard isEnabled else { return }
    let entry = DiagnosticLogEntry(level: level, category: category, message: message)
    writeQueue.async { [weak self] in
      self?.writeEntry(entry)
    }
  }

  /// The directory where log files are stored.
  var logDirectoryURL: URL {
    let libraryLogs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
      .appendingPathComponent("Logs")
      .appendingPathComponent(logDirectoryName)
    return libraryLogs
  }

  /// Path to today's log file.
  var currentLogFileURL: URL {
    logDirectoryURL.appendingPathComponent(logFileName(for: Date()))
  }

  // MARK: - File Management

  private func logFileName(for date: Date) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    return "\(filePrefix)\(fmt.string(from: date)).\(fileExtension)"
  }

  private func ensureLogDirectory() {
    let fm = FileManager.default
    if !fm.fileExists(atPath: logDirectoryURL.path) {
      try? fm.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
    }
  }

  private func fileHandle(for date: Date) -> FileHandle? {
    let dateString = {
      let fmt = DateFormatter()
      fmt.dateFormat = "yyyy-MM-dd"
      return fmt.string(from: date)
    }()

    // Reuse handle if same day
    if dateString == currentDateString, let handle = currentFileHandle {
      return handle
    }

    // Close previous handle
    try? currentFileHandle?.close()
    currentFileHandle = nil

    ensureLogDirectory()

    let fileURL = logDirectoryURL.appendingPathComponent(logFileName(for: date))
    let fm = FileManager.default

    if !fm.fileExists(atPath: fileURL.path) {
      fm.createFile(atPath: fileURL.path, contents: nil)
    }

    guard let handle = try? FileHandle(forWritingTo: fileURL) else { return nil }
    handle.seekToEndOfFile()

    currentFileHandle = handle
    currentDateString = dateString
    return handle
  }

  // MARK: - Writing

  private func writeEntry(_ entry: DiagnosticLogEntry) {
    guard let handle = fileHandle(for: entry.timestamp) else { return }
    if let data = entry.toLogLine().data(using: .utf8) {
      handle.write(data)
    }
  }

  private func writeSessionHeader() {
    guard !hasWrittenSessionHeader else { return }
    hasWrittenSessionHeader = true

    let now = Date()
    guard let handle = fileHandle(for: now) else { return }

    let info = ProcessInfo.processInfo
    let osVersion = info.operatingSystemVersion
    let osString = "macOS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

    let memoryGB = info.physicalMemory / (1024 * 1024 * 1024)

    let screens = NSScreen.screens
    let screenInfo = screens.enumerated().map { index, screen in
      let size = screen.frame.size
      return "\(Int(size.width))x\(Int(size.height))"
    }.joined(separator: ", ")

    let dateFmt = DateFormatter()
    dateFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let timestamp = dateFmt.string(from: now)

    let header = "=== SESSION START \(timestamp) ===\n\(osString) | Snapzy \(appVersion) (\(buildNumber)) | \(memoryGB)GB RAM | \(screens.count) screen\(screens.count == 1 ? "" : "s") (\(screenInfo))\n================================================\n"

    if let data = header.data(using: .utf8) {
      handle.write(data)
    }
  }

  // MARK: - Cleanup

  /// Close any open file handles (call before cleanup).
  func closeHandles() {
    writeQueue.sync {
      try? currentFileHandle?.close()
      currentFileHandle = nil
      currentDateString = nil
    }
  }
}
