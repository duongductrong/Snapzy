//
//  QuickAccessItem.swift
//  Snapzy
//
//  Data model for a captured item (screenshot or video) in the quick access stack
//

import AppKit
import Foundation

/// Type of quick access item
enum QuickAccessItemType: Equatable {
  case screenshot
  case video
}

/// Processing state for quick access item (annotation, conversion, etc.)
enum QuickAccessProcessingState: Equatable {
  case idle
  case processing(progress: Double?)  // nil = indeterminate
  case complete
  case failed

  var isProcessing: Bool {
    if case .processing = self { return true }
    return false
  }
}

/// Represents a single item (screenshot or video) in the quick access preview stack
struct QuickAccessItem: Identifiable, Equatable {
  let id: UUID
  let url: URL
  let thumbnail: NSImage
  let capturedAt: Date
  let itemType: QuickAccessItemType
  let duration: TimeInterval?
  var processingState: QuickAccessProcessingState = .idle
  /// Incremented when thumbnail changes — used by SwiftUI to detect visual updates
  let thumbnailVersion: UUID
  /// Cloud URL after successful upload (nil if not uploaded)
  var cloudURL: URL?
  /// Cloud object key for overwrite uploads (nil if not uploaded)
  var cloudKey: String?
  /// True when image has changed since last cloud upload (needs re-upload)
  var isCloudStale: Bool = false
  /// True when the item should remain visible and bypass auto-dismiss
  var isPinned: Bool = false
  /// True if the item's corresponding Pin or Edit window is currently open
  var isWindowOpen: Bool = false

  /// Initializer for screenshots (backward compatible)
  init(url: URL, thumbnail: NSImage) {
    self.id = UUID()
    self.url = url
    self.thumbnail = thumbnail
    self.capturedAt = Date()
    self.itemType = .screenshot
    self.duration = nil
    self.thumbnailVersion = UUID()
    self.cloudURL = nil
    self.cloudKey = nil
    self.isPinned = false
    self.isWindowOpen = false
  }

  /// Initializer for videos with duration
  init(url: URL, thumbnail: NSImage, duration: TimeInterval) {
    self.id = UUID()
    self.url = url
    self.thumbnail = thumbnail
    self.capturedAt = Date()
    self.itemType = .video
    self.duration = duration
    self.thumbnailVersion = UUID()
    self.cloudURL = nil
    self.cloudKey = nil
    self.isPinned = false
    self.isWindowOpen = false
  }

  /// Initializer with explicit id (used for thumbnail retry updates)
  init(id: UUID, url: URL, thumbnail: NSImage, capturedAt: Date, itemType: QuickAccessItemType, duration: TimeInterval?, thumbnailVersion: UUID = UUID(), cloudURL: URL? = nil, cloudKey: String? = nil, isCloudStale: Bool = false, isPinned: Bool = false, isWindowOpen: Bool = false) {
    self.id = id
    self.url = url
    self.thumbnail = thumbnail
    self.capturedAt = capturedAt
    self.itemType = itemType
    self.duration = duration
    self.thumbnailVersion = thumbnailVersion
    self.cloudURL = cloudURL
    self.cloudKey = cloudKey
    self.isCloudStale = isCloudStale
    self.isPinned = isPinned
    self.isWindowOpen = isWindowOpen
  }

  static func == (lhs: QuickAccessItem, rhs: QuickAccessItem) -> Bool {
    lhs.id == rhs.id && lhs.processingState == rhs.processingState && lhs.thumbnailVersion == rhs.thumbnailVersion && lhs.cloudURL == rhs.cloudURL && lhs.isCloudStale == rhs.isCloudStale && lhs.isPinned == rhs.isPinned && lhs.isWindowOpen == rhs.isWindowOpen
  }

  /// Whether this item is a video
  var isVideo: Bool {
    itemType == .video
  }

  /// Formatted duration string for display (e.g., "01:30s", "1:01:01s")
  var formattedDuration: String? {
    guard let duration = duration, duration.isFinite, duration >= 0 else {
      return nil
    }
    let totalSeconds = Int(duration)
    let hours = totalSeconds / 3600
    let mins = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02ds", hours, mins, secs)
    }
    return String(format: "%02d:%02ds", mins, secs)
  }
}
