//
//  VideoEditorSpeedSegment.swift
//  Snapzy
//
//  Data model for speed (timelapse) segments in video timeline
//

import Foundation

/// Represents a playback-speed effect segment on the video timeline.
///
/// A speed segment time-scales a region of the recorded video: `rate > 1` plays the
/// region faster (timelapse / speed-up), `rate < 1` plays it slower (slow-motion).
/// Times are absolute seconds on the editor's structural timeline, matching
/// `ZoomSegment`; they do not follow a clip's source material after reorder.
nonisolated struct SpeedSegment: Identifiable, Codable, Equatable, Hashable {
  let id: UUID
  var startTime: TimeInterval // structural timeline seconds (absolute)
  var duration: TimeInterval // segment length in seconds
  var rate: Double // 0.25...8.0 (>1 faster, <1 slower)
  var isEnabled: Bool

  // MARK: - Computed Properties

  var endTime: TimeInterval {
    startTime + duration
  }

  // MARK: - Constants

  /// Quick-set presets shown in the rate picker.
  static let presets: [Double] = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
  static let minRate: Double = 0.25
  static let maxRate: Double = 8.0
  static let defaultRate: Double = 2.0
  static let minDuration: TimeInterval = 0.5
  static let maxDuration: TimeInterval = 864_000
  static let maxTimelineStart: TimeInterval = 864_000
  static let defaultDuration: TimeInterval = 3.0

  private enum CodingKeys: String, CodingKey {
    case id, startTime, duration, rate, isEnabled
  }

  // MARK: - Initialization

  init(
    id: UUID = UUID(),
    startTime: TimeInterval,
    duration: TimeInterval = SpeedSegment.defaultDuration,
    rate: Double = SpeedSegment.defaultRate,
    isEnabled: Bool = true
  ) {
    self.id = id
    let safeStart = startTime.isFinite ? startTime : 0
    self.startTime = min(max(0, safeStart), Self.maxTimelineStart)
    let safeDuration = duration.isFinite ? duration : Self.defaultDuration
    self.duration = min(max(Self.minDuration, safeDuration), Self.maxDuration)
    self.rate = Self.clampRate(rate)
    self.isEnabled = isEnabled
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let decodedId = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    let decodedStart = (try? c.decodeIfPresent(TimeInterval.self, forKey: .startTime)) ?? 0
    let decodedDuration = (try? c.decodeIfPresent(TimeInterval.self, forKey: .duration)) ?? Self.defaultDuration
    let decodedRate = (try? c.decodeIfPresent(Double.self, forKey: .rate)) ?? Self.defaultRate
    let decodedEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? true

    self.init(
      id: decodedId,
      startTime: decodedStart,
      duration: decodedDuration,
      rate: decodedRate,
      isEnabled: decodedEnabled
    )
  }

  // MARK: - Helpers

  /// Clamp an arbitrary rate into the supported range.
  static func clampRate(_ r: Double) -> Double {
    guard r.isFinite else { return defaultRate }
    return min(max(r, minRate), maxRate)
  }

  /// Check if a given time falls within this segment.
  func contains(time: TimeInterval) -> Bool {
    time >= startTime && time < endTime
  }

  /// Check if this segment overlaps with another (used by state-level no-overlap validation).
  func overlaps(with other: SpeedSegment) -> Bool {
    startTime < other.endTime && endTime > other.startTime
  }

  /// Clamp segment to the video duration.
  func clamped(to videoDuration: TimeInterval) -> SpeedSegment {
    var clamped = self
    clamped.startTime = max(0, min(startTime, videoDuration - Self.minDuration))
    clamped.duration = max(Self.minDuration, min(duration, videoDuration - clamped.startTime))
    return clamped
  }
}

// MARK: - Speed Segment Extensions

extension SpeedSegment {
  /// Create a speed segment centered at a specific time.
  static func centered(
    at time: TimeInterval,
    duration: TimeInterval = defaultDuration,
    rate: Double = defaultRate
  ) -> SpeedSegment {
    SpeedSegment(
      startTime: max(0, time - duration / 2),
      duration: duration,
      rate: rate
    )
  }

  /// Formatted rate string (e.g., "2x", "0.5x"), mirroring `ZoomSegment.formattedZoomLevel`.
  var formattedRate: String {
    if rate == floor(rate) {
      String(format: "%.0fx", rate)
    } else {
      String(format: "%.2gx", rate)
    }
  }

  /// Formatted duration string.
  var formattedDuration: String {
    if duration < 1 {
      String(format: "%.1fs", duration)
    } else if duration == floor(duration) {
      String(format: "%.0fs", duration)
    } else {
      String(format: "%.1fs", duration)
    }
  }
}
