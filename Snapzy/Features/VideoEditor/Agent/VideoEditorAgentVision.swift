//
//  VideoEditorAgentVision.swift
//  Snapzy
//
//  What is on screen in the recording, for `get_frame`, `find_on_screen` and
//  `add_zoom(text:)`:
//
//  - frames: `AVAssetImageGenerator` on the clip's own asset (raw footage: no zoom,
//    no background), so boxes are in the same space as zoom centers.
//  - text: Vision OCR on frames sampled across the timeline (at most
//    `maximumSamples`, at least `minimumStep` apart), lazily, only when asked.
//    Each first sighting is narrowed down by bisection so a zoom starts when the
//    text appears, not when the next sample happened to see it.
//
//  OCR results are cached per source file and source time, so a second search,
//  or the same search after a cut, reads frames it already read from memory.
//

import AVFoundation
import CoreGraphics
import Foundation

// MARK: - Results

/// One line of text on screen. `box` is [x, y, w, h] from 0 to 1, origin top left.
nonisolated struct VideoEditorScreenText: Equatable, Sendable {
  let text: String
  let box: CGRect
}

/// Where a text shows on the timeline: first and last sample that saw it.
nonisolated struct VideoEditorTextAppearance: Equatable {
  var start: TimeInterval
  var end: TimeInterval
  /// The whole line the text was found in.
  let line: String
  /// The matched words' box (estimated within the line).
  let box: CGRect
}

nonisolated struct VideoEditorTextSearch: Equatable {
  let appearances: [VideoEditorTextAppearance]
  /// Seconds between samples; an appearance may begin up to this much earlier when it wasn't narrowed.
  let step: TimeInterval
  let samples: Int
  /// Lines seen most often, for a search that found nothing.
  let commonLines: [String]
}

nonisolated enum VideoEditorVisionError: Error, Equatable {
  /// Nothing plays at that time (trimmed-out footage or past the end).
  case noFootage(TimeInterval)
}

// MARK: - Vision

@MainActor
final class VideoEditorAgentVision {
  typealias Recognizer = @Sendable (CGImage) async throws -> [VideoEditorScreenText]

  /// `get_frame` image size, same as the endpoint screenshot.
  nonisolated static let frameEdge: CGFloat = AgentEndpointProvider.maximumImageEdge
  /// OCR frames: large enough for UI text on a Retina recording.
  nonisolated static let textEdge: CGFloat = 2048
  nonisolated static let maximumSamples = 60
  nonisolated static let minimumStep: TimeInterval = 1
  /// Bisection stops when a first sighting is known to this precision.
  nonisolated static let refinePrecision: TimeInterval = 0.25
  /// Only the first few appearances are narrowed down; the rest keep the sample time.
  nonisolated static let refinedAppearances = 4
  private nonisolated static let parallelism = 3

  private struct Key: Hashable {
    let url: URL
    let millis: Int
  }

  /// Where a timeline time's frame comes from.
  private struct Source {
    let asset: AVAsset
    let key: Key
    let sourceTime: TimeInterval
  }

  private let recognizer: Recognizer
  private var textCache: [Key: [VideoEditorScreenText]] = [:]
  private var fileAssets: [URL: AVAsset] = [:]

  init(recognizer: @escaping Recognizer = VideoEditorAgentVision.recognizeText) {
    self.recognizer = recognizer
  }

  // MARK: Frames

  /// The raw frame at a timeline time, at most `edge` on its long side.
  func frame(at time: TimeInterval, in state: VideoEditorState, edge: CGFloat = frameEdge) async throws -> CGImage {
    guard let source = source(at: time, in: state) else { throw VideoEditorVisionError.noFootage(time) }
    return try await Self.image(asset: source.asset, at: source.sourceTime, edge: edge, tolerance: 0.04)
  }

  /// Text on screen at a timeline time (OCR, cached).
  func text(at time: TimeInterval, in state: VideoEditorState) async throws -> [VideoEditorScreenText] {
    guard let source = source(at: time, in: state) else { throw VideoEditorVisionError.noFootage(time) }
    return try await text(for: source)
  }

  private func text(for source: Source) async throws -> [VideoEditorScreenText] {
    if let cached = textCache[source.key] { return cached }
    let recognizer = self.recognizer
    let asset = source.asset
    let time = source.sourceTime
    let lines = try await Task.detached(priority: .userInitiated) {
      let image = try await Self.image(asset: asset, at: time, edge: Self.textEdge, tolerance: 0.1)
      return try await recognizer(image)
    }.value
    textCache[source.key] = lines
    return lines
  }

