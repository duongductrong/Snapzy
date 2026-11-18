//
//  VideoEditorSourceTrackLayout.swift
//  Snapzy
//
//  Places SOURCE-time ranges (captions, hidden-camera stretches) on the structural
//  timeline: one piece per primary clip the range plays in, so a range split by a cut
//  shows as two blocks and reordered clips carry their pieces along.
//

import CoreGraphics
import Foundation

nonisolated enum VideoEditorSourceTrackLayout {
  struct Piece: Identifiable, Equatable {
    let rangeID: UUID
    let placementID: UUID
    /// Structural timeline seconds where the piece starts.
    let sequenceStart: TimeInterval
    let x: CGFloat
    let width: CGFloat

    var id: String { "\(rangeID)-\(placementID)" }
  }

  static func pieces(
    _ ranges: [(id: UUID, start: TimeInterval, end: TimeInterval)],
    placements: [TimelineSequence.Placement],
    duration: TimeInterval,
    width: CGFloat,
    minimumWidth: CGFloat = 4
  ) -> [Piece] {
    guard duration > 0, width > 0 else { return [] }
    var result: [Piece] = []
    for placement in placements where placement.clip.isPrimary {
      let low = max(placement.sourceAxisStart, placement.clip.sourceStart)
      let high = min(placement.sourceAxisEnd, placement.clip.sourceEnd)
      for range in ranges where range.end > low && range.start < high {
        let start = placement.sequenceTime(atSource: max(range.start, low))
        let end = placement.sequenceTime(atSource: min(range.end, high))
        result.append(Piece(
          rangeID: range.id,
          placementID: placement.id,
          sequenceStart: start,
          x: start / duration * width,
          width: max((end - start) / duration * width, minimumWidth)
        ))
      }
    }
    return result
  }
}
