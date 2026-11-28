//
//  VideoEditorCaptionResolver.swift
//  Snapzy
//
//  Which caption shows at a time, shared by preview (structural playhead -> source time)
//  and export (output time -> source time). Also maps captions to OUTPUT time for
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
    if settings.hideDuringFastSpeed, rate > Self.fastSpeedThreshold {
      return nil
    }
    var low = 0
    var high = visible.count
    while low < high {
      let mid = (low + high) / 2
      if visible[mid].start <= time {
        low = mid + 1
      } else {
        high = mid
      }
    }
    var index = low - 1
    while index >= 0, maxEndThrough[index] > time {
      let candidate = visible[index]
      if time < candidate.end {
        return candidate
      }
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

/// Byte-bounded, deduplicated thread-safe LRU cache of rendered caption & title bitmaps.
final nonisolated class VideoEditorCaptionImageCache: @unchecked Sendable {
  private struct LayoutKey: Equatable, Hashable {
    let text: String
    let settings: VideoEditorCaptionSettings
    let width: Int
    let height: Int
    private let precomputedHash: Int

    init(text: String, settings: VideoEditorCaptionSettings, width: Int, height: Int) {
      self.text = text
      self.settings = settings
      self.width = width
      self.height = height
      var hasher = Hasher()
      hasher.combine(text)
      hasher.combine(settings)
      hasher.combine(width)
      hasher.combine(height)
      precomputedHash = hasher.finalize()
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(precomputedHash)
    }
  }

  private struct ImageKey: Hashable {
    let layoutKey: LayoutKey
    let activeWordBucket: Int
    let activeWordArrivalBucket: Int
    let subwordKind: VideoEditorCaptionMotionState.SubwordAnimationKind?
    let subwordBucket: Int
    let scale: Int
  }

  struct Entry {
    let layout: VideoEditorCaptionLayout
    let image: CGImage
  }

  private struct StoredImage {
    let entry: Entry
    let byteCost: Int
    var generation: UInt64
  }

  private struct StoredLayout {
    let layout: VideoEditorCaptionLayout
    var generation: UInt64
  }

  static let defaultMaxBytes: Int = 48 * 1024 * 1024 // 48 MB total RGBA budget

  private let lock = NSLock()
  private var layouts: [LayoutKey: StoredLayout] = [:]
  private var entries: [ImageKey: StoredImage] = [:]
  private var totalBytes: Int = 0
  private var generationCounter: UInt64 = 0
  private let capacity: Int
  private let maxBytes: Int

  init(capacity: Int = 96, maxBytes: Int = VideoEditorCaptionImageCache.defaultMaxBytes) {
    self.capacity = max(8, capacity)
    self.maxBytes = max(4 * 1024 * 1024, maxBytes)
  }

  var currentByteCost: Int {
    lock.lock()
    defer { lock.unlock() }
    return totalBytes
  }

  var currentEntryCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return entries.count
  }

  /// Resolve cached layout + bitmap for `segment` at `sourceTime` (or plain `text` when `segment == nil`).
  func entry(
    text: String,
    segment: CaptionSegment? = nil,
    sourceTime: TimeInterval? = nil,
    settings: VideoEditorCaptionSettings,
    videoSize: CGSize,
    subwordKind: VideoEditorCaptionMotionState.SubwordAnimationKind? = nil,
    subwordProgress: CGFloat? = nil,
    scale: CGFloat = 1
  ) -> Entry? {
    let lKey = LayoutKey(
      text: text,
      settings: settings,
      width: Int(videoSize.width.rounded()),
      height: Int(videoSize.height.rounded())
    )

    let layout: VideoEditorCaptionLayout
    lock.lock()
    if var cachedLayout = layouts[lKey] {
      generationCounter &+= 1
      cachedLayout.generation = generationCounter
      layouts[lKey] = cachedLayout
      lock.unlock()
      layout = cachedLayout.layout
    } else {
      lock.unlock()
      guard let built = VideoEditorCaptionLayout.make(text: text, settings: settings, videoSize: videoSize) else {
        return nil
      }
      lock.lock()
      generationCounter &+= 1
      layouts[lKey] = StoredLayout(layout: built, generation: generationCounter)
      if layouts.count > capacity,
         let oldestLayoutKey = layouts.min(by: { $0.value.generation < $1.value.generation })?.key {
        layouts.removeValue(forKey: oldestLayoutKey)
      }
      lock.unlock()
      layout = built
    }

    let wordTiming: VideoEditorActiveWordTiming? = if settings.wordMode != .fullLine,
                                                      let segment,
                                                      let sourceTime {
      VideoEditorCaptionMotion.activeWordTiming(
        atSource: sourceTime,
        in: segment,
        wordsInLayout: layout.flatWords,
        settings: settings
      )
    } else {
      nil
    }

    let resolvedWordIdx = wordTiming?.index
    let resolvedWordArrival: CGFloat? = (settings.wordAnimation != .none) ? wordTiming?.arrivalProgress : nil
    let wordArrivalBucket: Int = if let arr = resolvedWordArrival {
      arr < 0.999 ? Int((min(1, max(0, arr)) * 8).rounded()) : 8
    } else {
      -1
    }

    let quantizedSubword: Int = if let sp = subwordProgress, subwordKind != nil, sp < 0.999 {
      Int((min(1, max(0, sp)) * 24).rounded())
    } else {
      -1
    }

    let iKey = ImageKey(
      layoutKey: lKey,
      activeWordBucket: resolvedWordIdx ?? -1,
      activeWordArrivalBucket: wordArrivalBucket,
      subwordKind: quantizedSubword >= 0 ? subwordKind : nil,
      subwordBucket: quantizedSubword,
      scale: Int((scale * 100).rounded())
    )

    lock.lock()
    if var hit = entries[iKey] {
      generationCounter &+= 1
      hit.generation = generationCounter
      entries[iKey] = hit
      lock.unlock()
      return hit.entry
    }
    lock.unlock()

    let quantizedArrivalProgress: CGFloat? = wordArrivalBucket >= 0 ? (CGFloat(wordArrivalBucket) / 8.0) : nil
    let quantizedSubProgress: CGFloat? = quantizedSubword >= 0 ? (CGFloat(quantizedSubword) / 24.0) : nil

    guard let image = VideoEditorCaptionRenderer.image(
      layout,
      settings: settings,
      activeWordIndex: resolvedWordIdx,
      activeWordArrivalProgress: quantizedArrivalProgress,
      subwordKind: quantizedSubword >= 0 ? subwordKind : nil,
      subwordProgress: quantizedSubProgress,
      scale: scale
    ) else { return nil }

    let entry = Entry(layout: layout, image: image)
    let cost = max(1, image.bytesPerRow * image.height)

    lock.lock()
    if let existing = entries.removeValue(forKey: iKey) {
      totalBytes = max(0, totalBytes - existing.byteCost)
    }
    generationCounter &+= 1
    entries[iKey] = StoredImage(entry: entry, byteCost: cost, generation: generationCounter)
    totalBytes += cost

    while entries.count > capacity || (totalBytes > maxBytes && entries.count > 1) {
      guard let oldest = entries.min(by: { $0.value.generation < $1.value.generation }) else {
        break
      }
      entries.removeValue(forKey: oldest.key)
      totalBytes = max(0, totalBytes - oldest.value.byteCost)
    }
    lock.unlock()
    return entry
  }
}