  private func source(at time: TimeInterval, in state: VideoEditorState) -> Source? {
    guard let context = state.sourceContext(atSequence: time) else { return nil }
    let clip = context.clip
    // Trimmed-out footage is still in the structural layout; it doesn't play.
    guard context.sourceTime >= clip.sourceStart - 0.001, context.sourceTime <= clip.sourceEnd + 0.001 else { return nil }
    let asset: AVAsset
    let url: URL
    switch clip.source {
    case .primary:
      asset = state.asset
      url = state.editingSourceURL
    case .file(let fileURL):
      url = fileURL
      if let cached = fileAssets[fileURL] {
        asset = cached
      } else {
        asset = AVURLAsset(url: fileURL)
        fileAssets[fileURL] = asset
      }
    }
    // Frames 0.1 s apart read the same text; cache at that grain.
    let millis = Int((context.sourceTime * 10).rounded()) * 100
    return Source(asset: asset, key: Key(url: url, millis: millis), sourceTime: context.sourceTime)
  }

  nonisolated static func image(asset: AVAsset, at time: TimeInterval, edge: CGFloat, tolerance: TimeInterval) async throws -> CGImage {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: edge, height: edge)
    let window = CMTime(seconds: tolerance, preferredTimescale: 600)
    generator.requestedTimeToleranceBefore = window
    generator.requestedTimeToleranceAfter = window
    return try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
  }

  // MARK: Search

  /// Where `query` shows on screen within `window` of the timeline.
  func find(_ query: String, in window: ClosedRange<TimeInterval>, state: VideoEditorState) async throws -> VideoEditorTextSearch {
    let times = Self.sampleTimes(spans: Self.footageSpans(state.placements), window: window)
    let step = Self.step(spans: Self.footageSpans(state.placements), window: window)

    // Read the samples, a few at a time.
    var sightings: [(time: TimeInterval, lines: [VideoEditorScreenText])] = []
    var pending: [(TimeInterval, Source)] = []
    for time in times {
      guard let source = source(at: time, in: state) else { continue }
      if let cached = textCache[source.key] {
        sightings.append((time, cached))
      } else {
        pending.append((time, source))
      }
    }
    var index = 0
    while index < pending.count {
      try Task.checkCancellation()
      let batch = pending[index ..< min(index + Self.parallelism, pending.count)]
      index += batch.count
      // A frame that can't be read is skipped; the others still count.
      await withTaskGroup(of: (TimeInterval, [VideoEditorScreenText])?.self) { group in
        for (time, source) in batch {
          group.addTask { @MainActor in
            guard let lines = try? await self.text(for: source) else { return nil }
            return (time, lines)
          }
        }
        for await result in group {
          if let result { sightings.append(result) }
        }
      }
    }
    sightings.sort { $0.time < $1.time }

    // Consecutive samples that see it are one appearance.
    var appearances: [VideoEditorTextAppearance] = []
    var previousTime: TimeInterval?
    var previousHit = false
    var gapBefore: [Int: TimeInterval] = [:]
    for sighting in sightings {
      let hit = Self.bestMatch(query, in: sighting.lines)
      let adjacent = previousTime.map { sighting.time - $0 <= step * 1.5 + 0.01 } ?? false
      if let hit {
        if previousHit, adjacent, var last = appearances.last {
          last.end = sighting.time
          appearances[appearances.count - 1] = last
        } else {
          // The text appeared somewhere after the previous (missed) sample, when there is one next to it.
          if adjacent, let previousTime { gapBefore[appearances.count] = previousTime }
          appearances.append(VideoEditorTextAppearance(start: sighting.time, end: sighting.time, line: hit.line, box: hit.box))
        }
      }
      previousHit = hit != nil
      previousTime = sighting.time
    }

    for (position, before) in gapBefore where position < Self.refinedAppearances {
      try Task.checkCancellation()
      appearances[position].start = try await refineStart(
        query, missed: before, seen: appearances[position].start, state: state
      )
    }

    var counts: [String: Int] = [:]
    for sighting in sightings {
      for line in Set(sighting.lines.map(\.text)) { counts[line, default: 0] += 1 }
    }
    let common = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(20).map(\.key)
    return VideoEditorTextSearch(appearances: appearances, step: step, samples: sightings.count, commonLines: common)
  }

  /// Bisect between a sample that missed the text and the next one that saw it.
  private func refineStart(
    _ query: String,
    missed: TimeInterval,
    seen: TimeInterval,
    state: VideoEditorState
  ) async throws -> TimeInterval {
    var low = missed, high = seen
    while high - low > Self.refinePrecision {
      let middle = (low + high) / 2
      let lines = (try? await text(at: middle, in: state)) ?? []
      if Self.bestMatch(query, in: lines) != nil { high = middle } else { low = middle }
    }
    return high
  }

  // MARK: Sampling

  /// Timeline ranges where any footage plays (inserted videos too).
  nonisolated static func footageSpans(_ placements: [TimelineSequence.Placement]) -> [ClosedRange<TimeInterval>] {
    placements
      .filter { $0.activeEnd > $0.activeStart }
      .map { $0.activeStart ... $0.activeEnd }
  }

  nonisolated static func step(spans: [ClosedRange<TimeInterval>], window: ClosedRange<TimeInterval>) -> TimeInterval {
    let length = VideoEditorAgentAnalyzer.intersect(spans, [window], minDuration: 0)
      .reduce(0) { $0 + $1.upperBound - $1.lowerBound }
    return max(minimumStep, length / Double(maximumSamples))
  }

  /// Sample times across the footage inside `window`: every `step`, at least one per span.
  nonisolated static func sampleTimes(spans: [ClosedRange<TimeInterval>], window: ClosedRange<TimeInterval>) -> [TimeInterval] {
    let pieces = VideoEditorAgentAnalyzer.intersect(spans, [window], minDuration: 0)
    let step = step(spans: spans, window: window)
    var times: [TimeInterval] = []
    for piece in pieces {
      let length = piece.upperBound - piece.lowerBound
      guard length > 0.01 else { continue }
      if length < step {
        times.append(piece.lowerBound + length / 2)
        continue
      }
      // Start a little inside the piece so a frame from the previous clip isn't read.
      var t = piece.lowerBound + min(0.05, length / 2)
      while t < piece.upperBound - 0.01 {
        times.append(t)
        t += step
      }
    }
    return times
  }

  // MARK: Matching

  /// Case, accent and spacing don't matter. "đ" is a letter of its own to `folding`; map it too.
  nonisolated static func normalize(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
      .replacingOccurrences(of: "đ", with: "d")
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  /// The line that best holds `query`: the exact label first, then whole-word hits, then the
  /// shortest line containing it (a button rather than a paragraph mentioning it). "OK" inside
  /// "Cookbook" counts only when nothing better is on screen. The box is narrowed to the matched words.
  nonisolated static func bestMatch(_ query: String, in lines: [VideoEditorScreenText]) -> (line: String, box: CGRect)? {
    let wanted = normalize(query)
    guard !wanted.isEmpty else { return nil }
    let compactWanted = wanted.replacingOccurrences(of: " ", with: "")
    var best: (line: String, box: CGRect, rank: Int)?
    for line in lines {
      let text = normalize(line.text)
      guard !text.isEmpty else { continue }
      var box = line.box
      var wholeWord = false
      if let range = text.range(of: wanted) {
        let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
        let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
        wholeWord = !(before?.isLetter ?? false) && !(before?.isNumber ?? false)
          && !(after?.isLetter ?? false) && !(after?.isNumber ?? false)
        // Assume even character widths to place the words inside the line.
        let total = Double(text.count)
        let offset = Double(text.distance(from: text.startIndex, to: range.lowerBound))
        let length = Double(wanted.count)
        box = CGRect(
          x: line.box.minX + line.box.width * offset / total,
          y: line.box.minY,
          width: line.box.width * length / total,
          height: line.box.height
        )
      } else if !text.replacingOccurrences(of: " ", with: "").contains(compactWanted) {
        continue
      }
      // Exact label < whole word (by length) < inside a word (by length).
      let rank = text == wanted ? 0 : (wholeWord ? 1 : 100_000) + text.count
      if best == nil || rank < best!.rank {
        best = (line.text, box, rank)
      }
    }
    return best.map { ($0.line, $0.box) }
  }

  // MARK: OCR

  /// Vision OCR; boxes flipped to top-left origin. Lines under 0.3 confidence are dropped.
  nonisolated static let recognizeText: Recognizer = { image in
    let configuration = VisionRecognitionConfiguration(
      usesLanguageCorrection: true,
      recognitionLanguages: [],
      customWords: [],
      minimumTextHeight: nil,
      automaticallyDetectsLanguage: true
    )
    let observations = try await VisionOCRWorker.recognizeText(in: image, configuration: configuration)
    return observations.compactMap { observation in
      guard let best = observation.candidates.first, best.confidence >= 0.3 else { return nil }
      let box = observation.boundingBox
      return VideoEditorScreenText(
        text: best.string,
        box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
      )
    }
  }
}
