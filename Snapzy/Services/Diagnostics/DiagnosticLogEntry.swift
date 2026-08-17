//
//  DiagnosticLogEntry.swift
//  Snapzy
//
//  Log entry model with compact text formatter
//

import Foundation

// MARK: - Log Level

enum DiagnosticLogLevel: String {
  case debug = "DBG"
  case info = "INF"
  case warning = "WRN"
  case error = "ERR"
  case crash = "CRS"
}

// MARK: - Log Category

enum DiagnosticLogCategory: String {
  case system = "SYSTEM"
  case capture = "CAPTURE"
  case recording = "RECORDING"
  case editor = "EDITOR"
  case action = "ACTION"
  case ui = "UI"
  case lifecycle = "LIFECYCLE"
  case update = "UPDATE"
  case annotate = "ANNOTATE"
  case ocr = "OCR"
  case clipboard = "CLIPBOARD"
  case export = "EXPORT"
  case preferences = "PREFERENCES"
  case cloud = "CLOUD"
  case history = "HISTORY"
  case fileAccess = "FILE_ACCESS"
  case plugin = "PLUGIN"
}

// MARK: - Log Entry

nonisolated struct DiagnosticLogEntry {
  let timestamp: Date
  let level: DiagnosticLogLevel
  let category: DiagnosticLogCategory
  let message: String
  let file: String
  let function: String
  let line: Int
  let context: [String: String]?

  init(
    level: DiagnosticLogLevel,
    category: DiagnosticLogCategory,
    message: String,
    context: [String: String]? = nil,
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
    timestamp: Date = Date()
  ) {
    self.timestamp = timestamp
    self.level = level
    self.category = category
    self.message = message
    self.file = file
    self.function = function
    self.line = line
    self.context = context
  }

  // MARK: - Formatting

  private static let timeFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm:ss.SSS"
    return fmt
  }()

  /// Extract short filename from #fileID (e.g. "Snapzy/DiagnosticLogEntry.swift" → "DiagnosticLogEntry.swift")
  private var shortFileName: String {
    if let lastSlash = file.lastIndex(of: "/") {
      return String(file[file.index(after: lastSlash)...])
    }
    return file
  }

  /// Compact single-line format:
  /// [14:32:05.123][INF][CAPTURE][ScreenCaptureManager.swift:168:captureFullscreen] Screenshot taken {displayID=1, scale=2.0}
  func toLogLine() -> String {
    let time = Self.timeFormatter.string(from: timestamp)
    var result = "[\(time)][\(level.rawValue)][\(category.rawValue)][\(shortFileName):\(line):\(function)] \(message)"

    if let context, !context.isEmpty {
      let pairs = context.sorted(by: { $0.key < $1.key })
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: ", ")
      result += " {\(pairs)}"
    }

    return result + "\n"
  }

  /// Parse timestamp from a log line (for cleanup). Returns nil if unparseable.
  static func parseTimestamp(from line: String, referenceDate: Date) -> Date? {
    // Expected: [HH:mm:ss.SSS][ ... or legacy [HH:mm:ss][...
    guard line.count >= 10,
      line.first == "["
    else { return nil }

    // Find the closing bracket for the timestamp
    let startIndex = line.index(after: line.startIndex)
    guard let closeBracket = line.firstIndex(of: "]"), closeBracket > startIndex else { return nil }

    let timeString = String(line[startIndex..<closeBracket])

    // Try millisecond format first, then legacy
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm:ss.SSS"
    var timeParsed = fmt.date(from: timeString)

    if timeParsed == nil {
      fmt.dateFormat = "HH:mm:ss"
      timeParsed = fmt.date(from: timeString)
    }

    guard let parsed = timeParsed else { return nil }

    // Combine with referenceDate's year/month/day
    let cal = Calendar.current
    var components = cal.dateComponents([.year, .month, .day], from: referenceDate)
    let timeComponents = cal.dateComponents([.hour, .minute, .second], from: parsed)
    components.hour = timeComponents.hour
    components.minute = timeComponents.minute
    components.second = timeComponents.second
    return cal.date(from: components)
  }
}
