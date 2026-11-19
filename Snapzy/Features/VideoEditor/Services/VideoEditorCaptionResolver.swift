//
//  VideoEditorCaptionResolver.swift
//  Snapzy
//
//  Which caption shows at a time, shared by preview (structural playhead → source time)
//  and export (output time → source time). Also maps captions to OUTPUT time for
//  SRT/VTT: footage that was cut is dropped, speed segments shrink the cue.
//

import CoreGraphics
import Foundation

nonisolated struct VideoEditorCaptionResolver: Sendable {
  let segments: [CaptionSegment]
  let settings: VideoEditorCaptionSettings
  /// Segments with visible text, in `segments` order, and the running maximum of their
  /// end times. Lookups run per preview tick and per export frame, so they binary-search
  /// instead of scanning (and trimming the text of) every caption.
  private let visible: [CaptionSegment]
  private let maxEndThrough: [TimeInterval]

  /// Faster than this, captions hide when `hideDuringFastSpeed` is on.
  static let fastSpeedThreshold = 2.0

  init(captions: VideoEditorCaptions) {
    segments = captions.segments.sorted { $0.start < $1.start }
    settings = captions.settings
    visible = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var running = -TimeInterval.infinity
    maxEndThrough = visible.map { segment in
      running = max(running, segment.end)
      return running
    }
  }

  /// The caption under a recording time; `rate` is the playback speed there.
  func segment(atSource time: TimeInterval, rate: Double = 1) -> CaptionSegment? {
    guard settings.isEnabled else { return nil }
    if settings.hideDuringFastSpeed, rate > Self.fastSpeedThreshold { return nil }
    // Later captions win where two overlap (a dragged edge): the highest index whose
    // range contains `time`. Only segments starting at or before `time` qualify, and
    // walking back can stop once no earlier segment ends after `time`.
    var low = 0
    var high = visible.count
    while low < high {
      let mid = (low + high) / 2
      if visible[mid].start <= time { low = mid + 1 } else { high = mid }
    }
    var index = low - 1
    while index >= 0, maxEndThrough[index] > time {
      let candidate = visible[index]
      if time < candidate.end { return candidate }
      index -= 1
    }
    return nil
  }

  /// Captions as cues in OUTPUT time. A caption split by a cut becomes several cues;
  /// a caption entirely in cut footage is dropped.
  static func outputCues(
    segments: [CaptionSegment],
    playbackPlacements: [TimelineSequence.Placement],
    sequenceMap: TimelineSequenceMap
  ) -> [VideoEditorSubtitleCue] {
    var cues: [VideoEditorSubtitleCue] = []
    for segment in segments.sorted(by: { $0.start < $1.start }) {
      for placement in playbackPlacements where placement.clip.isPrimary {
        let start = max(segment.start, placement.sourceAxisStart)
        let end = min(segment.end, placement.sourceAxisEnd)
        guard end - start > 0.01 else { continue }
        let outStart = sequenceMap.toOutput(placement.sequenceTime(atSource: start))
        let outEnd = sequenceMap.toOutput(placement.sequenceTime(atSource: end))
        guard outEnd - outStart > 0.01 else { continue }
        // Reordered clips can bring pieces back to back: merge them into one cue.
        if let last = cues.last, last.text == segment.text, abs(last.end - outStart) < 0.002 {
          cues[cues.count - 1].end = outEnd
        } else {
          cues.append(VideoEditorSubtitleCue(start: outStart, end: outEnd, text: segment.text))
        }
      }
    }
    return cues.sorted { $0.start < $1.start }
  }
}

/// Small thread-safe cache of rendered caption images (export renders one image per
/// caption, not per frame).
nonisolated final class VideoEditorCaptionImageCache: @unchecked Sendable {
  struct Key: Hashable {
    let text: String
    let settings: VideoEditorCaptionSettings
    let width: Int
    let height: Int
    let scale: Int
  }

  struct Entry {
    let layout: VideoEditorCaptionLayout
    let image: CGImage
  }

  private let lock = NSLock()
  private var entries: [Key: Entry] = [:]
  private var order: [Key] = []
  private let capacity: Int

  init(capacity: Int = 8) {
    self.capacity = capacity
  }

  /// Layout + image of `text` for a video rect of `videoSize`, rendered at `scale`.
  func entry(text: String, settings: VideoEditorCaptionSettings, videoSize: CGSize, scale: CGFloat = 1) -> Entry? {
    let key = Key(
      text: text, settings: settings,
      width: Int(videoSize.width.rounded()), height: Int(videoSize.height.rounded()),
      scale: Int((scale * 100).rounded())
    )
    lock.lock()
    if let hit = entries[key] {
      lock.unlock()
      return hit
    }
    lock.unlock()
    guard let layout = VideoEditorCaptionLayout.make(text: text, settings: settings, videoSize: videoSize),
          let image = VideoEditorCaptionRenderer.image(layout, settings: settings, scale: scale)
    else { return nil }
    let entry = Entry(layout: layout, image: image)
    lock.lock()
    entries[key] = entry
    order.append(key)
    if order.count > capacity { entries[order.removeFirst()] = nil }
    lock.unlock()
    return entry
  }
}
