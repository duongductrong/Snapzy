//
//  ScrollingCaptureStickyEdges.swift
//  Snapzy
//
//  Finds fixed chrome along the top and bottom of a scrolling viewport, such
//  as a browser toolbar, a pinned header, a cookie banner, or a floating
//  button, so stitching can keep it out of every strip.
//

import Foundation

nonisolated struct ScrollingCaptureStickyEdges: Equatable {
  /// Heights in image pixels.
  var top: Int
  var bottom: Int

  static let none = ScrollingCaptureStickyEdges(top: 0, bottom: 0)

  init(top: Int, bottom: Int) {
    self.top = max(0, top)
    self.bottom = max(0, bottom)
  }
}

/// Judges each row by the share of its contrasty pixels that stayed put, rather
/// than asking whether the whole row is unchanged. Most chrome does not span
/// the width: a floating button sits in a margin with content scrolling past
/// beside it, so a whole-row test never sees it.
nonisolated enum ScrollingCaptureStickyEdgeDetector {
  /// Luma difference below which a pixel counts as unchanged.
  static let sameRowTolerance = 6
  /// Share of a row's contrasty pixels that must stay put for the row to count
  /// as chrome. Well below a majority because chrome rarely spans the width;
  /// voting across frame pairs keeps coincidental matches out.
  static let chromeRowFraction = 0.4
  /// Contrast a sample needs along its row before it says anything. Flat
  /// background agrees at every offset and would make any row look frozen.
  static let contrastFloor = 12
  /// Contrasty samples a row needs before it can be judged at all.
  static let minimumContrastySamples = 6
  /// Non-chrome rows tolerated inside a band before it is considered finished,
  /// since chrome is not always one solid block.
  static let maximumGapRows = 48

  /// Estimate from one frame pair. Only meaningful when the two frames really
  /// moved: between frames that did not scroll, every row looks frozen.
  static func detect(
    previous: ScrollingCaptureLumaPlane,
    current: ScrollingCaptureLumaPlane,
    maximumFraction: Double = 0.3
  ) -> ScrollingCaptureStickyEdges {
    let samples = chromeRows(previous: previous, current: current, maximumFraction: maximumFraction)
    guard !samples.isEmpty else { return .none }
    var accumulator = ScrollingCaptureStickyEdgeAccumulator()
    for _ in 0..<ScrollingCaptureStickyEdgeAccumulator.minimumVotes {
      accumulator.add(samples)
    }
    return accumulator.edges(frameHeight: previous.height, maximumFraction: maximumFraction)
  }

  /// Verdict per row of the candidate top and bottom regions: true where the row
  /// looks like fixed chrome, false where it scrolled, and absent where it
  /// carries too little contrast to say.
  static func chromeRows(
    previous: ScrollingCaptureLumaPlane,
    current: ScrollingCaptureLumaPlane,
    maximumFraction: Double = 0.3
  ) -> [Int: Bool] {
    guard previous.width == current.width, previous.height == current.height else { return [:] }

    let height = previous.height
    let width = previous.width
    let limit = Int(Double(height) * maximumFraction)
    let columnStep = max(1, width / 80)

    func isChrome(row: Int) -> Bool? {
      var contrasty = 0
      var stayed = 0
      for column in stride(from: 0, to: width, by: columnStep) {
        let value = current.value(x: column, y: row)
        let neighbour = current.value(x: min(width - 1, column + columnStep), y: row)
        guard abs(value - neighbour) >= contrastFloor else { continue }
        contrasty += 1
        if abs(value - previous.value(x: column, y: row)) <= sameRowTolerance {
          stayed += 1
        }
      }
      guard contrasty >= minimumContrastySamples else { return nil }
      return Double(stayed) / Double(contrasty) >= chromeRowFraction
    }

    var samples: [Int: Bool] = [:]
    for row in 0..<limit {
      if let verdict = isChrome(row: row) { samples[row] = verdict }
      let mirrored = height - 1 - row
      if mirrored > row, let verdict = isChrome(row: mirrored) { samples[mirrored] = verdict }
    }
    return samples
  }
}

/// Votes per row across many frame pairs. A single pair is a poor witness: a
/// link-status bar only shows while the pointer rests on a link, and pale rows
/// sometimes carry too little contrast to judge. Chrome is whatever stays put
/// over and over.
nonisolated struct ScrollingCaptureStickyEdgeAccumulator {
  private var judged: [Int: Int] = [:]
  private var chrome: [Int: Int] = [:]
  private(set) var rounds = 0

  /// Pairs a row must be judged in before its votes are trusted.
  static let minimumVotes = 3
  /// Share of a row's judgements that must say chrome.
  static let chromeVoteFraction = 0.5
  /// Rows added to any detected band. The outer rows of chrome are shadow and
  /// antialiasing that rarely vote, so the measurement lands just inside it.
  static let bandMargin = 16
  /// Extra margin that scales with the band, since taller chrome carries a
  /// taller soft edge.
  static let bandMarginFraction = 0.25

  mutating func add(_ samples: [Int: Bool]) {
    guard !samples.isEmpty else { return }
    rounds += 1
    for (row, isChrome) in samples {
      judged[row, default: 0] += 1
      if isChrome { chrome[row, default: 0] += 1 }
    }
  }

  func edges(frameHeight: Int, maximumFraction: Double = 0.3) -> ScrollingCaptureStickyEdges {
    guard frameHeight > 0 else { return .none }
    let limit = Int(Double(frameHeight) * maximumFraction)

    func settled(_ row: Int) -> Bool? {
      guard let total = judged[row], total >= Self.minimumVotes else { return nil }
      return Double(chrome[row] ?? 0) / Double(total) >= Self.chromeVoteFraction
    }

    func bandDepth(_ rows: [Int]) -> Int {
      var depth = 0
      var gap = 0
      for (index, row) in rows.enumerated() {
        switch settled(row) {
        case .some(true):
          depth = index + 1
          gap = 0
        case .some(false):
          gap += 1
          if gap > ScrollingCaptureStickyEdgeDetector.maximumGapRows { return depth }
        case .none:
          continue
        }
      }
      return depth
    }

    func padded(_ depth: Int) -> Int {
      guard depth > 0 else { return 0 }
      let margin = max(Self.bandMargin, Int(Double(depth) * Self.bandMarginFraction))
      return min(limit, depth + margin)
    }

    let top = padded(bandDepth(Array(0..<limit)))
    let bottom = padded(bandDepth((0..<limit).map { frameHeight - 1 - $0 }))
    guard Double(top + bottom) < Double(frameHeight) * 0.5 else { return .none }
    return ScrollingCaptureStickyEdges(top: top, bottom: bottom)
  }
}
