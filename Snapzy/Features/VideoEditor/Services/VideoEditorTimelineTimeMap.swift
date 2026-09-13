//
//  VideoEditorTimelineTimeMap.swift
//  Snapzy
//
//  Maps between the video editor's compact playable sequence and its output.
//
//  PLAYABLE sequence time — active clip material laid shoulder to shoulder
//  (`Σ clip.duration`). Trimmed-out slot edges are omitted here because this is the
//  coordinate used by preview playback, speed lookup, and export.
//
//  OUTPUT time — playable sequence time with speed segments applied.
//
//  Speed segments stay authored in PRIMARY SOURCE time and are projected onto the
//  playable sequence, so they follow their material when a clip is moved or reordered.
//

import CoreMedia
import Foundation

struct TimelineSequenceMap: Equatable {
  /// A stretch of sequence time playing at a constant rate.
  struct Span: Equatable {
    let seqStart: TimeInterval
    let seqDuration: TimeInterval
    let rate: Double

    var seqEnd: TimeInterval { seqStart + seqDuration }
    /// Length this span occupies in output time.
    var scaledDuration: TimeInterval { seqDuration / rate }
  }

  /// Contiguous, sorted spans tiling `[0, sequenceDuration]`.
  let spans: [Span]
  let sequenceDuration: TimeInterval
  /// Σ span.scaledDuration — the exported length.
  let outputDuration: TimeInterval

  /// True when no span changes rate, so sequence time == output time.
  var isIdentity: Bool {
    spans.allSatisfy { $0.rate == 1.0 }
  }

  // MARK: - Build

  init(clips: [TimelineClip], speedSegments: [SpeedSegment]) {
    self.init(
      placements: TimelineSequence.playableLayout(clips),
      sequenceDuration: TimelineSequence.playableDuration(clips),
      speedSegments: speedSegments
    )
  }

  init(
    placements: [TimelineSequence.Placement],
    sequenceDuration: TimeInterval,
    speedSegments: [SpeedSegment]
  ) {
    self.sequenceDuration = max(0, sequenceDuration)

    guard self.sequenceDuration > 0.0001 else {
      self.spans = []
      self.outputDuration = 0
      return
    }

    // Project each enabled segment onto the sequence. A segment spanning material
    // that was cut out yields several pieces.
    var rated: [(range: ClosedRange<TimeInterval>, rate: Double)] = []
    for segment in speedSegments where segment.isEnabled && segment.rate != 1.0 {
      let rate = SpeedSegment.clampRate(segment.rate)
      let pieces = TimelineSequence.project(
        sourceRange: segment.startTime...max(segment.startTime, segment.endTime),
        in: placements
      )
      for piece in pieces {
        rated.append((piece, rate))
      }
    }
    rated.sort { $0.range.lowerBound < $1.range.lowerBound }

    var spans: [Span] = []
    var cursor: TimeInterval = 0
    for entry in rated {
      let start = max(cursor, entry.range.lowerBound)
      let end = min(self.sequenceDuration, entry.range.upperBound)
      guard end - start > 0.0001 else { continue }
      if start - cursor > 0.0001 {
        spans.append(Span(seqStart: cursor, seqDuration: start - cursor, rate: 1.0))
      }
      spans.append(Span(seqStart: start, seqDuration: end - start, rate: entry.rate))
      cursor = end
    }
    if self.sequenceDuration - cursor > 0.0001 {
      spans.append(
        Span(seqStart: cursor, seqDuration: self.sequenceDuration - cursor, rate: 1.0)
      )
    }

    self.spans = spans
    self.outputDuration = spans.reduce(0) { $0 + $1.scaledDuration }
  }

  // MARK: - Mapping

  /// SEQUENCE seconds → OUTPUT seconds.
  func toOutput(_ sequence: TimeInterval) -> TimeInterval {
    guard sequence > 0 else { return 0 }
    var acc: TimeInterval = 0
    for span in spans {
      if sequence < span.seqEnd {
        return acc + max(0, sequence - span.seqStart) / span.rate
      }
      acc += span.scaledDuration
    }
    return outputDuration
  }

  /// OUTPUT seconds → SEQUENCE seconds.
  func toSequence(_ output: TimeInterval) -> TimeInterval {
    guard output > 0, !spans.isEmpty else { return 0 }
    var acc: TimeInterval = 0
    for span in spans {
      let scaled = span.scaledDuration
      if output < acc + scaled {
        return span.seqStart + (output - acc) * span.rate
      }
      acc += scaled
    }
    return sequenceDuration
  }

  /// Playback rate active at a SEQUENCE time.
  func rate(atSequence t: TimeInterval) -> Double {
    for span in spans where t >= span.seqStart && t < span.seqEnd {
      return span.rate
    }
    return 1.0
  }

  // MARK: - CMTime convenience

  func outputCMDuration() -> CMTime {
    CMTime(seconds: outputDuration, preferredTimescale: 600)
  }
}
