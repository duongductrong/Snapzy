//
//  VideoEditorTimelineCut.swift
//  Snapzy
//
//  Pure math for removing a structural timeline range from the clip sequence
//  (agent `cut_range`), and for sliding effect blocks to follow the cut.
//
//  The structural axis lays clips out by their fixed slots, so a cut works on
//  slots: clips inside the range go, clips crossing an edge are cut down to the
//  part outside it, and a clip spanning the whole range splits in two. A leftover
//  piece with less than `TimelineClip.minDuration` of slot or of active material
//  is dropped too, and its span is reported as removed so effects can follow.
//

import Foundation

nonisolated enum VideoEditorTimelineCut {
  struct Result: Equatable {
    let clips: [TimelineClip]
    /// Removed spans on the OLD structural axis, sorted and merged.
    let removed: [ClosedRange<TimeInterval>]
  }

  /// Nil when the range misses the sequence or the cut would leave no clip.
  static func cut(_ clips: [TimelineClip], range: ClosedRange<TimeInterval>) -> Result? {
    let placements = TimelineSequence.layout(clips)
    guard let total = placements.last?.end else { return nil }
    let lo = max(0, range.lowerBound)
    let hi = min(total, range.upperBound)
    guard hi - lo > 0.0001 else { return nil }

    let placementByIndex = Dictionary(uniqueKeysWithValues: placements.map { ($0.index, $0) })
    var output: [TimelineClip] = []
    var removed: [ClosedRange<TimeInterval>] = []

    for (index, clip) in clips.enumerated() {
      guard let placement = placementByIndex[index], placement.end > lo, placement.start < hi else {
        output.append(clip)
        continue
      }
      removed.append(max(lo, placement.start) ... min(hi, placement.end))

      // Up to two pieces survive: before the range and after it, in source time.
      var pieces: [(slot: ClosedRange<TimeInterval>, span: ClosedRange<TimeInterval>)] = []
      if lo > placement.start {
        pieces.append((clip.slotStart ... placement.sourceTime(at: lo), placement.start ... lo))
      }
      if hi < placement.end {
        pieces.append((placement.sourceTime(at: hi) ... clip.slotEnd, hi ... placement.end))
      }

      var keptOriginalID = false
      for piece in pieces {
        let activeStart = max(clip.sourceStart, piece.slot.lowerBound)
        let activeEnd = min(clip.sourceEnd, piece.slot.upperBound)
        guard piece.slot.upperBound - piece.slot.lowerBound >= TimelineClip.minDuration,
              activeEnd - activeStart >= TimelineClip.minDuration
        else {
          removed.append(piece.span)
          continue
        }
        // The first surviving piece keeps the clip's identity so references stay valid.
        output.append(TimelineClip(
          id: keptOriginalID ? UUID() : clip.id,
          source: clip.source,
          sourceDuration: clip.sourceDuration,
          sourceStart: activeStart,
          sourceEnd: activeEnd,
          slotStart: piece.slot.lowerBound,
          slotEnd: piece.slot.upperBound
        ))
        keptOriginalID = true
      }
    }

    guard !output.isEmpty else { return nil }
    return Result(clips: output, removed: merged(removed))
  }

  /// Where an old structural time lands after the removed spans close up.
  static func shifted(_ time: TimeInterval, removing removed: [ClosedRange<TimeInterval>]) -> TimeInterval {
    var shift: TimeInterval = 0
    for span in removed where span.lowerBound < time {
      shift += min(time, span.upperBound) - span.lowerBound
    }
    return max(0, time - shift)
  }

  /// An effect block after the cut: shifted, shortened where it crossed a removed
  /// span, or nil when less than `minDuration` of it is left.
  static func shifted(
    start: TimeInterval,
    end: TimeInterval,
    removing removed: [ClosedRange<TimeInterval>],
    minDuration: TimeInterval
  ) -> ClosedRange<TimeInterval>? {
    let newStart = shifted(start, removing: removed)
    let newEnd = shifted(end, removing: removed)
    guard newEnd - newStart >= minDuration - 0.0001 else { return nil }
    return newStart ... newEnd
  }

  static func merged(_ spans: [ClosedRange<TimeInterval>]) -> [ClosedRange<TimeInterval>] {
    let sorted = spans.filter { $0.upperBound - $0.lowerBound > 0.0001 }.sorted { $0.lowerBound < $1.lowerBound }
    var result: [ClosedRange<TimeInterval>] = []
    for span in sorted {
      if let last = result.last, span.lowerBound <= last.upperBound + 0.0001 {
        result[result.count - 1] = last.lowerBound ... max(last.upperBound, span.upperBound)
      } else {
        result.append(span)
      }
    }
    return result
  }
}
