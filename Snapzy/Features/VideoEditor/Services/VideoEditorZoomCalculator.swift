//
//  VideoEditorZoomCalculator.swift
//  Snapzy
//
//  Utility functions for zoom calculations and animations
//

import CoreGraphics
import Foundation

/// Utility enum for zoom-related calculations
nonisolated enum ZoomCalculator {
  // MARK: - Transition Configuration

  static let transitionDurationRange: ClosedRange<TimeInterval> = 0.15 ... 0.90
  static let defaultTransitionDuration: TimeInterval = 0.52
  static let fastTransitionDuration: TimeInterval = 0.30
  static let balancedTransitionDuration: TimeInterval = 0.52
  static let smoothTransitionDuration: TimeInterval = 0.72
  static let legacyFastTransitionDuration: TimeInterval = 0.25
  static let legacyBalancedTransitionDuration: TimeInterval = 0.40
  static let legacySmoothTransitionDuration: TimeInterval = 0.60
  static let neutralCenter: CGPoint = .init(x: 0.5, y: 0.5)

  /// Snaps legacy persisted transition presets (`0.25 / 0.40 / 0.60`) to the updated
  /// Fast / Balanced / Smooth preset values so existing users keep their selected preset highlighted.
  static func migrateLegacyTransitionDuration(_ stored: TimeInterval) -> TimeInterval {
    if abs(stored - legacyFastTransitionDuration) < 0.01 {
      return fastTransitionDuration
    }
    if abs(stored - legacyBalancedTransitionDuration) < 0.01 {
      return balancedTransitionDuration
    }
    if abs(stored - legacySmoothTransitionDuration) < 0.01 {
      return smoothTransitionDuration
    }
    return clampTransitionDuration(stored)
  }

  // MARK: - Crop Rect Calculation

  /// Calculate the crop rectangle for a given zoom level and center point
  /// - Parameters:
  ///   - center: Normalized center point (0-1 for x and y)
  ///   - zoomLevel: Zoom multiplier (1.0 = no zoom, 2.0 = 2x zoom)
  ///   - frameSize: Original frame size
  /// - Returns: The crop rectangle in frame coordinates
  static func calculateCropRect(
    center: CGPoint,
    zoomLevel: CGFloat,
    frameSize: CGSize
  ) -> CGRect {
    guard zoomLevel > 1.0 else {
      return CGRect(origin: .zero, size: frameSize)
    }

    // Calculate cropped size (inverse of zoom)
    let cropWidth = frameSize.width / zoomLevel
    let cropHeight = frameSize.height / zoomLevel

    // Calculate origin based on center, clamped to frame bounds
    let maxOriginX = frameSize.width - cropWidth
    let maxOriginY = frameSize.height - cropHeight

    // Flip Y for CoreImage coordinate system (origin at bottom-left, Y increases upward)
    // SwiftUI uses top-left origin where Y increases downward
    let flippedCenterY = 1.0 - center.y

    let originX = max(0, min((center.x * frameSize.width) - (cropWidth / 2), maxOriginX))
    let originY = max(0, min((flippedCenterY * frameSize.height) - (cropHeight / 2), maxOriginY))

    return CGRect(x: originX, y: originY, width: cropWidth, height: cropHeight)
  }

  // MARK: - Easing Functions

  /// C²-continuous quintic smootherstep (zero velocity AND zero acceleration at both ends).
  static func smootherstep(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    return x * x * x * (x * (x * 6 - 15) + 10)
  }

  /// Cinema magnetic zoom-in curve: decisive acceleration into a long, silky critically-damped settle.
  /// C²-smooth at both endpoints so shutter-angle motion blur ramps cleanly without flicker.
  static func cinemaEaseIn(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    // Warp time slightly toward early arrival, then apply C² smootherstep.
    let warped = 1.0 - pow(1.0 - x, 1.38)
    return smootherstep(warped)
  }

  /// Cinema calm zoom-out curve: gentle release into steady spatial reveal.
  static func cinemaEaseOut(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    let warped = pow(x, 0.92)
    return smootherstep(warped)
  }

  /// Cubic ease-in-out for smooth zoom transitions
  static func easeInOutCubic(_ t: Double) -> Double {
    t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
  }

  /// Quadratic ease-in-out (faster than cubic)
  static func easeInOutQuad(_ t: Double) -> Double {
    t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
  }

  /// Linear interpolation (no easing)
  static func linear(_ t: Double) -> Double {
    t
  }

  static func clampTransitionDuration(_ value: TimeInterval) -> TimeInterval {
    min(max(value, transitionDurationRange.lowerBound), transitionDurationRange.upperBound)
  }

  /// Interpolates zoom level optically in reciprocal viewport-width space (`1 / zoom`) so
  /// screen-space corner trajectories follow straight lines with zero hyperbolic wobble.
  static func opticalZoomLevel(target targetZoom: CGFloat, progress: Double) -> CGFloat {
    let p = CGFloat(min(max(progress, 0), 1))
    guard targetZoom > 1.0, p > 0 else { return 1.0 }
    if p >= 1.0 { return targetZoom }
    let targetViewportSpan = 1.0 / targetZoom
    let currentSpan = 1.0 + (targetViewportSpan - 1.0) * p
    return 1.0 / max(currentSpan, 0.0001)
  }

  static func interpolateCenter(
    from start: CGPoint,
    to end: CGPoint,
    progress: Double
  ) -> CGPoint {
    let t = CGFloat(min(max(progress, 0), 1))
    return CGPoint(
      x: start.x + (end.x - start.x) * t,
      y: start.y + (end.y - start.y) * t
    )
  }

  // MARK: - Zoom Interpolation

  /// Calculate current zoom state for a given time within a segment
  /// - Parameters:
  ///   - segment: The zoom segment
  ///   - currentTime: Current playback time
  ///   - transitionDuration: Duration of zoom-in/out transition
  /// - Returns: Tuple with current zoom level, center, and transition progress
  static func interpolateZoom(
    segment: ZoomSegment,
    currentTime: TimeInterval,
    transitionDuration: TimeInterval = defaultTransitionDuration
  ) -> (level: CGFloat, center: CGPoint, progress: Double) {
    guard segment.isEnabled else {
      return (level: 1.0, center: CGPoint(x: 0.5, y: 0.5), progress: 0)
    }

    let timeInSegment = currentTime - segment.startTime

    // Before segment starts
    guard timeInSegment >= 0 else {
      return (level: 1.0, center: segment.zoomCenter, progress: 0)
    }

    // After segment ends
    guard timeInSegment < segment.duration else {
      return (level: 1.0, center: segment.zoomCenter, progress: 0)
    }

    // Keep transition smooth but avoid overlap on short segments.
    let clampedTransition = clampTransitionDuration(transitionDuration)
    let maxTransitionPerEdge = segment.duration * 0.45
    let effectiveIn = min(clampedTransition, maxTransitionPerEdge)
    let effectiveOut = min(clampedTransition * 1.12, maxTransitionPerEdge)
    let zoomInEnd = max(effectiveIn, 0.0001)
    let zoomOutStart = min(max(segment.duration - effectiveOut, zoomInEnd), segment.duration)

    var progress: Double

    if timeInSegment < zoomInEnd {
      // Zooming in with C² cinema magnetic deceleration
      let t = timeInSegment / zoomInEnd
      progress = cinemaEaseIn(t)
    } else if timeInSegment > zoomOutStart {
      // Zooming out with C² smooth reveal
      let outSpan = max(segment.duration - zoomOutStart, 0.0001)
      let t = (timeInSegment - zoomOutStart) / outSpan
      progress = 1.0 - cinemaEaseOut(t)
    } else {
      // Fully zoomed
      progress = 1.0
    }

    // Interpolate zoom level in reciprocal viewport space for straight optical rays
    let currentLevel = opticalZoomLevel(target: segment.zoomLevel, progress: progress)

    return (level: currentLevel, center: segment.zoomCenter, progress: progress)
  }

  // MARK: - Transform Calculation

  /// Calculate scale and offset for preview display
  /// - Parameters:
  ///   - zoomLevel: Current zoom level
  ///   - center: Zoom center point (normalized 0-1)
  ///   - viewSize: Size of the view
  /// - Returns: Tuple with scale factor and offset
  static func calculateTransform(
    zoomLevel: CGFloat,
    center: CGPoint,
    viewSize: CGSize
  ) -> (scale: CGFloat, offset: CGSize) {
    guard zoomLevel > 1.0 else {
      return (scale: 1.0, offset: .zero)
    }

    // Keep preview translation mathematically aligned with export crop+scale mapping.
    // With scaleEffect applied before offset, translation must be proportional to zoomLevel.
    let offsetX = (center.x - 0.5) * viewSize.width * zoomLevel
    let offsetY = (center.y - 0.5) * viewSize.height * zoomLevel

    return (scale: zoomLevel, offset: CGSize(width: -offsetX, height: -offsetY))
  }

  // MARK: - Segment Utilities

  /// Find the active zoom segment at a given time
  static func activeSegment(
    at time: TimeInterval,
    in segments: [ZoomSegment]
  ) -> ZoomSegment? {
    // Return last matching segment (priority to later segments). Called per playback
    // tick: scan from the end without allocating a filtered copy.
    segments.last { $0.isEnabled && $0.contains(time: time) }
  }

  /// Sort segments by start time
  static func sortedByStartTime(_ segments: [ZoomSegment]) -> [ZoomSegment] {
    segments.sorted { $0.startTime < $1.startTime }
  }

  /// Check if adding a zoom at given time would overlap with existing segments
  static func hasOverlap(
    at time: TimeInterval,
    duration: TimeInterval,
    in segments: [ZoomSegment],
    excluding: UUID? = nil
  ) -> Bool {
    let testSegment = ZoomSegment(startTime: time, duration: duration)
    return segments.contains { segment in
      segment.id != excluding && segment.overlaps(with: testSegment)
    }
  }
}
