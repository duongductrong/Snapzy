//
//  ZoomSegment.swift
//  Snapzy
//
//  Data model for zoom segments in video timeline
//

import Foundation

/// Represents a zoom effect segment on the video timeline
struct ZoomSegment: Identifiable, Codable, Equatable, Hashable {
  let id: UUID
  var startTime: TimeInterval      // seconds from video start
  var duration: TimeInterval       // zoom duration in seconds
  var zoomLevel: CGFloat           // 1.0 (100%) to 4.0 (400%)
  var zoomCenter: CGPoint          // normalized 0-1 for x,y position
  var zoomType: ZoomType
  var isEnabled: Bool

  // MARK: - Computed Properties

  var endTime: TimeInterval {
    startTime + duration
  }

  // MARK: - Constants

  static let defaultDuration: TimeInterval = 2.0
  static let defaultZoomLevel: CGFloat = 2.0
  static let minDuration: TimeInterval = 0.5
  static let maxDuration: TimeInterval = 30.0
  static let minZoomLevel: CGFloat = 1.0
  static let maxZoomLevel: CGFloat = 4.0

  // MARK: - Initialization

  init(
    id: UUID = UUID(),
    startTime: TimeInterval,
    duration: TimeInterval = ZoomSegment.defaultDuration,
    zoomLevel: CGFloat = ZoomSegment.defaultZoomLevel,
    zoomCenter: CGPoint = CGPoint(x: 0.5, y: 0.5),
    zoomType: ZoomType = .manual,
    isEnabled: Bool = true
  ) {
    self.id = id
    self.startTime = max(0, startTime)
    self.duration = max(Self.minDuration, min(duration, Self.maxDuration))
    self.zoomLevel = max(Self.minZoomLevel, min(zoomLevel, Self.maxZoomLevel))
    self.zoomCenter = CGPoint(
      x: max(0, min(zoomCenter.x, 1)),
      y: max(0, min(zoomCenter.y, 1))
    )
    self.zoomType = zoomType
    self.isEnabled = isEnabled
  }

  // MARK: - Validation

  /// Check if a given time falls within this zoom segment
  func contains(time: TimeInterval) -> Bool {
    time >= startTime && time < endTime
  }

  /// Check if this segment overlaps with another
  func overlaps(with other: ZoomSegment) -> Bool {
    startTime < other.endTime && endTime > other.startTime
  }

  /// Clamp segment to video duration
  func clamped(to videoDuration: TimeInterval) -> ZoomSegment {
    var clamped = self
    clamped.startTime = max(0, min(startTime, videoDuration - Self.minDuration))
    clamped.duration = min(duration, videoDuration - clamped.startTime)
    return clamped
  }
}

// MARK: - Zoom Type

enum ZoomType: String, Codable, CaseIterable {
  case auto    // generated from click detection during recording
  case manual  // user-defined zoom

  var displayName: String {
    switch self {
    case .auto: return "Auto"
    case .manual: return "Manual"
    }
  }

  var iconName: String {
    switch self {
    case .auto: return "cursorarrow.click"
    case .manual: return "hand.tap"
    }
  }
}

// MARK: - Zoom Segment Extensions

extension ZoomSegment {
  /// Create a zoom segment centered at a specific time
  static func centered(
    at time: TimeInterval,
    duration: TimeInterval = defaultDuration,
    zoomLevel: CGFloat = defaultZoomLevel,
    center: CGPoint = CGPoint(x: 0.5, y: 0.5),
    type: ZoomType = .manual
  ) -> ZoomSegment {
    ZoomSegment(
      startTime: max(0, time - duration / 2),
      duration: duration,
      zoomLevel: zoomLevel,
      zoomCenter: center,
      zoomType: type
    )
  }

  /// Formatted zoom level string (e.g., "2x", "1.5x")
  var formattedZoomLevel: String {
    if zoomLevel == floor(zoomLevel) {
      return String(format: "%.0fx", zoomLevel)
    } else {
      return String(format: "%.1fx", zoomLevel)
    }
  }

  /// Formatted duration string
  var formattedDuration: String {
    if duration < 1 {
      return String(format: "%.1fs", duration)
    } else if duration == floor(duration) {
      return String(format: "%.0fs", duration)
    } else {
      return String(format: "%.1fs", duration)
    }
  }
}
