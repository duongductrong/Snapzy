//
//  AutomationFileOriginTracker.swift
//  Snapzy
//
//  Remembers files Snapzy itself just wrote (captures, Save to Folder, run
//  outputs) so a folder watch never fires on them: an automation saving into
//  the folder it watches would otherwise run forever. Thread-safe; entries
//  expire after `AutomationEventLimits.ownFileMemory`.
//

import Foundation

nonisolated final class AutomationFileOriginTracker: @unchecked Sendable {
  static let shared = AutomationFileOriginTracker()

  /// Upper bound so a long session never grows the table without limit.
  private static let maxEntries = 512

  private let lock = NSLock()
  private var written: [String: Date] = [:]
  private let memory: TimeInterval
  private let now: @Sendable () -> Date

  init(memory: TimeInterval = AutomationEventLimits.ownFileMemory, now: @escaping @Sendable () -> Date = { Date() }) {
    self.memory = memory
    self.now = now
  }

  func markWritten(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    let date = now()
    lock.lock()
    defer { lock.unlock() }
    for url in urls where url.isFileURL {
      written[Self.key(url)] = date
    }
    if written.count > Self.maxEntries {
      prune(before: date.addingTimeInterval(-memory))
      // Still full: forget the oldest half.
      if written.count > Self.maxEntries {
        let sorted = written.sorted { $0.value < $1.value }
        for (key, _) in sorted.prefix(written.count / 2) {
          written.removeValue(forKey: key)
        }
      }
    }
  }

  func wasWrittenBySnapzy(_ url: URL) -> Bool {
    let key = Self.key(url)
    let date = now()
    lock.lock()
    defer { lock.unlock() }
    guard let stamp = written[key] else { return false }
    if date.timeIntervalSince(stamp) > memory {
      written.removeValue(forKey: key)
      return false
    }
    return true
  }

  func reset() {
    lock.lock()
    written.removeAll()
    lock.unlock()
  }

  private func prune(before cutoff: Date) {
    written = written.filter { $0.value >= cutoff }
  }

  /// The parent folder is resolved, not the file: a destination is marked
  /// before it exists, and `resolvingSymlinksInPath` leaves a missing file
  /// (and so its symlinked parents) unresolved.
  private static func key(_ url: URL) -> String {
    let standardized = url.standardizedFileURL
    let folder = standardized.deletingLastPathComponent().resolvingSymlinksInPath().path
    return (folder as NSString).appendingPathComponent(standardized.lastPathComponent)
  }
}
