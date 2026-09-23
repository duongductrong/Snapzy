//
//  ScrollingCaptureOffsetVerifier.swift
//  Snapzy
//
//  Checks a candidate scroll offset against the two frames it claims to
//  describe, judging only rows that carry content.
//

import Foundation

/// Score-based matching cannot separate offsets on a page with large flat
/// areas: white matches white at every offset, so many candidates tie and the
/// correct one is discarded as ambiguous.
///
/// The verification asks the definition of the offset instead. If content moved
/// up by `offset`, row `y` of the current frame is row `y + offset` of the
/// previous one, and that must hold across the whole overlap — not just the
/// bands the search sampled. Rows that carry no contrast are left out, because
/// they agree however the frames are aligned, and a repeated layout that
/// matches over a narrow band does not survive the whole-overlap check.
nonisolated enum ScrollingCaptureOffsetVerifier {
  /// Luma difference above which one sample is judged not to match. Generous,
  /// because a correct offset still differs where text was re-rasterised, a
  /// caret blinked, or an image finished decoding between frames.
  static let maximumSampleDifference = 24
  /// Share of a row's contrasty samples that must agree for the row to match.
  ///
  /// Counted per sample rather than averaged over the row. A repeating layout
  /// lines up at a multiple of its period everywhere except the few columns
  /// that differ, and a mean over the row hides that minority: the rows read as
  /// matching and a wrong repeat is confirmed.
  static let minimumMatchingSampleFraction = 0.8
  /// Overlap smaller than this proves nothing.
  static let minimumOverlapRows = 16
  /// A row that varies by less than this, both along its width and against the
  /// row above it, counts as background and is left out.
  static let backgroundRowSpread = 12
  /// Rows with content needed before the verdict means anything.
  static let minimumInformativeRows = 4
  /// Share of those rows that must agree. Not all of them, because a capture
  /// region can hold fixed chrome that no offset makes agree.
  static let minimumMatchingRowFraction = 0.5

  enum Verdict {
    case verified
    case rejected
    /// The overlap carries too little content to judge, so the caller should
    /// fall back to its own scoring.
    case noEvidence

    var isVerified: Bool { self == .verified }
  }

  /// - Returns: true when `offset` is consistent with the two frames. An
  ///   overlap with too little content to judge counts as unverified.
  static func matches(
    previous: ScrollingCaptureLumaPlane,
    current: ScrollingCaptureLumaPlane,
    offset: Int,
    headerHeight: Int = 0,
    footerHeight: Int = 0,
    columnStart: Int = 0,
    columnEnd: Int? = nil
  ) -> Bool {
    verdict(
      previous: previous,
      current: current,
      offset: offset,
      headerHeight: headerHeight,
      footerHeight: footerHeight,
      columnStart: columnStart,
      columnEnd: columnEnd
    ).isVerified
  }

  /// Judges `offset` against the two frames it claims to describe.
  static func verdict(
    previous: ScrollingCaptureLumaPlane,
    current: ScrollingCaptureLumaPlane,
    offset: Int,
    headerHeight: Int = 0,
    footerHeight: Int = 0,
    columnStart: Int = 0,
    columnEnd: Int? = nil
  ) -> Verdict {
    guard
      offset > 0,
      previous.width == current.width,
      previous.height == current.height
    else { return .rejected }

    let firstColumn = max(0, columnStart)
    let lastColumn = min(previous.width, columnEnd ?? previous.width)
    let columnSpan = lastColumn - firstColumn
    guard columnSpan > 1 else { return .noEvidence }

    // Rows of `current` that should have come from `previous`, skipping fixed
    // chrome at either edge: those rows match at every offset.
    let lower = headerHeight
    let upper = previous.height - footerHeight - offset
    guard upper - lower >= minimumOverlapRows else { return .noEvidence }

    let rowStep = max(1, (upper - lower) / 64)
    let columnStep = max(1, columnSpan / 32)

    var informativeRows = 0
    var matchedRows = 0

    /// Whether this row of `current` is unchanged from the same row of
    /// `previous`, which is what fixed chrome looks like.
    func stayedPut(row: Int, contrastySamples: Int) -> Bool {
      var unchanged = 0
      var judged = 0
      for column in stride(from: firstColumn, to: lastColumn, by: columnStep) {
        let currentValue = current.value(x: column, y: row)
        let neighbour = current.value(x: min(lastColumn - 1, column + columnStep), y: row)
        guard abs(currentValue - neighbour) >= backgroundRowSpread else { continue }
        judged += 1
        if abs(currentValue - previous.value(x: column, y: row)) <= maximumSampleDifference {
          unchanged += 1
        }
      }
      guard judged >= 3 else { return false }
      return Double(unchanged) / Double(judged) >= minimumMatchingSampleFraction
    }

    for row in stride(from: lower, to: upper, by: rowStep) {
      var agreeingSamples = 0
      var contrastySamples = 0
      var rowSamples = 0
      var minimum = 255
      var maximum = 0
      var verticalChange = 0
      let rowAbove = max(0, row - 1)

      for column in stride(from: firstColumn, to: lastColumn, by: columnStep) {
        let currentValue = current.value(x: column, y: row)
        let previousValue = previous.value(x: column, y: row + offset)
        minimum = min(minimum, currentValue)
        maximum = max(maximum, currentValue)
        verticalChange = max(verticalChange, abs(currentValue - current.value(x: column, y: rowAbove)))
        rowSamples += 1

        // Only samples that carry contrast say anything: flat background agrees
        // however the frames are aligned.
        let neighbour = current.value(x: min(lastColumn - 1, column + columnStep), y: row)
        guard abs(currentValue - neighbour) >= backgroundRowSpread else { continue }
        contrastySamples += 1
        if abs(currentValue - previousValue) <= maximumSampleDifference { agreeingSamples += 1 }
      }

      // Both directions count: a line of text varies along its width, while a
      // horizontal rule is flat across but differs sharply from the row above.
      let spread = max(maximum - minimum, verticalChange)
      guard rowSamples > 0, spread >= backgroundRowSpread, contrastySamples >= 3 else { continue }
      // A row that did not move is fixed chrome — a toolbar, a pinned header, a
      // prompt box — and no offset makes it agree. On a window capture such
      // rows can outnumber the scrolling content and vote down the true
      // offset, so they say nothing either way.
      guard !stayedPut(row: row, contrastySamples: contrastySamples) else { continue }
      informativeRows += 1
      if Double(agreeingSamples) / Double(contrastySamples) >= minimumMatchingSampleFraction {
        matchedRows += 1
      }
    }

    guard informativeRows >= minimumInformativeRows else { return .noEvidence }
    return Double(matchedRows) / Double(informativeRows) >= minimumMatchingRowFraction
      ? .verified
      : .rejected
  }
}
