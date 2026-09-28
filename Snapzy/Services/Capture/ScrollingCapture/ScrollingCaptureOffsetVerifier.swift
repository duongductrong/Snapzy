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
  /// Difference below which a sample counts as unchanged from the same place in
  /// the previous frame. Fixed chrome is drawn identically, so this is tight:
  /// content that merely looks similar must not be mistaken for it.
  static let unchangedSampleDifference = 6
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

  /// Rows sampled down the overlap, and samples taken along each row. A sparse
  /// grid cannot separate neighbouring offsets on a page of text: both the
  /// right offset and one a pixel away came back confirmed, and the sweep then
  /// had a band of candidates with nothing to choose between.
  static let rowSamples = 160
  static let columnSamples = 64

  /// What the frames say about an offset, before it is turned into a verdict.
  struct Evidence {
    /// Rows carrying anything at all, judgeable or not. Blank page has none.
    var rowsWithContent: Int
    /// Rows that carry content and are not fixed chrome.
    var informativeRows: Int
    /// Informative rows that agree at this offset.
    var matchingRows: Int

    var matchingFraction: Double {
      informativeRows > 0 ? Double(matchingRows) / Double(informativeRows) : 0
    }
  }

  enum Verdict {
    case verified
    case rejected
    /// The overlap is blank page: no row carries anything to see, so it stitches
    /// seamlessly however the frames are aligned.
    case blank
    /// The overlap carries content, but not in a form this check can judge, so
    /// the caller should fall back to its own scoring.
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
      let evidence = evidence(
        previous: previous,
        current: current,
        offset: offset,
        headerHeight: headerHeight,
        footerHeight: footerHeight,
        columnStart: columnStart,
        columnEnd: columnEnd
      )
    else {
      let comparable = offset > 0
        && previous.width == current.width
        && previous.height == current.height
      return comparable ? .noEvidence : .rejected
    }

    guard evidence.rowsWithContent >= minimumInformativeRows else { return .blank }
    guard evidence.informativeRows >= minimumInformativeRows else { return .noEvidence }
    return evidence.matchingFraction >= minimumMatchingRowFraction ? .verified : .rejected
  }

  /// Counts how the frames answer at `offset`.
  ///
  /// - Returns: nil when the overlap is too small or too narrow to judge.
  static func evidence(
    previous: ScrollingCaptureLumaPlane,
    current: ScrollingCaptureLumaPlane,
    offset: Int,
    headerHeight: Int = 0,
    footerHeight: Int = 0,
    columnStart: Int = 0,
    columnEnd: Int? = nil,
    rowSamples: Int = ScrollingCaptureOffsetVerifier.rowSamples,
    columnSamples: Int = ScrollingCaptureOffsetVerifier.columnSamples
  ) -> Evidence? {
    plan(
      previous: previous,
      current: current,
      headerHeight: headerHeight,
      footerHeight: footerHeight,
      columnStart: columnStart,
      columnEnd: columnEnd,
      rowSamples: rowSamples,
      columnSamples: columnSamples
    )?.evidence(offset: offset)
  }

  /// Everything about a pair of frames that does not depend on the offset:
  /// which sampled rows carry content, which of those are fixed chrome, and
  /// where along each row the contrast sits.
  ///
  /// All of it is a property of `current`, or of `current` against the same row
  /// of `previous`, so it is measured once and reused for every offset a caller
  /// asks about. Reading it again per offset made judging the thousand offsets
  /// of a sweep take seconds a frame.
  struct Plan {
    fileprivate let previous: ScrollingCaptureLumaPlane
    fileprivate let current: ScrollingCaptureLumaPlane
    fileprivate let rows: [Row]
    /// First row below the scrolling area.
    fileprivate let contentBottom: Int
    fileprivate let contentTop: Int

    fileprivate struct Row {
      let y: Int
      /// Columns carrying contrast, with the value `current` holds at each.
      let columns: [Int]
      let values: [Int]
      let hasContent: Bool
      /// Carries content and is not fixed chrome, so an offset has to explain it.
      let isInformative: Bool
    }

    /// Counts how the frames answer at `offset`.
    func evidence(offset: Int) -> Evidence? {
      guard offset > 0 else { return nil }
      let upper = contentBottom - offset
      guard upper - contentTop >= minimumOverlapRows else { return nil }

      var rowsWithContent = 0
      var informativeRows = 0
      var matchedRows = 0

      for row in rows {
        guard row.y < upper else { break }
        if row.hasContent { rowsWithContent += 1 }
        guard row.isInformative else { continue }
        informativeRows += 1

        var agreeing = 0
        for index in row.columns.indices {
          let previousValue = previous.value(x: row.columns[index], y: row.y + offset)
          if abs(row.values[index] - previousValue) <= maximumSampleDifference { agreeing += 1 }
        }
        if Double(agreeing) / Double(row.columns.count) >= minimumMatchingSampleFraction {
          matchedRows += 1
        }
      }

      return Evidence(
        rowsWithContent: rowsWithContent,
        informativeRows: informativeRows,
        matchingRows: matchedRows
      )
    }

    /// Judges `offset` against the two frames it was built from.
    func verdict(offset: Int) -> Verdict {
      guard let evidence = evidence(offset: offset) else {
        return offset > 0 ? .noEvidence : .rejected
      }
      guard evidence.rowsWithContent >= minimumInformativeRows else { return .blank }
      guard evidence.informativeRows >= minimumInformativeRows else { return .noEvidence }
      return evidence.matchingFraction >= minimumMatchingRowFraction ? .verified : .rejected
    }
  }

  /// Measures what the two frames say regardless of offset. Rows are sampled
  /// over the whole scrolling area, so every offset is judged on the same rows
  /// and their answers can be compared.
  ///
  /// - Returns: nil when the frames cannot be compared at all.
  static func plan(
    previous: ScrollingCaptureLumaPlane,
    current: ScrollingCaptureLumaPlane,
    headerHeight: Int = 0,
    footerHeight: Int = 0,
    columnStart: Int = 0,
    columnEnd: Int? = nil,
    rowSamples: Int = ScrollingCaptureOffsetVerifier.rowSamples,
    columnSamples: Int = ScrollingCaptureOffsetVerifier.columnSamples
  ) -> Plan? {
    guard
      previous.width == current.width,
      previous.height == current.height
    else { return nil }

    let firstColumn = max(0, columnStart)
    let lastColumn = min(previous.width, columnEnd ?? previous.width)
    let columnSpan = lastColumn - firstColumn
    guard columnSpan > 1 else { return nil }

    // Rows of `current` that could have come from `previous`, skipping fixed
    // chrome at either edge: those rows match at every offset.
    let contentTop = headerHeight
    let contentBottom = previous.height - footerHeight
    guard contentBottom - contentTop >= minimumOverlapRows else { return nil }

    let rowStep = max(1, (contentBottom - contentTop) / max(1, rowSamples))
    let columnStep = max(1, columnSpan / max(1, columnSamples))

    var rows: [Plan.Row] = []
    rows.reserveCapacity((contentBottom - contentTop) / rowStep + 1)

    for row in stride(from: contentTop, to: contentBottom, by: rowStep) {
      var columns: [Int] = []
      var values: [Int] = []
      var unchanged = 0
      var minimum = 255
      var maximum = 0
      var verticalChange = 0
      var samples = 0
      let rowAbove = max(0, row - 1)

      for column in stride(from: firstColumn, to: lastColumn, by: columnStep) {
        let value = current.value(x: column, y: row)
        minimum = min(minimum, value)
        maximum = max(maximum, value)
        verticalChange = max(verticalChange, abs(value - current.value(x: column, y: rowAbove)))
        samples += 1

        // Samples that carry contrast say the most: flat background agrees
        // however the frames are aligned.
        let neighbour = current.value(x: min(lastColumn - 1, column + columnStep), y: row)
        guard abs(value - neighbour) >= backgroundRowSpread else { continue }
        columns.append(column)
        values.append(value)
        if abs(value - previous.value(x: column, y: row)) <= unchangedSampleDifference {
          unchanged += 1
        }
      }

      // Both directions count: a line of text varies along its width, while a
      // horizontal rule is flat across but differs sharply from the row above.
      let spread = max(maximum - minimum, verticalChange)
      guard samples > 0, spread >= backgroundRowSpread else { continue }

      // A row that did not move is fixed chrome — a toolbar, a pinned header, a
      // prompt box — and no offset makes it agree. On a window capture such
      // rows can outnumber the scrolling content and vote down the true
      // offset, so they say nothing either way.
      let stayedPut = columns.count >= 2
        && Double(unchanged) / Double(columns.count) >= minimumMatchingSampleFraction
      let isInformative = columns.count >= 3 && !stayedPut

      rows.append(
        Plan.Row(
          y: row,
          columns: isInformative ? columns : [],
          values: isInformative ? values : [],
          hasContent: true,
          isInformative: isInformative
        )
      )
    }

    return Plan(
      previous: previous,
      current: current,
      rows: rows,
      contentBottom: contentBottom,
      contentTop: contentTop
    )
  }
}
