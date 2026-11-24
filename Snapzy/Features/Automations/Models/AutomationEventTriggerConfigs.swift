//
//  AutomationEventTriggerConfigs.swift
//  Snapzy
//
//  Settings of the event triggers (milestone 7): triggers that start a run by
//  themselves when something happens — a Snapzy capture is saved, another app
//  copies an image, a file lands in a watched folder. Every event hands files
//  to the run, so the automation's capture source is skipped.
//

import Foundation

/// Which standard captures fire a `captureSaved` trigger.
nonisolated enum AutomationCaptureEventKind: String, Codable, CaseIterable, Identifiable, Sendable {
  case screenshot
  case recording

  var id: String { rawValue }

  init(_ type: CaptureType) {
    switch type {
    case .screenshot: self = .screenshot
    case .recording: self = .recording
    }
  }
}

nonisolated struct AutomationCaptureEventConfig: Codable, Equatable, Sendable {
  /// Empty means nothing fires; the editor never stores it empty.
  var kinds: Set<AutomationCaptureEventKind>

  init(kinds: Set<AutomationCaptureEventKind> = [.screenshot]) {
    self.kinds = kinds
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // Unknown kinds (newer build) are dropped instead of failing the trigger.
    let raw = (try? container.decode([String].self, forKey: .kinds)) ?? [AutomationCaptureEventKind.screenshot.rawValue]
    kinds = Set(raw.compactMap(AutomationCaptureEventKind.init(rawValue:)))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    // Sorted so the stored JSON is stable.
    try container.encode(kinds.map(\.rawValue).sorted(), forKey: .kinds)
  }

  private enum CodingKeys: String, CodingKey {
    case kinds
  }
}

nonisolated struct AutomationFolderWatchConfig: Codable, Equatable, Sendable {
  /// `nil` until the user picks a folder (the trigger is then inactive).
  var folder: AutomationFolderRef?
  /// Last known path of the folder: shown in the editor, written to TOML and
  /// recipes, re-registered on import.
  var folderPath: String?

  init(folder: AutomationFolderRef? = nil, folderPath: String? = nil) {
    self.folder = folder
    self.folderPath = folderPath
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    folder = container.value(.folder, default: nil)
    folderPath = container.value(.folderPath, default: nil)
  }

  private enum CodingKeys: String, CodingKey {
    case folder, folderPath
  }
}

/// Limits shared by every event trigger. Kept in one place so tests and docs agree.
nonisolated enum AutomationEventLimits {
  /// Files waiting per automation; more are dropped (logged).
  static let maxPendingPerAutomation = 20
  /// Event runs allowed at the same time across all automations.
  static let maxConcurrentRuns = 2
  /// More event runs than this for one automation inside `burstWindow` pauses
  /// its events until it is edited (runaway loop guard).
  static let burstLimit = 30
  static let burstWindow: TimeInterval = 60
  /// How long a file Snapzy wrote is ignored by folder watches.
  static let ownFileMemory: TimeInterval = 600
  /// Clipboard poll interval (only `changeCount` is read).
  static let clipboardPollInterval: TimeInterval = 1
  /// Folder events are coalesced this long before the folder is listed.
  static let folderCoalesceDelay: TimeInterval = 0.4
  /// A new file must keep its size this long before it fires.
  static let folderStabilityDelay: TimeInterval = 0.6
  /// A file still growing after this long is given up (e.g. a stuck download).
  static let folderMaxSettleTime: TimeInterval = 600
  /// An empty new file is given up after this long.
  static let folderMaxEmptyTime: TimeInterval = 30
  /// Slowest rescan of files that are still settling.
  static let folderMaxRescanInterval: TimeInterval = 5
}
