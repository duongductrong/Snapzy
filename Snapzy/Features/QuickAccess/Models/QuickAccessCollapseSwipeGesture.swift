//
//  QuickAccessCollapseSwipeGesture.swift
//  Snapzy
//
//  Two-finger swipes on Quick Access cards (#591): touch a card and move two
//  fingers down to tuck it into the screen edge; on a peeking card, move two
//  fingers up, or sideways back out of the edge, to bring it back. Pure so it
//  is unit tested.
//

import CoreGraphics
import Foundation

enum QuickAccessVerticalSwipeHelpers {
  static let minimumDelta: CGFloat = 0.5
  /// Vertical travel must beat horizontal by this ratio to claim the gesture,
  /// so diagonal motion keeps going to the existing horizontal swipe.
  static let dominanceRatio: CGFloat = 1.35

  /// Whether a scroll sample is a deliberate vertical trackpad move.
  static func isVerticalDominant(
    scrollingDeltaX deltaX: CGFloat,
    scrollingDeltaY deltaY: CGFloat,
    hasPreciseScrollingDeltas: Bool
  ) -> Bool {
    guard hasPreciseScrollingDeltas, deltaX.isFinite, deltaY.isFinite else { return false }
    return abs(deltaY) >= minimumDelta && abs(deltaY) > abs(deltaX) * dominanceRatio
  }

  /// Physical finger movement, positive when the fingers move down, whatever
  /// the user's scroll direction ("natural" scrolling inverts `scrollingDeltaY`).
  static func fingerDeltaY(
    scrollingDeltaY deltaY: CGFloat,
    isDirectionInvertedFromDevice: Bool
  ) -> CGFloat {
    guard deltaY.isFinite else { return 0 }
    return isDirectionInvertedFromDevice ? deltaY : -deltaY
  }

  static func isHorizontalDominant(
    scrollingDeltaX deltaX: CGFloat,
    scrollingDeltaY deltaY: CGFloat,
    hasPreciseScrollingDeltas: Bool
  ) -> Bool {
    guard hasPreciseScrollingDeltas, deltaX.isFinite, deltaY.isFinite else { return false }
    return abs(deltaX) >= minimumDelta && abs(deltaX) > abs(deltaY) * dominanceRatio
  }

  /// Physical finger movement, positive when the fingers move right.
  static func fingerDeltaX(
    scrollingDeltaX deltaX: CGFloat,
    isDirectionInvertedFromDevice: Bool
  ) -> CGFloat {
    guard deltaX.isFinite else { return 0 }
    return isDirectionInvertedFromDevice ? deltaX : -deltaX
  }

  /// Finger travel toward the screen interior from a card tucked into the
  /// left (`isLeftSide`) or right edge: the way back out of the edge.
  static func inwardDelta(fingerDeltaX: CGFloat, isLeftSide: Bool) -> CGFloat {
    isLeftSide ? fingerDeltaX : -fingerDeltaX
  }
}

/// Accumulates one vertical two-finger move.
struct QuickAccessVerticalSwipeTracker: Equatable {
  enum Update: Equatable {
    case changed(distance: CGFloat)
    case ended(distance: CGFloat, velocity: CGFloat)
    case cancelled
  }

  /// Total finger travel, positive downward.
  private(set) var distance: CGFloat = 0
  /// Latest finger velocity in points per second, positive downward.
  private(set) var velocity: CGFloat = 0
  private(set) var isTracking = false
  private var lastTimestamp: TimeInterval?

  mutating func begin(timestamp: TimeInterval) {
    distance = 0
    velocity = 0
    isTracking = true
    lastTimestamp = timestamp
  }

  mutating func add(fingerDelta: CGFloat, timestamp: TimeInterval) -> Update? {
    guard isTracking else { return nil }
    let delta = fingerDelta.isFinite ? fingerDelta : 0
    distance += delta
    if let lastTimestamp, timestamp > lastTimestamp {
      velocity = delta / CGFloat(timestamp - lastTimestamp)
    }
    lastTimestamp = timestamp
    return .changed(distance: distance)
  }

  /// Ends the move. A cancel (system interruption) never commits.
  mutating func finish(cancelled: Bool) -> Update? {
    guard isTracking else { return nil }
    let update: Update = cancelled ? .cancelled : .ended(distance: distance, velocity: velocity)
    reset()
    return update
  }

  mutating func reset() {
    distance = 0
    velocity = 0
    isTracking = false
    lastTimestamp = nil
  }
}

enum QuickAccessCollapseSwipePolicy {
  /// Finger travel that commits on release.
  static let commitDistance: CGFloat = 60
  /// A shorter flick commits when it is at least this fast.
  static let commitVelocity: CGFloat = 450
  /// A flick still has to travel this far, so a twitch never commits.
  static let minimumFlickDistance: CGFloat = 12
  /// Finger travel that maps to the end of the follow-the-fingers motion.
  static let fullTravel: CGFloat = 120

  /// 0...1 progress of a move down (collapse).
  static func collapseProgress(distance: CGFloat) -> CGFloat {
    clamp(distance / fullTravel)
  }

  /// 0...1 progress of a move up (restore).
  static func restoreProgress(distance: CGFloat) -> CGFloat {
    clamp(-distance / fullTravel)
  }

  static func shouldCollapse(distance: CGFloat, velocity: CGFloat) -> Bool {
    commits(travel: distance, speed: velocity)
  }

  static func shouldRestore(distance: CGFloat, velocity: CGFloat) -> Bool {
    commits(travel: -distance, speed: -velocity)
  }

  private static func commits(travel: CGFloat, speed: CGFloat) -> Bool {
    guard travel.isFinite, speed.isFinite else { return false }
    if travel >= commitDistance { return true }
    return travel >= minimumFlickDistance && speed >= commitVelocity
  }

  // MARK: Card motion while moving down

  /// Card scale at the end of the travel.
  static let collapsedScale: CGFloat = 0.9
  /// How far the card follows the fingers down (rubber-banded by the travel).
  static let maxDrop: CGFloat = 28
  /// How far the card drifts toward its edge at the end of the travel.
  static let edgeDrift: CGFloat = 24

  static func cardScale(progress: CGFloat) -> CGFloat {
    1 - (1 - collapsedScale) * clamp(progress)
  }

  static func cardDrop(progress: CGFloat) -> CGFloat {
    maxDrop * clamp(progress)
  }

  static func cardDrift(progress: CGFloat, edgeDirection: CGFloat) -> CGFloat {
    edgeDrift * clamp(progress) * edgeDirection
  }

  private static func clamp(_ value: CGFloat) -> CGFloat {
    guard value.isFinite else { return 0 }
    return min(1, max(0, value))
  }
}
