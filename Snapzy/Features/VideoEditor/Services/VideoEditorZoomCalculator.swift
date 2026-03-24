//
//  ZoomCalculator.swift
//  Snapzy
//
//  Utility functions for zoom calculations and animations
//

import Foundation
import CoreGraphics

/// Utility enum for zoom-related calculations
enum ZoomCalculator {

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
    transitionDuration: TimeInterval = 0.3
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

    // Calculate transition phases
    let zoomInEnd = min(transitionDuration, segment.duration / 3)
    let zoomOutStart = max(segment.duration - transitionDuration, segment.duration * 2 / 3)

    var progress: Double

    if timeInSegment < zoomInEnd {
      // Zooming in
      let t = timeInSegment / zoomInEnd
      progress = easeInOutCubic(t)
    } else if timeInSegment > zoomOutStart {
      // Zooming out
      let t = (timeInSegment - zoomOutStart) / (segment.duration - zoomOutStart)
      progress = 1.0 - easeInOutCubic(t)
    } else {
      // Fully zoomed
      progress = 1.0
    }

    // Interpolate zoom level
    let currentLevel = 1.0 + (segment.zoomLevel - 1.0) * CGFloat(progress)

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
    // Return last matching segment (priority to later segments)
    segments.filter { $0.isEnabled && $0.contains(time: time) }.last
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
