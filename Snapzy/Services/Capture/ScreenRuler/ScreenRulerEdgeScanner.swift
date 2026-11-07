//
//  ScreenRulerEdgeScanner.swift
//  Snapzy
//
//  Screen Ruler edge finding. Both hover spans and drag boxes run one 1D edge finder along
//  rows or columns:
//
//  - A pixel is compared with a running reference (mean of the last few matched pixels), not
//    with the starting pixel, so slow drifts — window gradients, the soft tail of a shadow —
//    never read as an edge.
//  - The threshold adapts to the local noise (trimmed mean neighbor difference), so material
//    noise is ignored while low-contrast edges on flat UI (Δ4) are still found.
//  - Once a pixel deviates, the transition is examined as a whole: the sharpest step in it is
//    the edge, and a transition with no step clearly sharper than its slope (a shadow ramp)
//    is not an edge at all.
//  - The anti-aliased pixel at the edge is counted on whichever side covers most of it.
//

import Foundation

nonisolated enum ScreenRulerEdgeScanner {
  /// Smallest step (0–255, largest channel difference) treated as an edge on noise-free UI.
  static let defaultTolerance = 3
  static let toleranceRange = 0...64

  /// The threshold is at least `noiseFactor × noise + 1`.
  private static let noiseFactor = 3.0
  /// Noise level from which single-pixel deviations need confirmation by the next pixel.
  private static let noisyLevel = 0.5
  /// Share of the smallest neighbor differences averaged into the noise level; the rest are
  /// treated as edges (a hairline near the origin adds two columns of large differences).
  private static let noiseTrim = 0.7
  /// Pixels averaged into the running reference.
  private static let referenceLength = 4
  /// Longest transition examined for its sharpest step.
  private static let maxTransitionLength = 64
  /// An edge's step must be this many times sharper than the rest of its transition.
  private static let sharpnessRatio = 3

  // MARK: - Span

  static func span(
    in raster: ScreenRulerRaster,
    from origin: ColorPickerPixel,
    axis: ScreenRulerAxis,
    tolerance: Int
  ) -> ScreenRulerSpan {
    let x0 = min(max(origin.x, 0), raster.width - 1)
    let y0 = min(max(origin.y, 0), raster.height - 1)
    let noise = noiseLevel(in: raster, around: x0, y0)
    var left = x0
    var right = x0
    var top = y0
    var bottom = y0

    raster.withPixels { pixels in
      let finder = EdgeFinder(raster: raster, pixels: pixels, tolerance: tolerance, noise: noise)
      if axis != .vertical {
        left = x0 - finder.extent(x: x0, y: y0, dx: -1, dy: 0, count: x0 + 1)
        right = x0 + finder.extent(x: x0, y: y0, dx: 1, dy: 0, count: raster.width - x0)
      }
      if axis != .horizontal {
        top = y0 - finder.extent(x: x0, y: y0, dx: 0, dy: -1, count: y0 + 1)
        bottom = y0 + finder.extent(x: x0, y: y0, dx: 0, dy: 1, count: raster.height - y0)
      }
    }

    return ScreenRulerSpan(
      origin: ColorPickerPixel(x: x0, y: y0),
      axis: axis,
      left: left,
      right: right,
      top: top,
      bottom: bottom
    )
  }

  // MARK: - Box

  /// `rect` shrunk to the sharp edges inside it: every row is scanned in from the left and
  /// right border, every column from the top and bottom. Returns `rect` (clamped) unchanged
  /// when nothing inside has a sharp edge, so a box drawn over empty space keeps its size.
  static func snap(
    _ rect: ScreenRulerPixelRect,
    in raster: ScreenRulerRaster,
    tolerance: Int
  ) -> ScreenRulerPixelRect {
    let r = ScreenRulerPixelRect(
      minX: max(rect.minX, 0),
      minY: max(rect.minY, 0),
      maxX: min(rect.maxX, raster.width - 1),
      maxY: min(rect.maxY, raster.height - 1)
    )
    guard r.minX <= r.maxX, r.minY <= r.maxY else { return rect }
    let noise = borderNoiseLevel(of: r, in: raster)

    // Each side keeps the outermost edge over all rows (columns), so once one is found, later
    // lines only need scanning up to it (plus a pixel for anti-aliasing): with content in the
    // box this skips most pixels.
    var minX = Int.max
    var maxX = Int.min
    var minY = Int.max
    var maxY = Int.min
    raster.withPixels { pixels in
      let finder = EdgeFinder(raster: raster, pixels: pixels, tolerance: tolerance, noise: noise)
      for y in r.minY...r.maxY {
        let leftLimit = minX == Int.max ? r.width : min(r.width, minX - r.minX + 2)
        if let fromLeft = finder.edgeIndex(x: r.minX, y: y, dx: 1, dy: 0, count: leftLimit) {
          minX = min(minX, r.minX + fromLeft)
        } else if leftLimit == r.width {
          continue // The whole line has no edge, so scanning it back from the right is moot.
        }
        let rightLimit = maxX == Int.min ? r.width : min(r.width, r.maxX - maxX + 2)
        if let fromRight = finder.edgeIndex(x: r.maxX, y: y, dx: -1, dy: 0, count: rightLimit) {
          maxX = max(maxX, r.maxX - fromRight)
        }
      }
      for x in r.minX...r.maxX {
        let topLimit = minY == Int.max ? r.height : min(r.height, minY - r.minY + 2)
        if let fromTop = finder.edgeIndex(x: x, y: r.minY, dx: 0, dy: 1, count: topLimit) {
          minY = min(minY, r.minY + fromTop)
        } else if topLimit == r.height {
          continue
        }
        let bottomLimit = maxY == Int.min ? r.height : min(r.height, r.maxY - maxY + 2)
        if let fromBottom = finder.edgeIndex(x: x, y: r.maxY, dx: 0, dy: -1, count: bottomLimit) {
          maxY = max(maxY, r.maxY - fromBottom)
        }
      }
    }
    guard minX <= maxX, minY <= maxY else { return r }
    return ScreenRulerPixelRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
  }

  // MARK: - Noise

  /// Mean of the smallest 70% largest-channel differences between horizontal neighbors in a
  /// 9×9 window: 0 on flat UI, a few levels on materials and wallpapers. Edges in the window
  /// fall in the discarded 30%.
  static func noiseLevel(in raster: ScreenRulerRaster, around x: Int, _ y: Int, radius: Int = 4) -> Double {
    var samples: [Int] = []
    samples.reserveCapacity((2 * radius + 1) * (2 * radius))
    for yy in max(y - radius, 0)...min(y + radius, raster.height - 1) {
      let lower = max(x - radius, 0)
      let upper = min(x + radius, raster.width - 1)
      guard lower < upper else { continue }
      for xx in (lower + 1)...upper {
        samples.append(raster.delta(xx, yy, xx - 1, yy))
      }
    }
    return trimmedMean(samples)
  }

  /// Noise along the box border, which the user drew over background.
  private static func borderNoiseLevel(of r: ScreenRulerPixelRect, in raster: ScreenRulerRaster) -> Double {
    var samples: [Int] = []
    if r.minX < r.maxX {
      for x in (r.minX + 1)...r.maxX {
        samples.append(raster.delta(x, r.minY, x - 1, r.minY))
        samples.append(raster.delta(x, r.maxY, x - 1, r.maxY))
      }
    }
    if r.minY < r.maxY {
      for y in (r.minY + 1)...r.maxY {
        samples.append(raster.delta(r.minX, y, r.minX, y - 1))
        samples.append(raster.delta(r.maxX, y, r.maxX, y - 1))
      }
    }
    return trimmedMean(samples)
  }

  private static func trimmedMean(_ values: [Int]) -> Double {
    guard !values.isEmpty else { return 0 }
    let kept = values.sorted().prefix(max(1, Int(Double(values.count) * noiseTrim)))
    return Double(kept.reduce(0, +)) / Double(kept.count)
  }

  private static func median(_ values: [Int]) -> Int {
    guard !values.isEmpty else { return 0 }
    var sorted = values
    sorted.sort()
    return sorted[sorted.count / 2]
  }

  // MARK: - 1D edge finder

  private struct EdgeFinder {
    let raster: ScreenRulerRaster
    let pixels: UnsafePointer<UInt8>
    /// Smallest deviation from the reference that starts a transition.
    let threshold: Int
    /// Whether single-pixel deviations need the next pixel to agree.
    let isNoisy: Bool

    init(raster: ScreenRulerRaster, pixels: UnsafePointer<UInt8>, tolerance: Int, noise: Double) {
      self.raster = raster
      self.pixels = pixels
      let noiseThreshold = noise > 0 ? Int((noise * ScreenRulerEdgeScanner.noiseFactor).rounded(.up)) + 1 : 0
      threshold = max(tolerance, noiseThreshold)
      isNoisy = noise >= ScreenRulerEdgeScanner.noisyLevel
    }

    /// Matched pixels past the start (0 when the very next pixel is an edge).
    func extent(x: Int, y: Int, dx: Int, dy: Int, count: Int) -> Int {
      guard let index = edgeIndex(x: x, y: y, dx: dx, dy: dy, count: count) else { return count - 1 }
      return index - 1
    }

    /// Index (steps from the start pixel) of the first pixel past the edge, or nil when the
    /// line has no edge. The start pixel itself is index 0 and always matches.
    func edgeIndex(x: Int, y: Int, dx: Int, dy: Int, count: Int) -> Int? {
      guard count > 1 else { return nil }
      // On noisy backgrounds each sample averages three pixels across the scan direction:
      // edges crossing the line stay sharp, noise drops by √3.
      let px = dy
      let py = dx
      let width = raster.width
      let height = raster.height
      let rowBytes = raster.bytesPerRow
      let pixels = pixels
      let smooths = isNoisy
      let origin = y * rowBytes + x * 4
      let stride = dy * rowBytes + dx * 4
      @inline(__always) func value(_ i: Int, _ c: Int) -> Int {
        guard smooths else { return Int(pixels[origin + i * stride + c]) }
        let sx = x + i * dx
        let sy = y + i * dy
        let ax = min(max(sx - px, 0), width - 1)
        let ay = min(max(sy - py, 0), height - 1)
        let bx = min(max(sx + px, 0), width - 1)
        let by = min(max(sy + py, 0), height - 1)
        let sum = Int(pixels[ay * rowBytes + ax * 4 + c]) + Int(pixels[origin + i * stride + c])
          + Int(pixels[by * rowBytes + bx * 4 + c])
        return (sum + 1) / 3
      }

      var reference = Reference(length: ScreenRulerEdgeScanner.referenceLength)
      reference.reset(value(0, 0), value(0, 1), value(0, 2))
      var i = 1
      while i < count {
        let r = value(i, 0)
        let g = value(i, 1)
        let b = value(i, 2)
        guard reference.exceeds(r, g, b, threshold) else {
          reference.add(r, g, b)
          i += 1
          continue
        }
        let (deviation, channel) = reference.deviation(r, g, b)
        var starts = deviation > threshold
        if starts, isNoisy, deviation <= 2 * threshold {
          // A lone noisy pixel: only a transition if the next pixel deviates too.
          starts = i + 1 < count
            && reference.deviation(value(i + 1, 0), value(i + 1, 1), value(i + 1, 2)).0 > threshold
        }
        guard starts else {
          reference.add(value(i, 0), value(i, 1), value(i, 2))
          i += 1
          continue
        }

        let transition = examineTransition(at: i, count: count, channel: channel, value: value)
        if let edge = transition.edge {
          return edge
        }
        // A soft ramp (shadow, vignette): keep scanning from where it ended.
        i = max(transition.end, i + 1)
        if i < count {
          reference.reset(value(i - 1, 0), value(i - 1, 1), value(i - 1, 2))
        }
      }
      return nil
    }

    /// Walks the monotonic run that starts at `start` (plus one step back the other way, which
    /// is how a shadow meets the element casting it) and picks its sharpest step.
    private func examineTransition(
      at start: Int,
      count: Int,
      channel: Int,
      value: (Int, Int) -> Int
    ) -> (edge: Int?, end: Int) {
      let direction = value(start, channel) >= value(start - 1, channel) ? 1 : -1
      var steps: [(index: Int, size: Int)] = []
      var terminal: (index: Int, size: Int)?
      var j = start
      while j < count, j - start < ScreenRulerEdgeScanner.maxTransitionLength {
        let step = value(j, channel) - value(j - 1, channel)
        if step * direction > 0 {
          steps.append((j, abs(step)))
          j += 1
          continue
        }
        if step * direction < 0, abs(step) > threshold {
          terminal = (j, abs(step))
        }
        break
      }

      // The sharpest step; an anti-aliased edge splits it over two neighboring pixels.
      var bestIndex: Int?
      var bestStrength = 0
      var bestStart = 0
      var bestEnd = 0
      var paired: Set<Int> = []
      for (offset, step) in steps.enumerated() {
        let neighbor = offset + 1 < steps.count ? steps[offset + 1].size : 0
        let strength = step.size + neighbor
        if strength > bestStrength {
          bestStrength = strength
          bestIndex = offset
          bestStart = step.index
          bestEnd = neighbor > 0 ? step.index + 1 : step.index
        }
      }
      if let bestIndex {
        paired = [bestIndex]
        if bestEnd > bestStart { paired.insert(bestIndex + 1) }
      }
      let end = terminal.map { $0.index } ?? j
      let ratio = ScreenRulerEdgeScanner.sharpnessRatio
      // A step is sharp when it towers over the steps right next to it: the middle of a
      // blurred shadow has a large step too, but its neighbors are almost as large.
      if let bestIndex, bestStrength > threshold {
        // On noisy backgrounds the neighbors carry noise; only what exceeds it is slope.
        let noiseFloor = isNoisy ? threshold : 0
        let before = bestIndex > 0 ? max(0, steps[bestIndex - 1].size - noiseFloor) : 0
        let afterOffset = bestIndex + paired.count
        let after = afterOffset < steps.count ? max(0, steps[afterOffset].size - noiseFloor) : 0
        // ...so a sharp step in the run itself (an edge, a hairline) is the edge...
        // Per step: an anti-aliased pair is compared step for step, not as one big jump.
        if bestStrength >= ratio * max(before, after) * paired.count {
          return (refine(start: bestStart, end: bestEnd, count: count, channel: channel, value: value), end)
        }
      }
      // ...otherwise the run is a soft ramp, and a sharp step back the other way is the element
      // that casts it (a card at the end of its shadow).
      if let terminal, terminal.size > threshold, terminal.size >= ratio * (steps.last?.size ?? 0) {
        return (refine(start: terminal.index, end: terminal.index, count: count, channel: channel, value: value), end)
      }
      return (nil, end)
    }

    /// The first pixel past the edge: the transition's first pixel, unless the scanned side
    /// covers at least half of it.
    private func refine(start: Int, end: Int, count: Int, channel: Int, value: (Int, Int) -> Int) -> Int {
      let after = min(end + (end > start ? 0 : 1), count - 1)
      guard after > start else { return start }
      let before = value(start - 1, channel)
      let partial = value(start, channel)
      let settled = value(after, channel)
      let span = settled - before
      guard span != 0, (partial - before) * span >= 0, (settled - partial) * span >= 0 else { return start }
      let coverageOfScannedSide = Double(settled - partial) / Double(span)
      return coverageOfScannedSide >= 0.5 ? start + 1 : start
    }
  }

  /// Running mean of the last four matched pixels, in fixed storage (it is reset per line,
  /// so it must not allocate).
  private struct Reference {
    private var reds = SIMD4<Int32>()
    private var greens = SIMD4<Int32>()
    private var blues = SIMD4<Int32>()
    private var count = 0
    private var next = 0
    private var sum = (0, 0, 0)

    init(length: Int) {
      precondition(length == 4, "Reference keeps exactly four pixels")
    }

    mutating func reset(_ r: Int, _ g: Int, _ b: Int) {
      reds = SIMD4(repeating: 0)
      greens = SIMD4(repeating: 0)
      blues = SIMD4(repeating: 0)
      reds[0] = Int32(r)
      greens[0] = Int32(g)
      blues[0] = Int32(b)
      count = 1
      next = 1
      sum = (r, g, b)
    }

    mutating func add(_ r: Int, _ g: Int, _ b: Int) {
      if count < 4 {
        count += 1
      } else {
        sum.0 -= Int(reds[next])
        sum.1 -= Int(greens[next])
        sum.2 -= Int(blues[next])
      }
      reds[next] = Int32(r)
      greens[next] = Int32(g)
      blues[next] = Int32(b)
      next = (next + 1) & 3
      sum.0 += r
      sum.1 += g
      sum.2 += b
    }

    /// Whether any channel is more than `threshold` from the mean (no division).
    @inline(__always)
    func exceeds(_ r: Int, _ g: Int, _ b: Int, _ threshold: Int) -> Bool {
      let limit = threshold * count
      return abs(r * count - sum.0) > limit || abs(g * count - sum.1) > limit || abs(b * count - sum.2) > limit
    }

    /// Largest channel deviation from the mean, and which channel it is in.
    func deviation(_ r: Int, _ g: Int, _ b: Int) -> (Int, Int) {
      let n = count
      let dr = abs(r * n - sum.0) / n
      let dg = abs(g * n - sum.1) / n
      let db = abs(b * n - sum.2) / n
      if dr >= dg, dr >= db { return (dr, 0) }
      return dg >= db ? (dg, 1) : (db, 2)
    }
  }
}
