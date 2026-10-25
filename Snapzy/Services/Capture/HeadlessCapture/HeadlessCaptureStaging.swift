//
//  HeadlessCaptureStaging.swift
//  Snapzy
//
//  Where headless captures are written before a caller moves them. Kept
//  outside `Captures/` because `TempCaptureManager.cleanupOrphanedFiles()`
//  sweeps that tree at launch. Files older than 24 hours are removed.
//

import Foundation

nonisolated enum HeadlessCaptureStaging {
  static let retention: TimeInterval = 24 * 60 * 60

  static var directory: URL {
    let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return applicationSupport.appendingPathComponent("Snapzy/CLI/Captures", isDirectory: true)
  }

  /// Creates the directory (owner-only) and drops expired captures.
  static func prepare(in directory: URL = directory, now: Date = Date()) throws {
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    sweep(directory, now: now)
  }

  static func sweep(_ directory: URL = directory, now: Date = Date()) {
    let fileManager = FileManager.default
    guard let files = try? fileManager.contentsOfDirectory(
      at: directory,
      // Hidden files too: the post-processor's temp files outlive a crash.
      includingPropertiesForKeys: [.contentModificationDateKey]
    ) else { return }

    for file in files {
      let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
      if let modified, now.timeIntervalSince(modified) > retention {
        try? fileManager.removeItem(at: file)
      }
    }
  }

  /// `snapzy-cli-20261025-093012-a1b2c3`: sortable and predictable for agents,
  /// independent of the user's file-name template.
  static func makeFileName(now: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6).lowercased()
    return "snapzy-cli-\(formatter.string(from: now))-\(suffix)"
  }
}
