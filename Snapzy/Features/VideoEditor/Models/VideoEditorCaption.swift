//
//  VideoEditorCaption.swift
//  Snapzy
//
//  A caption in SOURCE time of the primary recording (like the transcript it comes
//  from), so cutting, reordering or re-speeding the timeline never needs a regenerate.
//

import Foundation

nonisolated struct CaptionSegment: Identifiable, Equatable, Sendable, Codable {
  var id: UUID = UUID()
  var sourceRange: ClosedRange<TimeInterval>
  var text: String
  /// The words the segment was built from, when known (for re-timing after a text edit).
  var words: [VideoEditorTranscriptWord]?

  var start: TimeInterval { sourceRange.lowerBound }
  var end: TimeInterval { sourceRange.upperBound }
}

/// Shape limits for generated captions.
nonisolated struct VideoEditorCaptionSegmenterOptions: Equatable, Sendable {
  var maxCharsPerLine = 42
  var maxLines = 2
  var minDuration: TimeInterval = 1
  var maxDuration: TimeInterval = 6
  /// A silence longer than this always starts a new caption.
  var pauseBreak: TimeInterval = 0.6

  var maxCharacters: Int { max(maxCharsPerLine * maxLines, 1) }
}
