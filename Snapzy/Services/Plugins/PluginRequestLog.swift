import Foundation

/// One redacted request-log entry. A top-level type so UI can render it
/// without touching the log actor's isolation.
struct PluginRequestLogEntry: Identifiable, Equatable {
  let id = UUID()
  let timestamp: Date
  let pluginID: String
  let service: String
  /// A redacted, human-readable summary of what was asked.
  let summary: String
  let outcome: String
}

/// The accountability surface: every brokered host call lands here, redacted
/// at write time. If a plugin did something, it is in this log — attributable,
/// but never carrying a secret.
@PluginEngine
final class PluginRequestLog {
  static let shared = PluginRequestLog()

  static let capacity = 100

  private var entries: [PluginRequestLogEntry] = []

  func record(pluginID: String, service: String, summary: String, outcome: String) {
    entries.append(
      PluginRequestLogEntry(
        timestamp: Date(),
        pluginID: pluginID,
        service: service,
        summary: summary,
        outcome: outcome
      )
    )
    if entries.count > Self.capacity {
      entries.removeFirst(entries.count - Self.capacity)
    }
  }

  func recentEntries() -> [PluginRequestLogEntry] { entries }

  /// Redaction rules, applied at write time — a value is redacted or not
  /// logged, never stored raw.
  enum Redaction {
    /// Header names whose values are never logged.
    static let sensitiveHeaders: Set<String> = [
      "authorization", "proxy-authorization", "x-api-key", "api-key",
      "cookie", "set-cookie", "x-auth-token", "x-access-token",
    ]

    static func redactedHeaders(_ headers: [String: String]) -> [String: String] {
      headers.mapValues { _ in "<redacted>" }
    }

    static func safeHeaderKeys(_ headers: [String: String]) -> [String] {
      headers.keys.filter { !sensitiveHeaders.contains($0.lowercased()) }.sorted()
    }
  }
}
