//
//  scrolling-capture-accuracy-metrics.swift
//  Snapzy
//
//  Pixel comparison helpers for Scroll Capture accuracy benchmark.
//

import Foundation

func scrollAccuracyCompare(
  output: ScrollAccuracyRGBA,
  expected: ScrollAccuracyRGBA,
  seamRows: [Int]
) -> ScrollAccuracyMetrics {
  guard output.width == expected.width else {
    return ScrollAccuracyMetrics(exactAccuracy: 0, overallAccuracy: 0, meanAbsoluteError: 255, maxSeamError: 255)
  }

  let comparedHeight = min(output.height, expected.height)
  let totalHeight = max(output.height, expected.height)
  var exactPixels = 0
  var absoluteError = 0
  var comparedChannels = 0

  for y in 0..<comparedHeight {
    for x in 0..<output.width {
      let index = y * output.bytesPerRow + x * 4
      let dr = abs(Int(output.pixels[index]) - Int(expected.pixels[index]))
      let dg = abs(Int(output.pixels[index + 1]) - Int(expected.pixels[index + 1]))
      let db = abs(Int(output.pixels[index + 2]) - Int(expected.pixels[index + 2]))
      if dr == 0, dg == 0, db == 0 { exactPixels += 1 }
      absoluteError += dr + dg + db
      comparedChannels += 3
    }
  }

  let comparedPixels = max(1, output.width * comparedHeight)
  let totalPixels = max(1, output.width * totalHeight)
  let maxSeamError = seamRows.map {
    seamError(output: output, expected: expected, centerRow: $0)
  }.max() ?? 0

  return ScrollAccuracyMetrics(
    exactAccuracy: Double(exactPixels) / Double(comparedPixels),
    overallAccuracy: Double(exactPixels) / Double(totalPixels),
    meanAbsoluteError: Double(absoluteError) / Double(max(1, comparedChannels)),
    maxSeamError: maxSeamError
  )
}

private func seamError(output: ScrollAccuracyRGBA, expected: ScrollAccuracyRGBA, centerRow: Int) -> Double {
  let start = max(0, centerRow - 3)
  let end = min(min(output.height, expected.height), centerRow + 4)
  guard start < end else { return 255 }
  var total = 0
  var count = 0

  for y in start..<end {
    for x in 0..<output.width {
      let index = y * output.bytesPerRow + x * 4
      total += abs(Int(output.pixels[index]) - Int(expected.pixels[index]))
      total += abs(Int(output.pixels[index + 1]) - Int(expected.pixels[index + 1]))
      total += abs(Int(output.pixels[index + 2]) - Int(expected.pixels[index + 2]))
      count += 3
    }
  }

  return Double(total) / Double(max(1, count))
}

func emptyFailure(for benchmark: ScrollAccuracyBenchmarkCase) -> ScrollAccuracyBenchmarkResult {
  let metrics = ScrollAccuracyMetrics(exactAccuracy: 0, overallAccuracy: 0, meanAbsoluteError: 255, maxSeamError: 255)
  return ScrollAccuracyBenchmarkResult(name: benchmark.name, frameCount: 0, appendedCount: 0, failedCount: 1, outputHeight: 0, expectedHeight: 0, metrics: metrics, averageConfidence: 0, passed: false)
}

func percent(_ value: Double) -> String {
  String(format: "%.3f%%", value * 100)
}

func number(_ value: Double) -> String {
  String(format: "%.3f", value)
}
