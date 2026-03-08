//
//  VideoEditorAutoFocusEngine.swift
//  Snapzy
//
//  Precomputes and resolves smart-camera states for cursor-follow zoom.
//

import CoreGraphics
import Foundation

enum VideoEditorAutoFocusEngine {
  static func buildPath(
    from metadata: RecordingMetadata,
    settings: AutoFocusSettings
  ) -> [AutoFocusCameraSample] {
    let samples = metadata.mouseSamples.sorted { $0.time < $1.time }
    guard samples.count >= 2 else { return [] }

    let zoomLevel = settings.zoomLevel.clamped(to: AutoFocusSettings.zoomRange)
    let cropHalfWidth = 0.5 / zoomLevel
    let cropHalfHeight = 0.5 / zoomLevel
    let safeHalfWidth = max(cropHalfWidth * settings.focusMargin.clamped(to: AutoFocusSettings.focusMarginRange), 0.02)
    let safeHalfHeight = max(cropHalfHeight * settings.focusMargin.clamped(to: AutoFocusSettings.focusMarginRange), 0.02)

    var lastVisiblePoint = samples.first(where: \.isInsideCapture)?.normalizedPoint.clampedToUnitRect
      ?? CGPoint(x: 0.5, y: 0.5)
    var currentCenter = clampCenter(
      lastVisiblePoint,
      cropHalfWidth: cropHalfWidth,
      cropHalfHeight: cropHalfHeight
    )

    var path: [AutoFocusCameraSample] = []
    var previousTime = samples[0].time

    for sample in samples {
      let cursorPoint = sample.normalizedPoint.clampedToUnitRect
      if sample.isInsideCapture {
        lastVisiblePoint = cursorPoint
      }

      let targetCenter = deadZoneAdjustedCenter(
        currentCenter: currentCenter,
        cursorPoint: sample.isInsideCapture ? cursorPoint : lastVisiblePoint,
        safeHalfWidth: safeHalfWidth,
        safeHalfHeight: safeHalfHeight,
        cropHalfWidth: cropHalfWidth,
        cropHalfHeight: cropHalfHeight
      )

      let deltaTime = max(sample.time - previousTime, 1.0 / Double(max(metadata.samplesPerSecond, 1)))
      let alpha = smoothingAlpha(
        deltaTime: deltaTime,
        followSpeed: settings.followSpeed.clamped(to: AutoFocusSettings.followSpeedRange)
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
          time: sample.time,
          center: currentCenter
        )
      )
      previousTime = sample.time
    }

    return path
  }

  static func cameraState(
    at time: TimeInterval,
    settings: AutoFocusSettings,
    path: [AutoFocusCameraSample]
  ) -> VideoEditorCameraState? {
    guard settings.isEnabled, !path.isEmpty else { return nil }

    let center = center(at: time, in: path)
    return VideoEditorCameraState(
      zoomLevel: settings.zoomLevel.clamped(to: AutoFocusSettings.zoomRange),
      center: center
    )
  }

  static func resolvedCameraState(
    at time: TimeInterval,
    manualSegments: [ZoomSegment],
    autoFocusSettings: AutoFocusSettings,
    autoFocusPath: [AutoFocusCameraSample],
    transitionDuration: TimeInterval
  ) -> VideoEditorCameraState {
    if let activeSegment = ZoomCalculator.activeSegment(at: time, in: manualSegments) {
      let interpolated = ZoomCalculator.interpolateZoom(
        segment: activeSegment,
        currentTime: time,
        transitionDuration: transitionDuration
      )
      return VideoEditorCameraState(
        zoomLevel: interpolated.level,
        center: interpolated.center
      )
    }

    return cameraState(at: time, settings: autoFocusSettings, path: autoFocusPath)
      ?? .identity
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

  private static func smoothingAlpha(deltaTime: TimeInterval, followSpeed: Double) -> CGFloat {
    let responseRate = 2.0 + (followSpeed * 10.0)
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
