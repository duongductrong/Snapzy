//
//  DiagnosticLogger.swift
//  Snapzy
//
//  Core logging engine — appends to daily .txt files in ~/Library/Logs/Snapzy/
//

import AppKit
import Foundation
import IOKit

final class DiagnosticLogger {
  static let shared = DiagnosticLogger()

  // MARK: - Configuration

  private let logDirectoryName = "Snapzy"
  private let filePrefix = "snapzy_"
  private let fileExtension = "txt"

  // MARK: - State

  private let writeQueue = DispatchQueue(label: "com.trongduong.snapzy.diagnosticlogger", qos: .utility)
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

  /// Log a diagnostic entry with source location and optional context.
  /// Backward-compatible: existing calls like `log(.info, .capture, "msg")` still compile.
  func log(
    _ level: DiagnosticLogLevel,
    _ category: DiagnosticLogCategory,
    _ message: String,
    context: [String: String]? = nil,
    file: String = #fileID,
    function: String = #function,
    line: Int = #line
  ) {
    guard isEnabled else { return }
    let entry = DiagnosticLogEntry(
      level: level,
      category: category,
      message: message,
      context: context,
      file: file,
      function: function,
      line: line
    )
    writeQueue.async { [weak self] in
      self?.writeEntry(entry)
    }
  }

  /// Convenience for logging errors — auto-extracts localizedDescription, NSError domain/code, and underlying error.
  func logError(
    _ category: DiagnosticLogCategory,
    _ error: Error,
    _ message: String = "",
    context: [String: String]? = nil,
    file: String = #fileID,
    function: String = #function,
    line: Int = #line
  ) {
    let nsError = error as NSError
    var ctx = context ?? [:]
    ctx["domain"] = nsError.domain
    ctx["code"] = String(nsError.code)
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
      ctx["underlying"] = underlying.localizedDescription
    }

    let prefix = message.isEmpty ? "" : "\(message): "
    log(
      .error,
      category,
      "\(prefix)\(error.localizedDescription)",
      context: ctx,
      file: file,
      function: function,
      line: line
    )
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

  private func logDateString(for date: Date) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = Calendar.current.timeZone
    return fmt.string(from: date)
  }

  private func logFileName(for date: Date) -> String {
    "\(filePrefix)\(logDateString(for: date)).\(fileExtension)"
  }

  private func ensureLogDirectory() {
    let fm = FileManager.default
    if !fm.fileExists(atPath: logDirectoryURL.path) {
      try? fm.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
    }
  }

  private func fileHandle(for date: Date) -> FileHandle? {
    let dateString = logDateString(for: date)

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

    // CPU architecture
    #if arch(arm64)
      let cpuArch = "arm64"
    #elseif arch(x86_64)
      let cpuArch = "x86_64"
    #else
      let cpuArch = "unknown"
    #endif

    // GPU model via IOKit
    let gpuModel = Self.queryGPUModel()

    // Available disk space
    let diskFree = Self.queryFreeDiskSpace()

    // Screens
    let screens = NSScreen.screens
    let screenInfo = screens.enumerated().map { _, screen in
      let size = screen.frame.size
      let scale = screen.backingScaleFactor
      return "\(Int(size.width))x\(Int(size.height))@\(Int(scale))x"
    }.joined(separator: ", ")

    // Thermal state
    let thermalState: String = {
      switch info.thermalState {
      case .nominal: return "nominal"
      case .fair: return "fair"
      case .serious: return "serious"
      case .critical: return "critical"
      @unknown default: return "unknown"
      }
    }()

    // Process ID
    let pid = info.processIdentifier

    // Locale
    let locale = Locale.current.identifier

    // Sandbox detection
    let isSandboxed = info.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    // Previous crash
    let didCrash = CrashSentinel.shared.didCrashLastSession

    let dateFmt = DateFormatter()
    dateFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let timestamp = dateFmt.string(from: now)

    let header = """
      === SESSION START \(timestamp) ===
      \(osString) | Snapzy \(appVersion) (\(buildNumber)) | \(cpuArch)
      \(memoryGB)GB RAM | \(gpuModel) | \(diskFree)
      \(screens.count) screen\(screens.count == 1 ? "" : "s") (\(screenInfo)) | PID \(pid)
      Locale: \(locale) | Thermal: \(thermalState) | Sandbox: \(isSandboxed ? "YES" : "NO")
      Previous crash: \(didCrash ? "YES" : "NO")
      ================================================\n
      """
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .joined(separator: "\n")

    if let data = header.data(using: .utf8) {
      handle.write(data)
    }
  }

  // MARK: - System Queries

  /// Query GPU model name via IOKit (no shell commands, cached by system)
  private static func queryGPUModel() -> String {
    let matchDict = IOServiceMatching("IOPCIDevice")
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator) == KERN_SUCCESS else {
      return "unknown GPU"
    }
    defer { IOObjectRelease(iterator) }

    var service = IOIteratorNext(iterator)
    while service != 0 {
      if let model = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() as? Data
      {
        let name = String(data: model, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
        if !name.isEmpty {
          IOObjectRelease(service)
          return name
        }
      }
      IOObjectRelease(service)
      service = IOIteratorNext(iterator)
    }

    // Fallback: Apple Silicon uses IOAccelerator
    var accelIterator: io_iterator_t = 0
    let accelDict = IOServiceMatching("IOAccelerator")
    if IOServiceGetMatchingServices(kIOMainPortDefault, accelDict, &accelIterator) == KERN_SUCCESS {
      defer { IOObjectRelease(accelIterator) }
      let accelService = IOIteratorNext(accelIterator)
      if accelService != 0 {
        if let props = IORegistryEntryCreateCFProperty(accelService, "IOClass" as CFString, kCFAllocatorDefault, 0)?
          .takeRetainedValue() as? String
        {
          IOObjectRelease(accelService)
          return props
        }
        IOObjectRelease(accelService)
      }
    }

    return "unknown GPU"
  }

  /// Query free disk space using FileManager (no shell commands)
  private static func queryFreeDiskSpace() -> String {
    do {
      let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
      if let freeBytes = attrs[.systemFreeSize] as? Int64 {
        let gb = Double(freeBytes) / (1024 * 1024 * 1024)
        return String(format: "%.1fGB free", gb)
      }
    } catch {}
    return "disk unknown"
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
