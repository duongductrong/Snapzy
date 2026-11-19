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
  /// Set when the camera sits on one of the nine anchors: x and y are each 0, 0.5 or 1
  /// (left/center/right, top/middle/bottom). The camera then keeps the recording overlay's
  /// fixed edge gap at any size, and `center` is ignored by `rect(in:aspect:edgeInset:)`.
  var anchor: CGPoint?
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

  /// Edge gap of an anchored camera as a fraction of the video width, when the recording
  /// gives none (24 pt on a 1440 pt wide screen).
  static let defaultEdgeInset: CGFloat = RecordingCameraOverlayPlacement.defaultEdgeInset / 1440

  /// Camera rect inside `videoRect` (any coordinate space whose y grows the same way as
  /// the normalized center: top-left for preview). `aspect` is width / height of the
  /// rectangle shape; square and circle are 1. `edgeInset` is the anchored camera's gap
  /// to the video edges, as a fraction of the video width (same gap on both axes).
  func rect(in videoRect: CGRect, aspect: CGFloat, edgeInset: CGFloat = defaultEdgeInset) -> CGRect {
    let width = size * videoRect.width
    let height = cameraShape == .rectangle ? width / max(aspect, 0.1) : width
    if let anchor {
      let inset = max(0, edgeInset) * videoRect.width
      let insetX = min(inset, max(0, (videoRect.width - width) / 2))
      let insetY = min(inset, max(0, (videoRect.height - height) / 2))
      let x = videoRect.minX + insetX + anchor.x * max(0, videoRect.width - 2 * insetX - width)
      let y = videoRect.minY + insetY + anchor.y * max(0, videoRect.height - 2 * insetY - height)
      return CGRect(x: x, y: y, width: width, height: height)
    }
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

  /// The 9 snap anchors the panel offers, as alignments (0 / 0.5 / 1 per axis, top-left
  /// origin), row by row from the top.
  static let anchors: [CGPoint] = [0, 0.5, 1].flatMap { y in [0, 0.5, 1].map { CGPoint(x: $0, y: y) } }

  /// Puts the camera on `anchor` (an entry of `anchors`), keeping `center` in step with
  /// where it is drawn in a video of `videoSize`.
  mutating func setAnchor(_ anchor: CGPoint, videoSize: CGSize, aspect: CGFloat, edgeInset: CGFloat) {
    self.anchor = anchor
    syncCenter(videoSize: videoSize, aspect: aspect, edgeInset: edgeInset)
  }

  /// Refreshes `center` from the drawn rect (a no-op for a free camera).
  mutating func syncCenter(videoSize: CGSize, aspect: CGFloat, edgeInset: CGFloat) {
    guard anchor != nil, videoSize.width > 0, videoSize.height > 0 else { return }
    let rect = rect(in: CGRect(origin: .zero, size: videoSize), aspect: aspect, edgeInset: edgeInset)
    center = CGPoint(x: rect.midX / videoSize.width, y: rect.midY / videoSize.height)
  }

  private enum CodingKeys: String, CodingKey { case isVisible, shape, size, center, isMirrored, anchor, hiddenRanges }

  init() {}

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = VideoEditorCameraSettings.default
    isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? d.isVisible
    shape = try c.decodeIfPresent(String.self, forKey: .shape) ?? d.shape
    size = try c.decodeIfPresent(CGFloat.self, forKey: .size) ?? d.size
    center = try c.decodeIfPresent(CGPoint.self, forKey: .center) ?? d.center
    isMirrored = try c.decodeIfPresent(Bool.self, forKey: .isMirrored) ?? d.isMirrored
    anchor = try c.decodeIfPresent(CGPoint.self, forKey: .anchor)
    hiddenRanges = try c.decodeIfPresent([VideoEditorCameraHiddenRange].self, forKey: .hiddenRanges) ?? []
  }
}

nonisolated extension RecordingCameraSource {
  /// Width / height of the rectangle overlay while recording (16:9 when unknown).
  var overlayAspect: CGFloat {
    pointSize.height > 0 ? pointSize.width / pointSize.height : 16.0 / 9.0
  }

  /// The recording overlay's edge gap as a fraction of the recorded area's width, so an
  /// anchored camera sits as far from the edge as it did while recording.
  var edgeInsetFraction: CGFloat {
    guard normalizedFrame.width > 0, pointSize.width > 0 else { return VideoEditorCameraSettings.defaultEdgeInset }
    let recordingWidth = pointSize.width / normalizedFrame.width
    return min(max(RecordingCameraOverlayPlacement.defaultEdgeInset / recordingWidth, 0), 0.1)
  }

  func isInGap(_ time: TimeInterval) -> Bool {
    gaps.contains { time >= $0.start && time < $0.end }
  }
}
