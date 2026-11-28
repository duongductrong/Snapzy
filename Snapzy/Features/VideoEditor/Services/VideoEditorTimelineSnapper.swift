//
//  VideoEditorTimelineSnapper.swift
//  Snapzy
//
//  Magnetic snapping engine and lightweight guide state for timeline drag gestures.
//

import AppKit
import Combine
import Foundation

/// Pure magnetic snapping calculations for timeline edits.
nonisolated enum VideoEditorTimelineSnapper {
  enum TargetKind: Int, Equatable, Sendable, Comparable {
    case playhead = 0
    case clipBoundary = 1
    case timelineBoundary = 2
    case zoomEdge = 3
    case speedEdge = 4
    case captionEdge = 5
    case cameraEdge = 6
    case textEdge = 7

    static func < (lhs: TargetKind, rhs: TargetKind) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }

  struct SnapTarget: Equatable, Sendable {
    let time: TimeInterval
    let kind: TargetKind
  }

  struct SnapResult: Equatable, Sendable {
    let time: TimeInterval
    let target: SnapTarget?
  }

  struct RangeSnapResult: Equatable, Sendable {
    let start: TimeInterval
    let target: SnapTarget?
  }

  /// Screen-space magnetic pull radius in points. Feels crisp without feeling sticky.
  static let defaultThresholdPixels: CGFloat = 7

  /// Snap a single timeline edge or point to the nearest candidate within `thresholdPixels`.
  static func snap(
    time: TimeInterval,
    candidates: [SnapTarget],
    pixelsPerSecond: CGFloat,
    thresholdPixels: CGFloat = defaultThresholdPixels,
    isDisabled: Bool = false
  ) -> SnapResult {
    guard !isDisabled,
          !candidates.isEmpty,
          pixelsPerSecond > 0,
          thresholdPixels > 0,
          time.isFinite
    else {
      return SnapResult(time: time, target: nil)
    }

    let timeTolerance = TimeInterval(thresholdPixels / pixelsPerSecond)
    var bestTarget: SnapTarget?
    var bestDistance = TimeInterval.greatestFiniteMagnitude

    for candidate in candidates where candidate.time.isFinite {
      let distance = abs(candidate.time - time)
      guard distance <= timeTolerance else { continue }

      if let currentBest = bestTarget {
        if distance < bestDistance - 0.0001 {
          bestTarget = candidate
          bestDistance = distance
        } else if abs(distance - bestDistance) <= 0.0001, candidate.kind < currentBest.kind {
          bestTarget = candidate
          bestDistance = distance
        }
      } else {
        bestTarget = candidate
        bestDistance = distance
      }
    }

    if let bestTarget {
      return SnapResult(time: bestTarget.time, target: bestTarget)
    }
    return SnapResult(time: time, target: nil)
  }

  /// Snap a moving segment `[start, start + duration]` by testing both leading and trailing edges.
  static func snapRange(
    start: TimeInterval,
    duration: TimeInterval,
    candidates: [SnapTarget],
    pixelsPerSecond: CGFloat,
    thresholdPixels: CGFloat = defaultThresholdPixels,
    isDisabled: Bool = false
  ) -> RangeSnapResult {
    guard !isDisabled,
          duration >= 0,
          !candidates.isEmpty,
          pixelsPerSecond > 0,
          thresholdPixels > 0
    else {
      return RangeSnapResult(start: start, target: nil)
    }

    let leading = snap(
      time: start,
      candidates: candidates,
      pixelsPerSecond: pixelsPerSecond,
      thresholdPixels: thresholdPixels,
      isDisabled: false
    )
    let trailing = snap(
      time: start + duration,
      candidates: candidates,
      pixelsPerSecond: pixelsPerSecond,
      thresholdPixels: thresholdPixels,
      isDisabled: false
    )

    switch (leading.target, trailing.target) {
    case (nil, nil):
      return RangeSnapResult(start: start, target: nil)
    case (let leadTarget?, nil):
      return RangeSnapResult(start: leadTarget.time, target: leadTarget)
    case (nil, let trailTarget?):
      return RangeSnapResult(start: trailTarget.time - duration, target: trailTarget)
    case (let leadTarget?, let trailTarget?):
      let leadDistance = abs(leadTarget.time - start)
      let trailDistance = abs(trailTarget.time - (start + duration))
      if leadDistance < trailDistance - 0.0001 {
        return RangeSnapResult(start: leadTarget.time, target: leadTarget)
      }
      if trailDistance < leadDistance - 0.0001 {
        return RangeSnapResult(start: trailTarget.time - duration, target: trailTarget)
      }
      if leadTarget.kind <= trailTarget.kind {
        return RangeSnapResult(start: leadTarget.time, target: leadTarget)
      }
      return RangeSnapResult(start: trailTarget.time - duration, target: trailTarget)
    }
  }
}

/// Dedicated observable for the timeline's active magnetic snap guide line.
/// Kept separate from `VideoEditorState`'s main publisher so guide updates never
/// invalidate unrelated sidebar/player views during high-frequency drags.
@MainActor
final class VideoEditorTimelineSnapGuideState: ObservableObject {
  @Published private(set) var activeTarget: VideoEditorTimelineSnapper.SnapTarget?

  /// Explicit and nonisolated: avoids macOS 13-15 swift_task_deinitOnExecutor abort (#668).
  nonisolated deinit {}

  var activeTime: TimeInterval? {
    activeTarget?.time
  }

  /// Update the displayed snap target and emit a single subtle alignment haptic
  /// when locking onto a new target.
  func update(_ target: VideoEditorTimelineSnapper.SnapTarget?, emitHaptic: Bool = true) {
    guard activeTarget != target else { return }
    let didLockNewTarget = target != nil && activeTarget?.time != target?.time
    activeTarget = target
    if emitHaptic, didLockNewTarget {
      NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }
  }

  func clear() {
    guard activeTarget != nil else { return }
    activeTarget = nil
  }

  /// Returns true when the user holds Option (`⌥`) to temporarily bypass magnetic snapping.
  static var isBypassKeyPressed: Bool {
    NSEvent.modifierFlags.contains(.option)
  }
}
