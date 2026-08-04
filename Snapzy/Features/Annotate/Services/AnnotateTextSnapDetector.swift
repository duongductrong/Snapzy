//
//  AnnotateTextSnapDetector.swift
//  Snapzy
//
//  Vision text-line detection for highlighter text snapping. Produces line and
//  word geometry only — the recognized strings are never surfaced, they are
//  used solely to derive word-edge x positions.
//

import CoreGraphics
import Foundation
import Vision

/// One detected line of text, in annotation image points (bottom-left origin).
struct AnnotateTextLine: Equatable, Sendable {
  /// Line box in image points.
  let bounds: CGRect
  /// Sorted x positions of every word's leading and trailing edge, clamped to
  /// `bounds`. Always contains at least `bounds.minX` and `bounds.maxX`.
  let wordEdges: [CGFloat]
}

/// Detected text lines of one image, ordered top → bottom (descending midY).
struct AnnotateTextLineProfile: Equatable, Sendable {
  let lines: [AnnotateTextLine]

  static let empty = AnnotateTextLineProfile(lines: [])

  var isEmpty: Bool { lines.isEmpty }
}

enum AnnotateTextSnapDetector {
  /// Lines shorter than this (in image points) are noise for highlighting.
  private static let minimumLineWidth: CGFloat = 6
  private static let minimumLineHeight: CGFloat = 4
  /// A "line" taller than this fraction of the image is a logo/heading blob
  /// rather than running text; snapping to it would look wrong.
  private static let maximumLineHeightRatio: CGFloat = 0.25
  private static let minimumConfidence: Float = 0.3

  /// Detect text lines in `image`. Safe to call off the main actor.
  ///
  /// - Parameters:
  ///   - image: source pixels.
  ///   - imagePointSize: point size the annotation coordinates use
  ///     (`NSImage.size`); differs from pixel size on retina captures.
  nonisolated static func detectLines(
    in image: CGImage,
    imagePointSize: CGSize
  ) -> AnnotateTextLineProfile {
    guard imagePointSize.width > 0, imagePointSize.height > 0 else { return .empty }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    // Only geometry is consumed, so the language-correction pass is pure cost.
    request.usesLanguageCorrection = false
    request.minimumTextHeight = 0.008

    do {
      try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    } catch {
      return .empty
    }

    guard let observations = request.results as? [VNRecognizedTextObservation] else {
      return .empty
    }

    let lines = observations.compactMap { observation -> AnnotateTextLine? in
      textLine(from: observation, imagePointSize: imagePointSize)
    }

    return AnnotateTextLineProfile(lines: lines.sorted { $0.bounds.midY > $1.bounds.midY })
  }

  /// Vision normalized box → image points. Both spaces use a bottom-left
  /// origin, so only scaling is needed (no Y flip).
  nonisolated static func imagePointRect(
    fromVisionBoundingBox boundingBox: CGRect,
    imagePointSize: CGSize
  ) -> CGRect {
    CGRect(
      x: boundingBox.minX * imagePointSize.width,
      y: boundingBox.minY * imagePointSize.height,
      width: boundingBox.width * imagePointSize.width,
      height: boundingBox.height * imagePointSize.height
    ).standardized
  }

  private nonisolated static func textLine(
    from observation: VNRecognizedTextObservation,
    imagePointSize: CGSize
  ) -> AnnotateTextLine? {
    guard observation.confidence >= minimumConfidence,
          let candidate = observation.topCandidates(1).first else { return nil }

    let bounds = imagePointRect(
      fromVisionBoundingBox: observation.boundingBox,
      imagePointSize: imagePointSize
    )
    guard bounds.width >= minimumLineWidth,
          bounds.height >= minimumLineHeight,
          bounds.height <= imagePointSize.height * maximumLineHeightRatio else { return nil }

    return AnnotateTextLine(
      bounds: bounds,
      wordEdges: wordEdges(in: candidate, lineBounds: bounds, imagePointSize: imagePointSize)
    )
  }

  /// Leading/trailing x of every whitespace-delimited word. Vision resolves the
  /// box per character range, so ranges that fail simply contribute nothing.
  private nonisolated static func wordEdges(
    in candidate: VNRecognizedText,
    lineBounds: CGRect,
    imagePointSize: CGSize
  ) -> [CGFloat] {
    let text = candidate.string
    var edges: [CGFloat] = [lineBounds.minX, lineBounds.maxX]

    for wordRange in text.wordRanges() {
      guard let box = try? candidate.boundingBox(for: wordRange) else { continue }
      let rect = imagePointRect(fromVisionBoundingBox: box.boundingBox, imagePointSize: imagePointSize)
      guard rect.width > 0 else { continue }
      edges.append(max(lineBounds.minX, min(rect.minX, lineBounds.maxX)))
      edges.append(max(lineBounds.minX, min(rect.maxX, lineBounds.maxX)))
    }

    return edges.sorted()
  }
}

private extension String {
  /// Ranges of whitespace-delimited words, in order.
  func wordRanges() -> [Range<String.Index>] {
    var ranges: [Range<String.Index>] = []
    var wordStart: String.Index?

    for index in indices {
      if self[index].isWhitespace {
        if let start = wordStart {
          ranges.append(start..<index)
          wordStart = nil
        }
      } else if wordStart == nil {
        wordStart = index
      }
    }

    if let start = wordStart {
      ranges.append(start..<endIndex)
    }
    return ranges
  }
}
