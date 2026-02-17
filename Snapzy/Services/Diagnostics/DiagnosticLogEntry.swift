//
//  DiagnosticLogEntry.swift
//  Snapzy
//
//  Log entry model with compact text formatter
//

import Foundation

// MARK: - Log Level

enum DiagnosticLogLevel: String {
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
  case license = "LICENSE"
  case lifecycle = "LIFECYCLE"
}

// MARK: - Log Entry

struct DiagnosticLogEntry {
  let timestamp: Date
  let level: DiagnosticLogLevel
  let category: DiagnosticLogCategory
  let message: String

  init(
    level: DiagnosticLogLevel,
    category: DiagnosticLogCategory,
    message: String,
    timestamp: Date = Date()
  ) {
    self.timestamp = timestamp
    self.level = level
    self.category = category
    self.message = message
  }

  // MARK: - Formatting

  private static let timeFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm:ss"
    return fmt
  }()

  /// Compact single-line format: [14:32:05][INF][CAPTURE] Screenshot taken
  func toLogLine() -> String {
    let time = Self.timeFormatter.string(from: timestamp)
    return "[\(time)][\(level.rawValue)][\(category.rawValue)] \(message)\n"
  }

  /// Parse timestamp from a log line (for cleanup). Returns nil if unparseable.
  static func parseTimestamp(from line: String, referenceDate: Date) -> Date? {
    // Expected: [HH:mm:ss][...
    guard line.count >= 10,
      line.first == "[",
      let closeBracket = line.index(line.startIndex, offsetBy: 9, limitedBy: line.endIndex),
      line[closeBracket] == "]"
    else { return nil }

    let timeString = String(line[line.index(after: line.startIndex)..<closeBracket])
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm:ss"

    guard let timeParsed = fmt.date(from: timeString) else { return nil }

    // Combine with referenceDate's year/month/day
    let cal = Calendar.current
    var components = cal.dateComponents([.year, .month, .day], from: referenceDate)
    let timeComponents = cal.dateComponents([.hour, .minute, .second], from: timeParsed)
    components.hour = timeComponents.hour
    components.minute = timeComponents.minute
    components.second = timeComponents.second
    return cal.date(from: components)
  }
}
