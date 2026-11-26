//
//  VideoEditorTimelineTransition.swift
//  Snapzy
//
//  Video transition models for seams between abutting clips on the timeline
//  (Crossfade / Dip to Black) and resolved output-time descriptors for export.
//

import AVFoundation
import Foundation

/// Transition authored on the leading seam of a `TimelineClip` (between the
/// immediately preceding clip and this clip).
nonisolated struct TimelineClipTransition: Equatable, Hashable, Codable, Sendable {
  enum Style: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case none
    case crossfade
    case dipToBlack

    var displayName: String {
      switch self {
      case .none: L10n.VideoEditor.noneOption
      case .crossfade: L10n.VideoEditor.transitionCrossfade
      case .dipToBlack: L10n.VideoEditor.transitionDipToBlack
      }
    }

    var systemImage: String {
      switch self {
      case .none: "minus"
      case .crossfade: "square.split.2x1"
      case .dipToBlack: "circle.lefthalf.filled"
      }
    }
  }

  static let minDuration: TimeInterval = 0.15
  static let maxDuration: TimeInterval = 2.0
  static let defaultDuration: TimeInterval = 0.5
  static let presetDurations: [TimeInterval] = [0.3, 0.5, 0.8, 1.0]
  /// Maximum gap between two consecutive active clips treated as an abutting seam in UI and export.
  static let abuttingGapTolerance: TimeInterval = 0.02

  var style: Style
  var duration: TimeInterval

  init(style: Style, duration: TimeInterval = defaultDuration) {
    self.style = style
    self.duration = Self.clampedDuration(duration)
  }

  var isActive: Bool {
    style != .none && duration >= Self.minDuration - 0.0001
  }

  static func clampedDuration(_ value: TimeInterval) -> TimeInterval {
    guard value.isFinite else { return defaultDuration }
    return min(max(value, minDuration), maxDuration)
  }

  /// Clamp transition duration so it never consumes more than 45% of either abutting clip,
  /// guaranteeing adjacent seams can never collide with each other.
  static func effectiveDuration(
    requested: TimeInterval,
    outgoingClipDuration: TimeInterval,
    incomingClipDuration: TimeInterval
  ) -> TimeInterval {
    let maxAllowed = min(outgoingClipDuration, incomingClipDuration) * 0.45
    guard maxAllowed >= minDuration - 0.0001 else { return 0 }
    return min(clampedDuration(requested), maxAllowed)
  }
}

/// Resolved output-time video transition consumed by `ZoomVideoCompositorClass` during export.
nonisolated struct VideoEditorExportTransition: Equatable, Sendable {
  let style: TimelineClipTransition.Style
  /// Output time where the transition begins.
  let startTime: TimeInterval
  /// Output time of the nominal cut seam between outgoing and incoming clips.
  let cutTime: TimeInterval
  /// Output time where the transition ends.
  let endTime: TimeInterval
  /// Composition track carrying the outgoing clip.
  let outgoingTrackID: CMPersistentTrackID
  /// Composition track carrying the incoming clip.
  let incomingTrackID: CMPersistentTrackID

  var duration: TimeInterval {
    max(0, endTime - startTime)
  }

  func contains(_ outputTime: TimeInterval) -> Bool {
    duration > 0.001 && outputTime >= startTime && outputTime <= endTime
  }

  /// Normalized `[0, 1]` transition progress at `outputTime`.
  func progress(at outputTime: TimeInterval) -> Double {
    guard duration > 0.001 else { return 0 }
    return min(max((outputTime - startTime) / duration, 0), 1)
  }

  /// Smooth black opacity curve (`0 → 1 → 0`) for Dip to Black transitions.
  func dipBlackAlpha(at outputTime: TimeInterval) -> Double {
    let p = progress(at: outputTime)
    let curve = sin(p * .pi)
    return min(max(curve, 0), 1)
  }
}
