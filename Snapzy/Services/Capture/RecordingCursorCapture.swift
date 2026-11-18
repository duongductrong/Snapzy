//
//  RecordingCursorCapture.swift
//  Snapzy
//
//  Cursor data captured by a Studio recording: the cursor images seen while recording,
//  when the visible cursor changed, and every click. Positions stay in
//  `RecordingMetadata.mouseSamples`; all times are recording (source) time.
//

import CoreGraphics
import Foundation

/// One distinct cursor image, stored as `fileName` (PNG) inside the recording's
/// `CursorImages/<imagesFolderName>/` sidecar folder.
nonisolated struct RecordedCursorImage: Codable, Equatable, Sendable {
  var id: Int
  var fileName: String
  /// Hotspot in points from the image's top-left corner.
  var hotspot: CGPoint
  /// Image size in points (already includes the Accessibility pointer size).
  var pointSize: CGSize
  /// Pixels per point of the stored PNG.
  var scale: CGFloat
}

/// The visible cursor changed at `time`. Written only on change.
nonisolated struct RecordedCursorChange: Codable, Equatable, Sendable {
  var time: TimeInterval
  var imageID: Int?
  var isHidden: Bool
}

nonisolated enum RecordedClickButton: String, Codable, Sendable {
  case left
  case right
  case other
}

nonisolated enum RecordedClickPhase: String, Codable, Sendable {
  case down
  case up
}

nonisolated struct RecordedClick: Codable, Equatable, Sendable {
  var time: TimeInterval
  var button: RecordedClickButton
  var phase: RecordedClickPhase
  /// Top-left normalized point inside the capture rect.
  var normalizedX: CGFloat
  var normalizedY: CGFloat

  var normalizedPoint: CGPoint { CGPoint(x: normalizedX, y: normalizedY) }
}

/// Cursor appearance/click data captured by a Studio recording.
nonisolated struct RecordingCursorCapture: Codable, Equatable, Sendable {
  /// Folder inside the `CursorImages` sidecar directory holding this recording's
  /// cursor PNGs. `nil` while no image was captured.
  var imagesFolderName: String?
  var images: [RecordedCursorImage]
  var appearance: [RecordedCursorChange]
  var clicks: [RecordedClick]

  init(
    imagesFolderName: String? = nil,
    images: [RecordedCursorImage] = [],
    appearance: [RecordedCursorChange] = [],
    clicks: [RecordedClick] = []
  ) {
    self.imagesFolderName = imagesFolderName
    self.images = images
    self.appearance = appearance
    self.clicks = clicks
  }

  private enum CodingKeys: String, CodingKey {
    case imagesFolderName, images, appearance, clicks
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    imagesFolderName = try container.decodeIfPresent(String.self, forKey: .imagesFolderName)
    images = try container.decodeIfPresent([RecordedCursorImage].self, forKey: .images) ?? []
    appearance = try container.decodeIfPresent([RecordedCursorChange].self, forKey: .appearance) ?? []
    clicks = try container.decodeIfPresent([RecordedClick].self, forKey: .clicks) ?? []
  }

  /// The appearance change in effect at `time` (last change at or before it).
  func appearance(at time: TimeInterval) -> RecordedCursorChange? {
    guard !appearance.isEmpty else { return nil }
    var low = 0
    var high = appearance.count - 1
    guard appearance[0].time <= time else { return appearance[0] }
    while low < high {
      let mid = (low + high + 1) / 2
      if appearance[mid].time <= time { low = mid } else { high = mid - 1 }
    }
    return appearance[low]
  }

  func image(id: Int?) -> RecordedCursorImage? {
    guard let id else { return nil }
    return images.first { $0.id == id }
  }
}

nonisolated enum RecordedMouseSampleInterpolator {
  /// Linearly interpolated sample at `time`; `nil` when there are no samples.
  static func sample(at time: TimeInterval, in samples: [RecordedMouseSample]) -> RecordedMouseSample? {
    guard let first = samples.first, let last = samples.last else { return nil }
    if time <= first.time { return first }
    if time >= last.time { return last }
    var low = 0
    var high = samples.count - 1
    while high - low > 1 {
      let mid = (low + high) / 2
      if samples[mid].time <= time { low = mid } else { high = mid }
    }
    let a = samples[low]
    let b = samples[high]
    let span = b.time - a.time
    guard span > 0 else { return b }
    let t = CGFloat((time - a.time) / span)
    return RecordedMouseSample(
      time: time,
      normalizedX: a.normalizedX + (b.normalizedX - a.normalizedX) * t,
      normalizedY: a.normalizedY + (b.normalizedY - a.normalizedY) * t,
      isInsideCapture: t < 0.5 ? a.isInsideCapture : b.isInsideCapture
    )
  }
}
