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
  /// Mean luma difference above which a row is judged not to match. Generous,
  /// because a correct offset still differs where content animated, a caret
  /// blinked, or an image finished decoding between frames.
  static let maximumMeanDifference = 14.0
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

  /// - Parameter requiresEvidence: when true, an overlap with too few
  ///   informative rows is reported as unverified rather than accepted.
  /// - Returns: true when `offset` is consistent with the two frames.
  static func matches(
    previous: ScrollingCaptureLumaPlane,
    current: ScrollingCaptureLumaPlane,
    offset: Int,
    headerHeight: Int = 0,
    footerHeight: Int = 0,
    columnStart: Int = 0,
    columnEnd: Int? = nil,
    requiresEvidence: Bool = true
  ) -> Bool {
    guard
      offset > 0,
      previous.width == current.width,
      previous.height == current.height
    else { return false }

    let firstColumn = max(0, columnStart)
    let lastColumn = min(previous.width, columnEnd ?? previous.width)
    let columnSpan = lastColumn - firstColumn
    guard columnSpan > 1 else { return false }

    // Rows of `current` that should have come from `previous`, skipping fixed
    // chrome at either edge: those rows match at every offset.
    let lower = headerHeight
    let upper = previous.height - footerHeight - offset
    guard upper - lower >= minimumOverlapRows else { return false }

    let rowStep = max(1, (upper - lower) / 64)
    let columnStep = max(1, columnSpan / 32)

    var informativeRows = 0
    var matchedRows = 0

    for row in stride(from: lower, to: upper, by: rowStep) {
      var rowTotal = 0
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
        rowTotal += abs(currentValue - previousValue)
        rowSamples += 1
      }

      // Both directions count: a line of text varies along its width, while a
      // horizontal rule is flat across but differs sharply from the row above.
      let spread = max(maximum - minimum, verticalChange)
      guard rowSamples > 0, spread >= backgroundRowSpread else { continue }
      informativeRows += 1
      if Double(rowTotal) / Double(rowSamples) <= maximumMeanDifference { matchedRows += 1 }
    }

    guard informativeRows >= minimumInformativeRows else { return !requiresEvidence }
    return Double(matchedRows) / Double(informativeRows) >= minimumMatchingRowFraction
  }
}
