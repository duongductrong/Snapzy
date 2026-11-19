//
//  VideoEditorCameraHiddenRange.swift
//  Snapzy
//
//  "Hide camera" stretches of a Studio recording, in recording SOURCE time, plus the
//  shared visibility math (0.2 s fade at each edge) used by preview and export, and the
//  drag-to-place math for the preview.
//

import CoreGraphics
import Foundation

nonisolated struct VideoEditorCameraHiddenRange: Codable, Equatable, Identifiable, Sendable {
  var id = UUID()
  var start: TimeInterval
  var end: TimeInterval

  static let minimumDuration: TimeInterval = 0.2
  static let defaultDuration: TimeInterval = 2
}

nonisolated extension VideoEditorCameraSettings {
  /// Fade length when the camera hides or comes back.
  static let hideFadeDuration: TimeInterval = 0.2

  /// 0 (hidden) … 1 (shown) at a recording time, fading over `hideFadeDuration` outside
  /// each hidden range. Ignores `isVisible` (callers check it first).
  func visibility(atSource time: TimeInterval) -> Double {
    var result = 1.0
    for range in hiddenRanges {
      if time >= range.start, time < range.end { return 0 }
      let distance = time < range.start ? range.start - time : time - range.end
      result = min(result, distance / Self.hideFadeDuration)
    }
    return max(0, min(1, result))
  }

  /// Adds a hidden range (merging overlaps), keeping the list sorted.
  func addingHiddenRange(_ range: VideoEditorCameraHiddenRange) -> VideoEditorCameraSettings {
    var copy = self
    var merged = range
    copy.hiddenRanges.removeAll { other in
      guard other.start <= merged.end, other.end >= merged.start else { return false }
      merged.start = min(merged.start, other.start)
      merged.end = max(merged.end, other.end)
      return true
    }
    copy.hiddenRanges.append(merged)
    copy.hiddenRanges.sort { $0.start < $1.start }
    return copy
  }

  /// Placement after dragging the camera by `translation` (points) from `startCenter` over
  /// a video of `videoSize` points. Snaps to the nearest of the nine anchors (placed with
  /// the `edgeInset` gap, as `rect(in:aspect:edgeInset:)` draws them) within `threshold`
  /// points (square distance, like the recording overlay); else the camera stays free.
  static func draggedPlacement(
    from startCenter: CGPoint,
    translation: CGSize,
    videoSize: CGSize,
    cameraSize: CGSize,
    edgeInset: CGFloat = defaultEdgeInset,
    threshold: CGFloat
  ) -> (center: CGPoint, anchor: CGPoint?) {
    guard videoSize.width > 0, videoSize.height > 0 else { return (startCenter, nil) }
    // Keep the whole camera inside the video, as `rect(in:aspect:)` draws it.
    let halfX = min(cameraSize.width / 2 / videoSize.width, 0.5)
    let halfY = min(cameraSize.height / 2 / videoSize.height, 0.5)
    let proposed = CGPoint(
      x: min(max(startCenter.x + translation.width / videoSize.width, halfX), 1 - halfX),
      y: min(max(startCenter.y + translation.height / videoSize.height, halfY), 1 - halfY)
    )
    let inset = max(0, edgeInset) * videoSize.width
    let insetX = min(inset, max(0, (videoSize.width - cameraSize.width) / 2))
    let insetY = min(inset, max(0, (videoSize.height - cameraSize.height) / 2))
    var best: (anchor: CGPoint, center: CGPoint, distance: CGFloat)?
    for anchor in anchors {
      let target = CGPoint(
        x: (insetX + cameraSize.width / 2 + anchor.x * max(0, videoSize.width - 2 * insetX - cameraSize.width)) / videoSize.width,
        y: (insetY + cameraSize.height / 2 + anchor.y * max(0, videoSize.height - 2 * insetY - cameraSize.height)) / videoSize.height
      )
      let distance = max(
        abs(target.x - proposed.x) * videoSize.width,
        abs(target.y - proposed.y) * videoSize.height
      )
      if distance <= threshold, distance < (best?.distance ?? .greatestFiniteMagnitude) {
        best = (anchor, target, distance)
      }
    }
    if let best { return (best.center, best.anchor) }
    return (proposed, nil)
  }
}
