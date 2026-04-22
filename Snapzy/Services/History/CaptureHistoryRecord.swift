//
//  CaptureHistoryRecord.swift
//  Snapzy
//
//  GRDB model for persisted capture history entries
//

import Foundation
import GRDB

/// Type of capture stored in history
enum CaptureHistoryType: String, Codable, Equatable, CaseIterable {
  case screenshot
  case video
  case gif

  var systemIconName: String {
    switch self {
    case .screenshot:
      return "photo"
    case .video:
      return "film"
    case .gif:
      return "photo.stack"
    }
  }
}

/// Record of a capture (screenshot, video, or GIF) persisted locally in history
struct CaptureHistoryRecord: Identifiable, Codable, Equatable, FetchableRecord, PersistableRecord {
  let id: UUID
  var filePath: String
  var fileName: String
  let captureType: CaptureHistoryType
  let fileSize: Int64
  let capturedAt: Date
  var width: Int?
  var height: Int?
  var duration: TimeInterval?
  var thumbnailPath: String?
  var isDeleted: Bool

  /// Human-readable file size
  var formattedFileSize: String {
    ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
  }

  /// Formatted capture date
  var formattedDate: String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: capturedAt)
  }

  /// Formatted duration string for display (e.g., "01:30s")
  var formattedDuration: String? {
    guard let duration = duration, duration.isFinite, duration >= 0 else {
      return nil
    }
    let mins = Int(duration) / 60
    let secs = Int(duration) % 60
    return String(format: "%02d:%02ds", mins, secs)
  }

  /// Local thumbnail URL in App Support, if the thumbnail file exists
  var thumbnailURL: URL? {
    guard let thumbnailPath = thumbnailPath else { return nil }
    let url = URL(fileURLWithPath: thumbnailPath)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  /// File URL from stored path
  var fileURL: URL {
    URL(fileURLWithPath: filePath)
  }

  /// Whether the underlying file still exists on disk
  var fileExists: Bool {
    FileManager.default.fileExists(atPath: filePath)
  }
}
