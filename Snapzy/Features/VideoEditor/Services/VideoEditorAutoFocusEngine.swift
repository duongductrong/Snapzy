//
//  VideoEditorAutoFocusEngine.swift
//  Snapzy
//
//  Precomputes and resolves smart-camera states for cursor-follow zoom.
//

import CoreGraphics
import Foundation

enum VideoEditorAutoFocusEngine {
  struct AutoFocusAccuracyMetrics {
    let sampleCount: Int
    let lockAccuracy: Double
    let visibilityRate: Double
    let meanError: Double
  }

  static func buildPath(
    from metadata: RecordingMetadata,
    segment: ZoomSegment
  ) -> [AutoFocusCameraSample] {
    guard segment.isAutoMode else { return [] }

    let settings = segment.autoFocusSettings
    let samples = canonicalSamples(from: metadata)
    guard samples.count >= 2 else { return [] }

    let zoomLevel = settings.zoomLevel.clamped(to: AutoFocusSettings.zoomRange)
    let cropHalfWidth = 0.5 / zoomLevel
    let cropHalfHeight = 0.5 / zoomLevel
    let safeHalfWidth = max(cropHalfWidth * settings.focusMargin.clamped(to: AutoFocusSettings.focusMarginRange), 0.02)
    let safeHalfHeight = max(cropHalfHeight * settings.focusMargin.clamped(to: AutoFocusSettings.focusMarginRange), 0.02)

    var lastVisiblePoint = samples.first(where: \.isInsideCapture)?.point.clampedToUnitRect
      ?? CGPoint(x: 0.5, y: 0.5)
    var currentCenter = clampCenter(
      lastVisiblePoint,
      cropHalfWidth: cropHalfWidth,
      cropHalfHeight: cropHalfHeight
    )

    let minimumDelta = 1.0 / Double(max(metadata.samplesPerSecond, 1))
    let maxResampleStep: TimeInterval = 1.0 / 60.0
    var path: [AutoFocusCameraSample] = [
      AutoFocusCameraSample(time: samples[0].time, center: currentCenter)
    ]

    var previousTime = samples[0].time
    var previousCursorPoint = samples[0].point.clampedToUnitRect

    for sample in samples.dropFirst() {
      let cursorPoint = sample.point.clampedToUnitRect
      if sample.isInsideCapture {
        lastVisiblePoint = cursorPoint
      }

      let cursorTarget = sample.isInsideCapture ? cursorPoint : lastVisiblePoint
      let deltaTime = max(sample.time - previousTime, minimumDelta)
      let filteredCursorTarget = clampedCursorPoint(
        from: previousCursorPoint,
        to: cursorTarget,
        deltaTime: deltaTime
      )
      let stepCount = max(1, Int(ceil(deltaTime / maxResampleStep)))
      let motion = motionIntensity(
        from: previousCursorPoint,
        to: filteredCursorTarget,
        deltaTime: deltaTime
      )

      for step in 1...stepCount {
        let progress = CGFloat(step) / CGFloat(stepCount)
        let interpolatedCursor = interpolate(
          from: previousCursorPoint,
          to: filteredCursorTarget,
          progress: progress
        )
        let adaptiveSafeHalfWidth = max(safeHalfWidth * (1 - 0.45 * motion), 0.015)
        let adaptiveSafeHalfHeight = max(safeHalfHeight * (1 - 0.45 * motion), 0.015)

        let targetCenter = deadZoneAdjustedCenter(
          currentCenter: currentCenter,
          cursorPoint: interpolatedCursor,
          safeHalfWidth: adaptiveSafeHalfWidth,
          safeHalfHeight: adaptiveSafeHalfHeight,
          cropHalfWidth: cropHalfWidth,
          cropHalfHeight: cropHalfHeight
        )

        let alpha = smoothingAlpha(
          deltaTime: deltaTime / Double(stepCount),
          followSpeed: settings.followSpeed.clamped(to: AutoFocusSettings.followSpeedRange),
          motionIntensity: motion
        )
        currentCenter = CGPoint(
          x: currentCenter.x + (targetCenter.x - currentCenter.x) * alpha,
          y: currentCenter.y + (targetCenter.y - currentCenter.y) * alpha
        )
        currentCenter = clampCenter(
          currentCenter,
          cropHalfWidth: cropHalfWidth,
          cropHalfHeight: cropHalfHeight
        )

        path.append(
          AutoFocusCameraSample(
            time: previousTime + (deltaTime * Double(step) / Double(stepCount)),
            center: currentCenter
          )
        )
      }

      previousTime = sample.time
      previousCursorPoint = filteredCursorTarget
    }

    return deduplicated(path)
  }

