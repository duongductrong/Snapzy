//
//  VideoEditorTimelineClip.swift
//  Snapzy
//
//  The video editor timeline is an ordered sequence of clips laid shoulder to
//  shoulder. Each clip owns a fixed structural slot; trimming changes only its
//  active source window inside that slot. Cutting splits a slot in two, deleting
//  ripples the rest left, and an added video is simply another clip inserted at an
//  index.
//
//  Replaces the previous "source filmstrip with holes" model (`CutSegment` removed
//  ranges + appended `MergedClip`s), which had no segments to move and left dead
//  hatched regions occupying timeline width.
//

import Foundation

/// One segment of the timeline: a window onto some source asset.
///
/// Trimming is **non-destructive** — a clip keeps `sourceDuration` for its whole
/// backing asset, so dragging an edge outward restores frames trimmed away earlier.
/// The clip also keeps a fixed source slot. The slot is the structural span that
/// remains visible on the timeline; `sourceStart`/`sourceEnd` are the active part
/// that plays and exports.
struct TimelineClip: Identifiable, Equatable, Hashable, Codable {
  /// Which asset backs this clip.
  enum Source: Equatable, Hashable, Codable {
    /// The recording being edited (`state.asset` / `state.sourceURL`).
    case primary
    /// A video appended or inserted by the user.
    case file(url: URL)
  }

  let id: UUID
  let source: Source
  /// Full length of the backing asset — the bound for non-destructive re-extension.
  let sourceDuration: TimeInterval
  /// In-point within the backing asset.
  var sourceStart: TimeInterval
  /// Out-point within the backing asset.
  var sourceEnd: TimeInterval
  /// Start of this clip's fixed structural slot within the backing asset.
  let slotStart: TimeInterval
  /// End of this clip's fixed structural slot within the backing asset.
  let slotEnd: TimeInterval

  /// Shortest a clip may be trimmed. Splitting also refuses to create anything shorter.
  static let minDuration: TimeInterval = 0.1

  var duration: TimeInterval {
    max(0, sourceEnd - sourceStart)
  }

  var slotDuration: TimeInterval {
    max(0, slotEnd - slotStart)
  }

  var isPrimary: Bool {
    if case .primary = source { return true }
    return false
  }

  var url: URL? {
    if case .file(let url) = source { return url }
    return nil
  }

  /// Source range as a range value, for intersection math.
  var sourceRange: ClosedRange<TimeInterval> {
    sourceStart ... max(sourceStart, sourceEnd)
  }

  /// Full structural source slot as a range value.
  var slotRange: ClosedRange<TimeInterval> {
    slotStart ... max(slotStart, slotEnd)
  }

  init(
    id: UUID = UUID(),
    source: Source,
    sourceDuration: TimeInterval,
    sourceStart: TimeInterval = 0,
    sourceEnd: TimeInterval? = nil,
    slotStart: TimeInterval? = nil,
    slotEnd: TimeInterval? = nil
  ) {
    self.id = id
    self.source = source
    self.sourceDuration = max(0, sourceDuration)
    let requestedSlotStart = slotStart ?? sourceStart
    let requestedSlotEnd = slotEnd ?? sourceEnd ?? self.sourceDuration
    var normalizedSlotStart = max(0, min(requestedSlotStart, self.sourceDuration))
    var normalizedSlotEnd = max(normalizedSlotStart, min(requestedSlotEnd, self.sourceDuration))
    if normalizedSlotEnd - normalizedSlotStart < Self.minDuration {
      if normalizedSlotStart + Self.minDuration <= self.sourceDuration {
        normalizedSlotEnd = normalizedSlotStart + Self.minDuration
      } else {
        normalizedSlotEnd = self.sourceDuration
        normalizedSlotStart = max(0, normalizedSlotEnd - Self.minDuration)
      }
    }
    self.slotStart = normalizedSlotStart
    self.slotEnd = normalizedSlotEnd

    let start = max(normalizedSlotStart, min(sourceStart, normalizedSlotEnd))
    let end = min(normalizedSlotEnd, sourceEnd ?? normalizedSlotEnd)
    self.sourceStart = start
    // Keep the clip at least `minDuration` long, preferring to extend the out-point
    // and falling back to pulling the in-point back when there is no room after it.
    if end - start < Self.minDuration {
      if start + Self.minDuration <= normalizedSlotEnd {
        self.sourceEnd = start + Self.minDuration
      } else {
        self.sourceEnd = normalizedSlotEnd
        self.sourceStart = max(normalizedSlotStart, normalizedSlotEnd - Self.minDuration)
      }
    } else {
      self.sourceEnd = end
    }
  }

  func contains(sourceTime: TimeInterval) -> Bool {
    sourceTime >= sourceStart && sourceTime < sourceEnd
  }
}

// MARK: - Sequence Layout

/// Pure math laying clips out on the structural/playable axes and mapping between
/// sequence time (what the playhead and effect tracks use) and source time (what
/// the player and exporter need).
enum TimelineSequence {
  /// A clip together with the span it occupies on the sequence axis.
  struct Placement: Identifiable, Equatable {
    let clip: TimelineClip
    let index: Int
    let start: TimeInterval
    let end: TimeInterval
    /// Source coordinate represented at `start` on this placement. Structural
    /// placements use `clip.slotStart`; playable placements use `clip.sourceStart`.
    let sourceAxisStart: TimeInterval
    let sourceAxisEnd: TimeInterval

    var id: UUID {
      clip.id
    }

    var duration: TimeInterval {
      max(0, end - start)
    }

