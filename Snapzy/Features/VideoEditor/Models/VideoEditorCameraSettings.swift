//
//  VideoEditorCameraSettings.swift
//  Snapzy
//
//  Editable camera layer settings for Studio recordings (camera recorded as a sidecar).
//  Position and size are relative to the VIDEO rect (not the padded canvas), so the
//  camera keeps its place over the screen content; it is drawn in canvas space and is
//  never zoomed.
//

import CoreGraphics
import Foundation

nonisolated struct VideoEditorCameraSettings: Codable, Equatable, Sendable {
  static let sizeRange: ClosedRange<CGFloat> = 0.08 ... 0.6
  static let defaultSize: CGFloat = 0.22

  var isVisible: Bool = true
  /// `RecordingCameraShape.rawValue`.
  var shape: String = RecordingCameraShape.rectangle.rawValue
  /// Camera width as a fraction of the video width.
  var size: CGFloat = defaultSize
  /// Center, normalized to the video rect, top-left origin.
  var center: CGPoint = CGPoint(x: 0.85, y: 0.82)
  var isMirrored: Bool = false
  /// Stretches where the camera is hidden, in SOURCE time of the recording (like captions),
  /// so they follow cuts, reorder and speed. Sorted by start.
  var hiddenRanges: [VideoEditorCameraHiddenRange] = []

  static let `default` = VideoEditorCameraSettings()

  /// The camera as it was placed while recording.
  static func recorded(_ source: RecordingCameraSource) -> VideoEditorCameraSettings {
    var settings = VideoEditorCameraSettings()
    settings.shape = source.shape
    settings.isMirrored = source.isMirrored
    if source.normalizedFrame.width > 0 {
      settings.size = min(max(source.normalizedFrame.width, sizeRange.lowerBound), sizeRange.upperBound)
      settings.center = CGPoint(x: source.normalizedFrame.midX, y: source.normalizedFrame.midY)
    }
    return settings
  }

  var cameraShape: RecordingCameraShape { RecordingCameraShape(rawValue: shape) ?? .rectangle }

  /// Camera rect inside `videoRect` (any coordinate space whose y grows the same way as
  /// the normalized center: top-left for preview). `aspect` is width / height of the
  /// rectangle shape; square and circle are 1.
  func rect(in videoRect: CGRect, aspect: CGFloat) -> CGRect {
    let width = size * videoRect.width
    let height = cameraShape == .rectangle ? width / max(aspect, 0.1) : width
    let halfW = min(width / 2, videoRect.width / 2)
    let halfH = min(height / 2, videoRect.height / 2)
    let cx = min(max(videoRect.minX + center.x * videoRect.width, videoRect.minX + halfW), videoRect.maxX - halfW)
    let cy = min(max(videoRect.minY + center.y * videoRect.height, videoRect.minY + halfH), videoRect.maxY - halfH)
    return CGRect(x: cx - width / 2, y: cy - height / 2, width: width, height: height)
  }

  /// Corner radius for `rect`, scaling the recording overlay's point radius with the
  /// rect (a 18 pt radius on a 280 pt overlay keeps that proportion at any size).
  func cornerRadius(for rect: CGRect, referencePointWidth: CGFloat) -> CGFloat {
    let shape = cameraShape
    if shape == .circle { return min(rect.width, rect.height) / 2 }
    let reference = referencePointWidth > 0 ? referencePointWidth : 280
    let pointRadius = shape.cornerRadius(for: CGSize(width: reference, height: reference))
    return min(pointRadius * rect.width / reference, min(rect.width, rect.height) / 2)
  }

  /// The 9 snap anchors the panel offers (top-left normalized centers).
  static let anchors: [CGPoint] = [0.15, 0.5, 0.85].flatMap { y in [0.15, 0.5, 0.85].map { CGPoint(x: $0, y: y) } }

  private enum CodingKeys: String, CodingKey { case isVisible, shape, size, center, isMirrored, hiddenRanges }

  init() {}

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = VideoEditorCameraSettings.default
    isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? d.isVisible
    shape = try c.decodeIfPresent(String.self, forKey: .shape) ?? d.shape
    size = try c.decodeIfPresent(CGFloat.self, forKey: .size) ?? d.size
    center = try c.decodeIfPresent(CGPoint.self, forKey: .center) ?? d.center
    isMirrored = try c.decodeIfPresent(Bool.self, forKey: .isMirrored) ?? d.isMirrored
    hiddenRanges = try c.decodeIfPresent([VideoEditorCameraHiddenRange].self, forKey: .hiddenRanges) ?? []
  }
}

nonisolated extension RecordingCameraSource {
  /// Width / height of the rectangle overlay while recording (16:9 when unknown).
  var overlayAspect: CGFloat {
    pointSize.height > 0 ? pointSize.width / pointSize.height : 16.0 / 9.0
  }

  func isInGap(_ time: TimeInterval) -> Bool {
    gaps.contains { time >= $0.start && time < $0.end }
  }
}