  static func evaluatePathQuality(
    metadata: RecordingMetadata,
    segment: ZoomSegment,
    path: [AutoFocusCameraSample],
    lockThreshold: CGFloat = 0.08
  ) -> AutoFocusAccuracyMetrics {
    let samples = canonicalSamples(from: metadata)
      .filter { $0.time >= segment.startTime && $0.time <= segment.endTime }
    guard !samples.isEmpty else {
      return AutoFocusAccuracyMetrics(sampleCount: 0, lockAccuracy: 0, visibilityRate: 0, meanError: 0)
    }

    let zoomLevel = segment.zoomLevel.clamped(to: AutoFocusSettings.zoomRange)
    let cropHalfWidth = 0.5 / zoomLevel
    let cropHalfHeight = 0.5 / zoomLevel

    var lockedSamples = 0
    var visibleSamples = 0
    var totalError: Double = 0

    for sample in samples {
      let centerPoint = path.isEmpty ? segment.zoomCenter : center(at: sample.time, in: path)
      let dx = sample.point.x - centerPoint.x
      let dy = sample.point.y - centerPoint.y
      let distance = sqrt(dx * dx + dy * dy)
      totalError += distance

      if distance <= lockThreshold {
        lockedSamples += 1
      }

      if abs(dx) <= cropHalfWidth && abs(dy) <= cropHalfHeight {
        visibleSamples += 1
      }
    }

    let totalCount = samples.count
    return AutoFocusAccuracyMetrics(
      sampleCount: totalCount,
      lockAccuracy: Double(lockedSamples) / Double(totalCount),
      visibilityRate: Double(visibleSamples) / Double(totalCount),
      meanError: totalError / Double(totalCount)
    )
  }

  static func cameraState(
    at time: TimeInterval,
    segment: ZoomSegment,
    path: [AutoFocusCameraSample],
    transitionDuration: TimeInterval
  ) -> VideoEditorCameraState {
    let interpolated = ZoomCalculator.interpolateZoom(
      segment: segment,
      currentTime: time,
      transitionDuration: transitionDuration
    )

    guard interpolated.level > 1.0 else {
      return .identity
    }

    let center = path.isEmpty ? segment.zoomCenter : center(at: time, in: path)
    return VideoEditorCameraState(zoomLevel: interpolated.level, center: center)
  }

  static func resolvedCameraState(
    at time: TimeInterval,
    segments: [ZoomSegment],
    autoFocusPaths: [UUID: [AutoFocusCameraSample]],
    transitionDuration: TimeInterval
  ) -> VideoEditorCameraState {
    guard let activeSegment = ZoomCalculator.activeSegment(at: time, in: segments) else {
      return .identity
    }

    switch activeSegment.zoomType {
    case .manual:
      let interpolated = ZoomCalculator.interpolateZoom(
        segment: activeSegment,
        currentTime: time,
        transitionDuration: transitionDuration
      )
      return VideoEditorCameraState(
        zoomLevel: interpolated.level,
        center: interpolated.center
      )
    case .auto:
      return cameraState(
        at: time,
        segment: activeSegment,
        path: autoFocusPaths[activeSegment.id] ?? [],
        transitionDuration: transitionDuration
      )
    }
  }

  static func trimmedPath(
    _ path: [AutoFocusCameraSample],
    trimStart: TimeInterval,
    trimEnd: TimeInterval
  ) -> [AutoFocusCameraSample] {
    guard !path.isEmpty, trimEnd > trimStart else { return [] }

    let startCenter = center(at: trimStart, in: path)
    let endCenter = center(at: trimEnd, in: path)

    var trimmed = path
      .filter { $0.time > trimStart && $0.time < trimEnd }
      .map { sample in
        AutoFocusCameraSample(
          time: sample.time - trimStart,
          center: sample.center
        )
      }

    trimmed.insert(
      AutoFocusCameraSample(time: 0, center: startCenter),
      at: 0
    )
    trimmed.append(
      AutoFocusCameraSample(time: trimEnd - trimStart, center: endCenter)
    )

    return deduplicated(trimmed)
  }

  private static func center(at time: TimeInterval, in path: [AutoFocusCameraSample]) -> CGPoint {
    guard let firstSample = path.first else {
      return CGPoint(x: 0.5, y: 0.5)
    }
    guard let lastSample = path.last else {
      return firstSample.center
    }

    if time <= firstSample.time {
      return firstSample.center
    }
    if time >= lastSample.time {
      return lastSample.center
    }

    var low = 0
    var high = path.count - 1

    while low + 1 < high {
      let mid = (low + high) / 2
      if path[mid].time <= time {
        low = mid
      } else {
        high = mid
      }
    }

    let previous = path[low]
    let next = path[high]
    let duration = max(next.time - previous.time, 0.0001)
    let progress = ((time - previous.time) / duration).clamped(to: 0...1)

    return CGPoint(
      x: previous.center.x + (next.center.x - previous.center.x) * progress,
      y: previous.center.y + (next.center.y - previous.center.y) * progress
    )
  }

  private static func smoothingAlpha(
    deltaTime: TimeInterval,
    followSpeed: Double,
    motionIntensity: CGFloat
  ) -> CGFloat {
    let responseRate = 2.0 + (followSpeed * 10.0) + (Double(motionIntensity) * 6.0)
    let alpha = 1.0 - exp(-responseRate * deltaTime)
    return CGFloat(alpha).clamped(to: 0...1)
  }

