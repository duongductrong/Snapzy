//
//  AutomationRunLog.swift
//  Snapzy
//
//  The Activity log: the last 100 runs with per-step timings, kept in
//  `Application Support/Snapzy/automation-runs.json`. No image data; text is
//  truncated to 200 characters. Can be turned off in Settings → Automations.
//

import Combine
import Foundation

nonisolated struct AutomationRunRecord: Codable, Identifiable, Equatable, Sendable {
  enum Outcome: String, Codable, Sendable {
    case succeeded
    /// A step failed but the run went on (failure policy "Continue").
    case partial
    case failed
    case cancelled
  }

  struct StepRecord: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
      case succeeded
      case failed
      case skipped
    }

    let kind: String
    let durationMs: Int
    let status: Status
    let error: String?
  }

  static let maxTextLength = 200

  /// The run id.
  let id: UUID
  let automationID: UUID
  let automationName: String
  let invocation: String
  let startedAt: Date
  let durationMs: Int
  let outcome: Outcome
  let steps: [StepRecord]
  let inputFiles: [String]
  let link: String?
  let text: String?
  let savedPaths: [String]
  let warnings: [String]

  init(
    id: UUID,
    automationID: UUID,
    automationName: String,
    invocation: String,
    startedAt: Date,
    durationMs: Int,
    outcome: Outcome,
    steps: [StepRecord],
    inputFiles: [String],
    link: String? = nil,
    text: String? = nil,
    savedPaths: [String] = [],
    warnings: [String] = []
  ) {
    self.id = id
    self.automationID = automationID
    self.automationName = automationName
    self.invocation = invocation
    self.startedAt = startedAt
    self.durationMs = durationMs
    self.outcome = outcome
    self.steps = steps
    self.inputFiles = inputFiles
    self.link = link
    self.text = text.map(Self.truncated)
    self.savedPaths = savedPaths
    self.warnings = warnings
  }

  static func truncated(_ text: String) -> String {
    text.count > maxTextLength ? String(text.prefix(maxTextLength)) + "…" : text
  }
}

@MainActor
final class AutomationRunLog: ObservableObject {
  static let shared = AutomationRunLog()
  static let capacity = 100

  @Published private(set) var records: [AutomationRunRecord] = []

  private let fileURL: URL
  private let defaults: UserDefaults
  private let writeDelay: UInt64
  private var pendingWrite: Task<Void, Never>?

  nonisolated deinit {}

  init(
    fileURL: URL = AutomationRunLog.defaultFileURL,
    defaults: UserDefaults = .standard,
    writeDelayNanoseconds: UInt64 = 500_000_000
  ) {
    self.fileURL = fileURL
    self.defaults = defaults
    writeDelay = writeDelayNanoseconds
    if let data = try? Data(contentsOf: fileURL),
       let decoded = try? Self.decoder.decode([AutomationRunRecord].self, from: data)
    {
      records = Array(decoded.prefix(Self.capacity))
    }
  }

  nonisolated static var defaultFileURL: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base
      .appendingPathComponent("Snapzy", isDirectory: true)
      .appendingPathComponent("automation-runs.json")
  }

  var isEnabled: Bool {
    defaults.object(forKey: PreferencesKeys.automationsActivityLogEnabled) as? Bool ?? true
  }

  /// Newest first; drops the oldest beyond `capacity`.
  func append(_ record: AutomationRunRecord) {
    guard isEnabled else { return }
    records.insert(record, at: 0)
    if records.count > Self.capacity {
      records.removeLast(records.count - Self.capacity)
    }
    scheduleWrite()
  }

  func clear() {
    records = []
    scheduleWrite()
  }

  /// Writes immediately (tests, app termination).
  func flush() {
    pendingWrite?.cancel()
    pendingWrite = nil
    write()
  }

  private func scheduleWrite() {
    pendingWrite?.cancel()
    pendingWrite = Task { @MainActor [weak self, writeDelay] in
      try? await Task.sleep(nanoseconds: writeDelay)
      guard !Task.isCancelled else { return }
      self?.write()
    }
  }

  private func write() {
    do {
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let data = try Self.encoder.encode(records)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      DiagnosticLogger.shared.logError(.action, error, "Automation activity log write failed")
    }
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}