    var activeStart: TimeInterval {
      start + max(0, min(clip.sourceStart - sourceAxisStart, duration))
    }

    var activeEnd: TimeInterval {
      start + max(0, min(clip.sourceEnd - sourceAxisStart, duration))
    }

    func contains(_ sequenceTime: TimeInterval) -> Bool {
      sequenceTime >= start && sequenceTime < end
    }

    func containsActive(_ sequenceTime: TimeInterval) -> Bool {
      sequenceTime >= activeStart && sequenceTime < activeEnd
    }

    /// Source time corresponding to a sequence time inside this placement.
    func sourceTime(at sequenceTime: TimeInterval) -> TimeInterval {
      sourceAxisStart + max(0, min(sequenceTime - start, duration))
    }

    /// Sequence time corresponding to a source time inside this clip.
    func sequenceTime(atSource sourceTime: TimeInterval) -> TimeInterval {
      start + max(0, min(sourceTime - sourceAxisStart, duration))
    }
  }

  /// Lay clips end to end using their fixed structural slots. Trimmed-out footage
  /// remains in this layout as an inactive portion of its owning clip.
  static func layout(_ clips: [TimelineClip]) -> [Placement] {
    var placements: [Placement] = []
    var cursor: TimeInterval = 0
    for (index, clip) in clips.enumerated() {
      let duration = clip.slotDuration
      guard duration > 0.0001 else { continue }
      placements.append(
        Placement(
          clip: clip,
          index: index,
          start: cursor,
          end: cursor + duration,
          sourceAxisStart: clip.slotStart,
          sourceAxisEnd: clip.slotEnd
        )
      )
      cursor += duration
    }
    return placements
  }

  /// Lay clips end to end using only their active in/out ranges. This is the
  /// playable/export sequence used by the speed map; unlike `layout(_:)`, it
  /// intentionally collapses inactive trim slots.
  static func playableLayout(_ clips: [TimelineClip]) -> [Placement] {
    var placements: [Placement] = []
    var cursor: TimeInterval = 0
    for (index, clip) in clips.enumerated() {
      let duration = clip.duration
      guard duration > 0.0001 else { continue }
      placements.append(
        Placement(
          clip: clip,
          index: index,
          start: cursor,
          end: cursor + duration,
          sourceAxisStart: clip.sourceStart,
          sourceAxisEnd: clip.sourceEnd
        )
      )
      cursor += duration
    }
    return placements
  }

  static func duration(_ clips: [TimelineClip]) -> TimeInterval {
    clips.reduce(0) { $0 + $1.slotDuration }
  }

  static func playableDuration(_ clips: [TimelineClip]) -> TimeInterval {
    clips.reduce(0) { $0 + $1.duration }
  }

  /// Placement covering a sequence time; the last placement answers for the exact
  /// end of the sequence so a playhead parked at the tail still has a clip.
  static func placement(at sequenceTime: TimeInterval, in placements: [Placement]) -> Placement? {
    if let match = placements.first(where: { $0.contains(sequenceTime) }) { return match }
    guard let last = placements.last, sequenceTime >= last.end - 0.0001 else {
      return placements.first
    }
    return last
  }

  /// Placement whose active material is under the sequence time. Structural
  /// placements can answer nil while the playhead is over trimmed-out footage.
  static func activePlacement(at sequenceTime: TimeInterval, in placements: [Placement]) -> Placement? {
    placements.first(where: { $0.containsActive(sequenceTime) })
  }

  /// Project an effect range authored on the structural timeline onto the compact
  /// playable sequence. Structural slots keep trimmed footage visible for stable
  /// editing, while playable placements collapse those inactive edges. The clip ID
  /// is the join key, so cuts, swaps, and inserted clips never reinterpret the
  /// effect's authored position as source time.
  static func project(
    timelineRange: ClosedRange<TimeInterval>,
    from timelinePlacements: [Placement],
    to playablePlacements: [Placement]
  ) -> [ClosedRange<TimeInterval>] {
    guard timelineRange.upperBound - timelineRange.lowerBound > 0.0001 else {
      return []
    }

    var projected: [ClosedRange<TimeInterval>] = []
    for placement in timelinePlacements {
      let start = max(timelineRange.lowerBound, placement.activeStart)
      let end = min(timelineRange.upperBound, placement.activeEnd)
      guard end - start > 0.0001,
            let playable = playablePlacements.first(where: { $0.clip.id == placement.clip.id })
      else { continue }

      let sourceStart = placement.sourceTime(at: start)
      let sourceEnd = placement.sourceTime(at: end)
      let playableStart = playable.sequenceTime(atSource: sourceStart)
      let playableEnd = playable.sequenceTime(atSource: sourceEnd)
      guard playableEnd - playableStart > 0.0001 else { continue }
      projected.append(playableStart ... playableEnd)
    }

    return merged(projected)
  }

  /// Collapse pieces that meet, so a range crossing an untouched split renders as
  /// one block rather than two abutting ones.
  private static func merged(_ ranges: [ClosedRange<TimeInterval>]) -> [ClosedRange<TimeInterval>] {
    guard !ranges.isEmpty else { return [] }
    let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
    var result: [ClosedRange<TimeInterval>] = [sorted[0]]
    for range in sorted.dropFirst() {
      let last = result[result.count - 1]
      if range.lowerBound - last.upperBound <= 0.0001 {
        result[result.count - 1] = last.lowerBound ... max(last.upperBound, range.upperBound)
      } else {
        result.append(range)
      }
    }
    return result
  }
}