  private static func deadZoneAdjustedCenter(
    currentCenter: CGPoint,
    cursorPoint: CGPoint,
    safeHalfWidth: CGFloat,
    safeHalfHeight: CGFloat,
    cropHalfWidth: CGFloat,
    cropHalfHeight: CGFloat
  ) -> CGPoint {
    var target = currentCenter

    if cursorPoint.x < currentCenter.x - safeHalfWidth {
      target.x = cursorPoint.x + safeHalfWidth
    } else if cursorPoint.x > currentCenter.x + safeHalfWidth {
      target.x = cursorPoint.x - safeHalfWidth
    }

    if cursorPoint.y < currentCenter.y - safeHalfHeight {
      target.y = cursorPoint.y + safeHalfHeight
    } else if cursorPoint.y > currentCenter.y + safeHalfHeight {
      target.y = cursorPoint.y - safeHalfHeight
    }

    return clampCenter(
      target,
      cropHalfWidth: cropHalfWidth,
      cropHalfHeight: cropHalfHeight
    )
  }

  private static func clampCenter(
    _ center: CGPoint,
    cropHalfWidth: CGFloat,
    cropHalfHeight: CGFloat
  ) -> CGPoint {
    CGPoint(
      x: center.x.clamped(to: cropHalfWidth...(1 - cropHalfWidth)),
      y: center.y.clamped(to: cropHalfHeight...(1 - cropHalfHeight))
    )
  }

  private static func deduplicated(_ path: [AutoFocusCameraSample]) -> [AutoFocusCameraSample] {
    var deduplicatedPath: [AutoFocusCameraSample] = []

    for sample in path {
      if let lastSample = deduplicatedPath.last,
         abs(lastSample.time - sample.time) < 0.0001
      {
        deduplicatedPath[deduplicatedPath.count - 1] = sample
      } else {
        deduplicatedPath.append(sample)
      }
    }

    return deduplicatedPath
  }

  private struct CanonicalCursorSample {
    var time: TimeInterval
    var point: CGPoint
    var isInsideCapture: Bool
  }

  private static func canonicalSamples(from metadata: RecordingMetadata) -> [CanonicalCursorSample] {
    let sortedSamples = metadata.mouseSamples.sorted { $0.time < $1.time }
    guard !sortedSamples.isEmpty else { return [] }

    var canonical: [CanonicalCursorSample] = []
    canonical.reserveCapacity(sortedSamples.count)

    for sample in sortedSamples {
      let point = canonicalPoint(for: sample, coordinateSpace: metadata.coordinateSpace)
      let canonicalSample = CanonicalCursorSample(
        time: sample.time,
        point: point.clampedToUnitRect,
        isInsideCapture: sample.isInsideCapture
      )

      if let last = canonical.last, abs(last.time - canonicalSample.time) < 0.0001 {
        canonical[canonical.count - 1] = canonicalSample
      } else {
        canonical.append(canonicalSample)
      }
    }

    return canonical
  }

  private static func canonicalPoint(
    for sample: RecordedMouseSample,
    coordinateSpace: RecordingCoordinateSpace
  ) -> CGPoint {
    switch coordinateSpace {
    case .topLeftNormalized:
      return sample.normalizedPoint
    case .bottomLeftNormalized:
      return CGPoint(
        x: sample.normalizedX,
        y: 1 - sample.normalizedY
      )
    }
  }

  private static func clampedCursorPoint(
    from previous: CGPoint,
    to current: CGPoint,
    deltaTime: TimeInterval
  ) -> CGPoint {
    let maxSpeed: CGFloat = 4.0  // normalized units per second
    let minDelta = max(deltaTime, 0.0001)
    let maxDistance = maxSpeed * CGFloat(minDelta)
    let distance = hypot(current.x - previous.x, current.y - previous.y)
    guard distance > maxDistance, distance > 0.0001 else {
      return current.clampedToUnitRect
    }

    let progress = (maxDistance / distance).clamped(to: 0...1)
    return interpolate(from: previous, to: current, progress: progress).clampedToUnitRect
  }

  private static func motionIntensity(
    from previous: CGPoint,
    to current: CGPoint,
    deltaTime: TimeInterval
  ) -> CGFloat {
    let minDelta = max(deltaTime, 0.0001)
    let speed = hypot(current.x - previous.x, current.y - previous.y) / CGFloat(minDelta)
    return (speed / 1.2).clamped(to: 0...1)
  }

  private static func interpolate(from start: CGPoint, to end: CGPoint, progress: CGFloat) -> CGPoint {
    CGPoint(
      x: start.x + (end.x - start.x) * progress,
      y: start.y + (end.y - start.y) * progress
    )
  }
}

private extension CGPoint {
  var clampedToUnitRect: CGPoint {
    CGPoint(
      x: x.clamped(to: 0...1),
      y: y.clamped(to: 0...1)
    )
  }
}

private extension CGFloat {
  func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}

private extension Double {
  func clamped(to range: ClosedRange<Double>) -> Double {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}
