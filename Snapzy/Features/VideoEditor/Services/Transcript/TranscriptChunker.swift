//
//  TranscriptChunker.swift
//  Snapzy
//
//  Splits a recording into chunks for engines with a length limit, cutting at
//  silences, and runs a recognizer over them with retries. Pure logic: the
//  recognizer is injected, so offsets, retries and partial failure are testable.
//

import Foundation

nonisolated enum TranscriptChunker {
  /// Chunks no longer than `maxLength`, each cut at the middle of the latest silence in the
  /// back half of its window (hard cut when there is none). Covers `0 ... duration` without gaps.
  static func plan(
    duration: TimeInterval,
    silences: [ClosedRange<TimeInterval>],
    maxLength: TimeInterval = 50
  ) -> [ClosedRange<TimeInterval>] {
    guard duration > 0, maxLength > 0 else { return [] }
    var chunks: [ClosedRange<TimeInterval>] = []
    var start = 0.0
    while start < duration - 1e-6 {
      let limit = start + maxLength
      if limit >= duration {
        chunks.append(start ... duration)
        break
      }
      let cut = silences
        .map { ($0.lowerBound + $0.upperBound) / 2 }
        .filter { $0 > start + maxLength / 2 && $0 <= limit }
        .max() ?? limit
      chunks.append(start ... cut)
      start = cut
    }
    return chunks
  }

  /// Recognizes each chunk (words relative to the chunk start), retrying a failing chunk
  /// `retries` more times. A chunk that keeps failing becomes an unrecognized span; the file
  /// only fails when nothing at all could be recognized, or on cancellation / permission errors.
  static func run(
    chunks: [ClosedRange<TimeInterval>],
    retries: Int = 2,
    cancel: TranscriptCancelFlag? = nil,
    progress: (@Sendable (Double) -> Void)? = nil,
    recognize: (ClosedRange<TimeInterval>) async throws -> [VideoEditorTranscriptWord]
  ) async throws -> TranscriptResult {
    var result = TranscriptResult(words: [])
    var lastError: Error?
    var succeeded = 0
    for (index, chunk) in chunks.enumerated() {
      var words: [VideoEditorTranscriptWord]?
      for _ in 0 ... max(retries, 0) {
        try cancel?.check()
        do {
          words = try await recognize(chunk)
          break
        } catch is CancellationError {
          throw CancellationError()
        } catch VideoEditorTranscriptError.denied {
          throw VideoEditorTranscriptError.denied
        } catch VideoEditorTranscriptError.unsupported(let language) {
          throw VideoEditorTranscriptError.unsupported(language)
        } catch {
          lastError = error
        }
      }
      if let words {
        succeeded += 1
        result.words += words.map {
          VideoEditorTranscriptWord(start: $0.start + chunk.lowerBound, duration: $0.duration, text: $0.text)
        }
      } else {
        result.unrecognizedSpans.append(chunk)
      }
      progress?(Double(index + 1) / Double(chunks.count))
    }
    if succeeded == 0, !chunks.isEmpty {
      throw lastError ?? VideoEditorTranscriptError.failed("no chunk could be recognized")
    }
    result.words.sort { $0.start < $1.start }
    return result
  }
}
